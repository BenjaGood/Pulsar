//
//  OuraDataMapper.swift
//  Pulsar
//

import Foundation

struct OuraDataMapper {
    var calendar: Calendar = .current
    var targetSleepHours: Double = SleepSchedule.standard.targetSleepHours

    func map(bundle: OuraRawSyncBundle, for date: Date, syncedAt: Date = Date()) -> OuraMappedHealthData {
        let dayKey = OuraDateParser.dayString(for: date, calendar: calendar)
        let dailySleep = bundle.dailySleep.first { $0.day == dayKey }
        let sleepPeriod = primarySleepPeriod(in: bundle.sleepPeriods.filter { $0.day == dayKey })
        let readiness = bundle.dailyReadiness.first { $0.day == dayKey }
        let activity = bundle.dailyActivity.first { $0.day == dayKey }
        let spo2 = bundle.dailySpo2.first { $0.day == dayKey }
        let dailyStress = bundle.dailyStress.first { $0.day == dayKey }
        let dailyResilience = bundle.dailyResilience.first { $0.day == dayKey }
        let workouts = bundle.workouts.filter { ($0.day ?? dayKey) == dayKey }
        let dayHeartRates = heartRates(bundle.heartRates, on: date)

        let sleepMetric = makeSleepMetric(dailySleep: dailySleep, sleepPeriod: sleepPeriod, date: date, syncedAt: syncedAt)
        let recoveryMetric = makeRecoveryMetric(readiness: readiness, sleep: sleepPeriod, sleepMetric: sleepMetric, spo2: spo2, syncedAt: syncedAt)
        let strainMetric = makeStrainMetric(activity: activity, workouts: workouts, heartRates: dayHeartRates, date: date, syncedAt: syncedAt)
        let stressMetric = makeStressMetric(
            dailyStress: dailyStress,
            resilience: dailyResilience,
            sleepMetric: sleepMetric,
            recoveryMetric: recoveryMetric,
            strainMetric: strainMetric,
            heartRates: dayHeartRates,
            workouts: workouts,
            syncedAt: syncedAt
        )
        let healthMonitorMetric = makeHealthMonitorMetric(
            readiness: readiness,
            sleep: sleepPeriod,
            sleepMetric: sleepMetric,
            spo2: spo2,
            heartRates: dayHeartRates,
            syncedAt: syncedAt
        )
        let samples = makeCanonicalSamples(
            sleepMetric: sleepMetric,
            recoveryMetric: recoveryMetric,
            strainMetric: strainMetric,
            stressMetric: stressMetric,
            healthMonitorMetric: healthMonitorMetric,
            heartRates: dayHeartRates,
            workouts: workouts,
            syncedAt: syncedAt
        )

        let payload = PulsarDailyMetricsSyncPayload(
            date: calendar.startOfDay(for: date),
            dateKey: PulsarDailyMetricsDateKey.dateKey(for: date, calendar: calendar),
            syncedAt: syncedAt,
            sourceDevice: .ouraRing,
            strain: strainMetric,
            recovery: recoveryMetric,
            sleep: sleepMetric,
            stress: stressMetric,
            healthMonitor: healthMonitorMetric,
            syncSessionID: UUID(),
            validityFlag: true
        )

        return OuraMappedHealthData(
            payload: payload.isValidPayload ? payload : nil,
            samples: samples,
            ringBatteryPercentage: nil,
            mappedAt: syncedAt
        )
    }

    private func primarySleepPeriod(in periods: [OuraSleepPeriod]) -> OuraSleepPeriod? {
        periods
            .filter { $0.type != "deleted" && $0.type != "rest" }
            .sorted { lhs, rhs in
                let lhsDuration = lhs.totalSleepDuration ?? 0
                let rhsDuration = rhs.totalSleepDuration ?? 0
                if lhs.type == "long_sleep", rhs.type != "long_sleep" { return true }
                if rhs.type == "long_sleep", lhs.type != "long_sleep" { return false }
                return lhsDuration > rhsDuration
            }
            .first
    }

    private func heartRates(_ heartRates: [OuraHeartRate], on date: Date) -> [OuraHeartRate] {
        guard let interval = calendar.dateInterval(of: .day, for: date) else { return heartRates }
        return heartRates.filter { interval.contains($0.timestamp) }.sorted { $0.timestamp < $1.timestamp }
    }

    private func makeSleepMetric(
        dailySleep: OuraDailySleep?,
        sleepPeriod: OuraSleepPeriod?,
        date: Date,
        syncedAt: Date
    ) -> PulsarSleepSyncMetric? {
        guard let sleepPeriod,
              let score = dailySleep?.score,
              let sleepStart = sleepPeriod.bedtimeStart,
              let sleepEnd = sleepPeriod.bedtimeEnd,
              score > 0 else {
            return nil
        }

        let totalSleepMinutes = max(0, (sleepPeriod.totalSleepDuration ?? 0) / 60)
        let timeInBedMinutes = max(totalSleepMinutes, (sleepPeriod.timeInBed ?? sleepEnd.timeIntervalSince(sleepStart)) / 60)
        guard totalSleepMinutes > 0, timeInBedMinutes > 0, sleepStart < sleepEnd else { return nil }

        let awakeMinutes = max(0, (sleepPeriod.awakeTime ?? max(0, timeInBedMinutes - totalSleepMinutes) * 60) / 60)
        let remMinutes = max(0, (sleepPeriod.remSleepDuration ?? 0) / 60)
        let deepMinutes = max(0, (sleepPeriod.deepSleepDuration ?? 0) / 60)
        let coreMinutes = max(0, (sleepPeriod.lightSleepDuration ?? 0) / 60)
        let stagedSleepMinutes = remMinutes + deepMinutes + coreMinutes
        let asleepUnspecifiedMinutes = max(0, totalSleepMinutes - stagedSleepMinutes)
        let sleepEfficiency = ScoreMath.clamp(Double(sleepPeriod.efficiency ?? Int((totalSleepMinutes / max(1, timeInBedMinutes) * 100).rounded())) / 100)
        let contributors = dailySleep?.contributors
        let stageIntervals = stageIntervals(from: sleepPeriod, sleepStart: sleepStart, sleepEnd: sleepEnd)
        let queryStart = min(sleepStart, sleepStart.addingTimeInterval(-60 * 60))
        let queryEnd = max(sleepEnd, sleepEnd.addingTimeInterval(60 * 60))

        let metric = PulsarSleepSyncMetric(
            score: score,
            confidence: stageIntervals.isEmpty ? .moderate : .high,
            sleepDateKey: SleepWindowResolver.sleepDateKey(forWakeUpDate: date, calendar: calendar),
            wakeUpDate: calendar.startOfDay(for: date),
            sleepStart: sleepStart,
            sleepEnd: sleepEnd,
            queryStart: queryStart,
            queryEnd: queryEnd,
            totalSleepMinutes: totalSleepMinutes,
            timeInBedMinutes: timeInBedMinutes,
            sleepEfficiency: sleepEfficiency,
            awakeMinutes: awakeMinutes,
            wasoMinutes: awakeMinutes,
            remMinutes: remMinutes,
            coreMinutes: coreMinutes,
            deepMinutes: deepMinutes,
            asleepUnspecifiedMinutes: asleepUnspecifiedMinutes,
            awakenings: max(0, sleepPeriod.restlessPeriods ?? 0),
            analyzedSampleCount: max(1, stageIntervals.count),
            sleepConsistency: contributorRatio(contributors?.timing),
            sleepPerformance: contributorRatio(contributors?.totalSleep),
            durationAdequacy: contributorRatio(contributors?.totalSleep),
            regularity: contributorRatio(contributors?.timing),
            continuity: contributorRatio(contributors?.restfulness),
            targetSleepHours: targetSleepHours,
            sourceNames: ["Oura Ring"],
            computedAt: syncedAt,
            stageIntervals: stageIntervals
        )

        return metric.isValid ? metric : nil
    }

    private func stageIntervals(
        from sleepPeriod: OuraSleepPeriod,
        sleepStart: Date,
        sleepEnd: Date
    ) -> [PulsarSleepStageSyncInterval] {
        guard let phases = sleepPeriod.sleepPhase5Min, !phases.isEmpty else { return [] }
        var intervals: [PulsarSleepStageSyncInterval] = []
        var cursor = sleepStart
        var currentStage: SleepStage?
        var currentStart = sleepStart

        func finish(at end: Date) {
            guard let currentStage, currentStart < end else { return }
            intervals.append(PulsarSleepStageSyncInterval(stage: currentStage.rawValue, start: currentStart, end: end))
        }

        for code in phases {
            let stage = stage(for: code)
            let next = min(sleepEnd, cursor.addingTimeInterval(5 * 60))
            if currentStage == nil {
                currentStage = stage
                currentStart = cursor
            } else if currentStage != stage {
                finish(at: cursor)
                currentStage = stage
                currentStart = cursor
            }
            cursor = next
            if cursor >= sleepEnd { break }
        }
        finish(at: min(cursor, sleepEnd))
        return intervals.filter(\.isValid)
    }

    private func stage(for code: Character) -> SleepStage {
        switch code {
        case "1":
            return .deep
        case "2":
            return .core
        case "3":
            return .rem
        case "4":
            return .awake
        default:
            return .asleepUnspecified
        }
    }

    private func makeRecoveryMetric(
        readiness: OuraDailyReadiness?,
        sleep: OuraSleepPeriod?,
        sleepMetric: PulsarSleepSyncMetric?,
        spo2: OuraDailySpo2?,
        syncedAt: Date
    ) -> PulsarRecoverySyncMetric? {
        guard let readiness,
              let score = readiness.score,
              score > 0 else { return nil }

        let oxygenSaturation = validatedValue(normalizedSpo2(spo2?.spo2Percentage?.average), in: 0.5...1)
        let contributors = readiness.contributors
        let restingHeartRate = validatedValue(sleep?.lowestHeartRate, in: 30...120) ??
            validatedValue(sleep?.averageHeartRate, in: 30...120)
        let metric = PulsarRecoverySyncMetric(
            score: score,
            confidence: .high,
            statusText: recoveryStatus(for: score).label,
            hrvSDNN: validatedValue(sleep?.averageHRV, in: 5...250),
            hrvBaseline: nil,
            restingHeartRate: restingHeartRate,
            restingHeartRateBaseline: nil,
            sleepDuration: sleepMetric.map { $0.totalSleepMinutes * 60 },
            sleepEfficiency: sleepMetric?.sleepEfficiency,
            strainScore: nil,
            respiratoryRate: validatedValue(sleep?.respiratoryRate, in: 6...30),
            oxygenSaturation: oxygenSaturation,
            wristTemperatureDeviation: validatedValue(ouraTemperatureTrend(readiness: readiness, sleep: sleep), in: (-10)...10),
            hrvReadiness: contributorRatio(contributors?.hrvBalance),
            restingHeartRateReadiness: contributorRatio(contributors?.restingHeartRate),
            respiratoryStability: contributorRatio(contributors?.bodyTemperature),
            sleepContribution: contributorRatio(contributors?.previousNight ?? contributors?.sleepBalance),
            strainPenalty: ScoreMath.clamp(1 - contributorRatio(contributors?.previousDayActivity)),
            sourceNames: ["Oura Ring"],
            computedAt: syncedAt
        )
        return metric.isValid ? metric : nil
    }

    private func makeStrainMetric(
        activity: OuraDailyActivity?,
        workouts: [OuraWorkout],
        heartRates: [OuraHeartRate],
        date: Date,
        syncedAt: Date
    ) -> PulsarStrainSyncMetric? {
        guard let activity else { return nil }

        let activeHeartRates = heartRates.filter { ($0.source ?? "").lowercased() != "sleep" }
        let heartContext = PulsarSharedMetricCalculator.heartRateContext(
            samples: heartRateSamples(from: activeHeartRates),
            restingHeartRate: nil,
            maxHeartRate: nil
        )
        let workoutInputs = workouts.compactMap { workout -> PulsarSharedWorkoutInput? in
            guard let start = workout.startDateTime,
                  let end = workout.endDateTime,
                  end > start else { return nil }
            return PulsarSharedWorkoutInput(
                type: workout.label ?? workout.activity ?? workout.intensity ?? "Oura workout",
                durationMinutes: end.timeIntervalSince(start) / 60,
                activeEnergyKilocalories: validatedValue(workout.calories, in: 0...5_000),
                distanceMeters: validatedValue(workout.distance, in: 0...500_000),
                averageHeartRate: nil,
                peakHeartRate: nil,
                sourceName: "Oura Ring"
            )
        }
        let activeCalories = validatedValue(activity.activeCalories, in: 0...20_000) ?? 0
        let basalCalories = validatedValue(activity.totalCalories, in: 0...20_000).map { max(0, $0 - activeCalories) }
        var metric = PulsarSharedMetricCalculator.makeStrainMetric(
            activity: PulsarSharedActivityInput(
                steps: Double(max(0, activity.steps ?? 0)),
                activeEnergyKilocalories: activeCalories,
                basalEnergyKilocalories: basalCalories,
                distanceMeters: validatedValue(activity.equivalentWalkingDistance, in: 0...500_000) ?? 0,
                exerciseMinutes: max(0, ((activity.highActivityTime ?? 0) + (activity.mediumActivityTime ?? 0)) / 60),
                elevatedHeartRateMinutes: heartContext.elevatedMinutes,
                moderateHeartRateMinutes: heartContext.moderateMinutes,
                vigorousHeartRateMinutes: heartContext.vigorousMinutes,
                zone1Minutes: heartContext.zone1Minutes,
                zone2Minutes: heartContext.zone2Minutes,
                zone3Minutes: heartContext.zone3Minutes,
                zone4Minutes: heartContext.zone4Minutes,
                zone5Minutes: heartContext.zone5Minutes,
                averageElevatedHeartRate: heartContext.averageElevatedHeartRate,
                peakHeartRate: heartContext.peakHeartRate,
                sourceName: "Oura Ring"
            ),
            workouts: workoutInputs,
            recentRawLoads: [],
            computedAt: syncedAt
        )
        let activeHeartRateCount = activeHeartRates.count
        metric?.activitySampleCount = 1
        metric?.heartRateSampleCount = activeHeartRateCount
        metric?.workoutSampleCount = workoutInputs.count
        metric?.analyzedSampleCount = 1 + activeHeartRateCount + workoutInputs.count
        PulsarOuraLogger.log("Oura strain mapped from load activityScore=\(activity.score.map(String.init) ?? "nil") steps=\(activity.steps ?? 0) activeCalories=\(String(format: "%.1f", activeCalories)) workouts=\(workoutInputs.count) activeHRRows=\(activeHeartRateCount) finalStrain=\(metric.map { String($0.score) } ?? "nil")")
        return metric
    }

    private func heartRateSamples(from heartRates: [OuraHeartRate]) -> [PulsarSharedHeartRateSample] {
        heartRates
            .filter { (30...260).contains($0.bpm) }
            .sorted { $0.timestamp < $1.timestamp }
            .map { heartRate in
                PulsarSharedHeartRateSample(
                    start: heartRate.timestamp,
                    end: heartRate.timestamp.addingTimeInterval(60),
                    bpm: heartRate.bpm
                )
            }
    }

    private func makeHealthMonitorMetric(
        readiness: OuraDailyReadiness?,
        sleep: OuraSleepPeriod?,
        sleepMetric: PulsarSleepSyncMetric?,
        spo2: OuraDailySpo2?,
        heartRates: [OuraHeartRate],
        syncedAt: Date
    ) -> PulsarHealthMonitorSyncMetric? {
        var metrics: [PulsarHealthMetricSyncValue] = []
        let restingHeartRate = healthMonitorValue(.restingHeartRate, value: sleep?.lowestHeartRate) ??
            healthMonitorValue(.restingHeartRate, value: sleep?.averageHeartRate) ??
            restingHeartRateEstimate(from: heartRates)
        metrics.append(healthValue(.respiratoryRate, value: healthMonitorValue(.respiratoryRate, value: sleep?.respiratoryRate), status: .normal, comparison: "From Oura overnight breathing trend."))
        metrics.append(healthValue(.restingHeartRate, value: restingHeartRate, status: .normal, comparison: "From Oura sleep or rest heart-rate samples."))
        metrics.append(healthValue(.hrv, value: healthMonitorValue(.hrv, value: sleep?.averageHRV), status: .normal, comparison: "From Oura overnight HRV."))
        metrics.append(healthValue(.oxygenSaturation, value: healthMonitorValue(.oxygenSaturation, value: normalizedSpo2(spo2?.spo2Percentage?.average)), status: .normal, comparison: "From Oura sleep SpO2 average when available."))
        metrics.append(healthValue(.wristTemperature, value: healthMonitorValue(.wristTemperature, value: ouraTemperatureTrend(readiness: readiness, sleep: sleep)), status: .normal, comparison: "Nighttime temperature vs baseline from Oura. Shown as a deviation, not absolute body temperature."))
        metrics.append(healthValue(.sleep, value: sleepMetric?.totalSleepMinutes, status: .normal, comparison: "From Oura sleep summary."))

        let metric = PulsarHealthMonitorSyncMetric(
            metrics: metrics,
            baselineWindowDays: 0,
            sourceNames: ["Oura Ring"],
            computedAt: syncedAt
        )
        return metric.isValid ? metric : nil
    }

    private func restingHeartRateEstimate(from heartRates: [OuraHeartRate]) -> Double? {
        let candidates = heartRates
            .filter { sample in
                guard let source = sample.source?.lowercased() else { return false }
                return source == "sleep" || source == "rest"
            }
            .map(\.bpm)
            .filter { (25...160).contains($0) }
            .sorted()
        guard candidates.count >= 3 else { return nil }
        return candidates[max(0, candidates.count / 10)]
    }

    private func makeStressMetric(
        dailyStress: OuraDailyStress?,
        resilience: OuraDailyResilience?,
        sleepMetric: PulsarSleepSyncMetric?,
        recoveryMetric: PulsarRecoverySyncMetric?,
        strainMetric: PulsarStrainSyncMetric?,
        heartRates: [OuraHeartRate],
        workouts: [OuraWorkout],
        syncedAt: Date
    ) -> PulsarStressSyncMetric? {
        let rawMetric = makeRawOuraStressMetric(
            dailyStress: dailyStress,
            resilience: resilience,
            sleepMetric: sleepMetric,
            recoveryMetric: recoveryMetric,
            heartRates: heartRates,
            workouts: workouts,
            syncedAt: syncedAt
        )
        if var rawMetric {
            let vendorInsights = ouraDailyStressInsights(dailyStress: dailyStress, resilience: resilience)
            rawMetric.driverInsights = Array((rawMetric.driverInsights + vendorInsights).prefix(4))
            let timeline = makeOuraStressTimeline(
                metric: rawMetric,
                heartRates: heartRates,
                recoveryMetric: recoveryMetric,
                workouts: workouts
            )
            if timeline.count >= 2 {
                rawMetric.timelineSamples = timeline
            }
            let zoneDurations = PulsarStressTimelineDistribution.buckets(
                samples: rawMetric.timelineSamples.map { PulsarStressTimelineSample(timestamp: $0.timestamp, score: $0.score) }
            )
                .map { "\($0.category.rawValue)=\(Int(($0.duration / 60).rounded()))m" }
                .joined(separator: ",")
            let activeHeartRateCount = heartRates.filter { ($0.source ?? "").lowercased() != "sleep" }.count
            let sleepHeartRateCount = heartRates.count - activeHeartRateCount
            PulsarOuraLogger.log("Oura raw stress mapped currentHR=\(rawMetric.recentHeartRate.map { String(format: "%.1f", $0) } ?? "nil") HRV=\(rawMetric.hrvSDNN.map { String(format: "%.1f", $0) } ?? "nil") RHR=\(rawMetric.restingHeartRate.map { String(format: "%.1f", $0) } ?? "nil") activeHRRows=\(activeHeartRateCount) sleepHRRows=\(sleepHeartRateCount) workouts=\(workouts.count) dailyStressRows=\(dailyStress == nil ? 0 : 1) finalCurrentStress=\(rawMetric.score) dailyAverageStress=\(PulsarStressTimelineDistribution.weightedAverage(samples: rawMetric.timelineSamples.map { PulsarStressTimelineSample(timestamp: $0.timestamp, score: $0.score) }).map { String(format: "%.1f", $0) } ?? "nil") zoneDurations=\(zoneDurations.isEmpty ? "none" : zoneDurations) samples=\(rawMetric.timelineSamples.count)")
            return rawMetric.isValid ? rawMetric : nil
        }

        return nil
    }

    private func makeRawOuraStressMetric(
        dailyStress: OuraDailyStress?,
        resilience: OuraDailyResilience?,
        sleepMetric: PulsarSleepSyncMetric?,
        recoveryMetric: PulsarRecoverySyncMetric?,
        heartRates: [OuraHeartRate],
        workouts: [OuraWorkout],
        syncedAt: Date
    ) -> PulsarStressSyncMetric? {
        let activeHeartRates = heartRates.filter { ($0.source ?? "").lowercased() != "sleep" }
        let recentHeartRate = activeHeartRates.last ?? heartRates.last
        let activeWorkout = workouts.contains { workout in
            guard let start = workout.startDateTime, let end = workout.endDateTime else { return false }
            return start <= syncedAt && end >= syncedAt
        }
        let latestWorkoutEnd = workouts
            .compactMap(\.endDateTime)
            .filter { $0 <= syncedAt }
            .max()
        let hrv = recoveryMetric?.hrvSDNN
        let restingHeartRate = recoveryMetric?.restingHeartRate
        guard recentHeartRate != nil || hrv != nil || restingHeartRate != nil else { return nil }

        return PulsarSharedMetricCalculator.makeStressMetric(
            today: PulsarSharedStressInput(
                date: syncedAt,
                hrvSDNN: hrv,
                hrvTimestamp: hrv == nil ? nil : recoveryMetric?.computedAt,
                restingHeartRate: restingHeartRate,
                respiratoryRate: recoveryMetric?.respiratoryRate,
                recentHeartRate: recentHeartRate?.bpm,
                heartRateTimestamp: recentHeartRate?.timestamp,
                daytimeHeartRate: activeHeartRates.isEmpty ? nil : activeHeartRates.map(\.bpm).reduce(0, +) / Double(activeHeartRates.count),
                sleepDurationMinutes: sleepMetric?.totalSleepMinutes,
                sleepPerformance: nil,
                strainScore: nil,
                recentWorkoutLoad: nil,
                isWorkoutActive: activeWorkout,
                lastWorkoutEnd: latestWorkoutEnd,
                recentSteps: nil,
                recentActiveEnergyKilocalories: nil,
                recentExerciseMinutes: nil,
                movementState: .unknown,
                previousScore: nil,
                sourceNames: ["Oura Ring"]
            ),
            baselineDays: [],
            sleep: sleepMetric,
            strain: nil,
            computedAt: syncedAt
        )
    }

    private func makeOuraStressTimeline(
        metric: PulsarStressSyncMetric,
        heartRates: [OuraHeartRate],
        recoveryMetric: PulsarRecoverySyncMetric?,
        workouts: [OuraWorkout]
    ) -> [PulsarStressSyncSample] {
        let activeHeartRates = heartRates
            .filter { ($0.source ?? "").lowercased() != "sleep" && $0.bpm.isFinite && $0.bpm > 30 && $0.bpm < 220 }
            .sorted { $0.timestamp < $1.timestamp }
        guard activeHeartRates.count >= 2 else { return metric.timelineSamples }

        let sampled = downsample(activeHeartRates, maximumCount: 48)
        let bpmValues = activeHeartRates.map(\.bpm)
        let resting = recoveryMetric?.restingHeartRate ?? percentile(bpmValues, fraction: 0.20) ?? max(45, (metric.recentHeartRate ?? 65) - 12)
        let daytime = max(resting + 8, robustAverage(bpmValues) ?? resting + 16)
        let spread = max(8, standardDeviation(bpmValues) * 0.60)
        let scoreOffset = (Double(metric.score) - 50) * 0.10

        let timeline = sampled.map { sample -> PulsarStressSyncSample in
            let context = ouraTimelineContext(at: sample.timestamp, source: sample.source, workouts: workouts)
            let expected: Double
            let base: Double
            let multiplier: Double
            let cap: Double?
            switch context {
            case "workout":
                expected = daytime + 30
                base = 8
                multiplier = 0
                cap = 12
            case "cooldown":
                expected = daytime + 8
                base = 24
                multiplier = 4
                cap = 42
            case "movementFiltered", "active":
                expected = daytime
                base = 34
                multiplier = 4.5
                cap = 56
            default:
                expected = resting + 5
                base = 27
                multiplier = 8
                cap = nil
            }

            let residual = ScoreMath.clamp((sample.bpm - expected) / spread, -2.2, 2.6)
            var score = PulsarStressScale.clampedScore(base + residual * multiplier + scoreOffset)
            if let cap {
                score = min(score, cap)
            }
            return PulsarStressSyncSample(timestamp: sample.timestamp, score: score, context: context)
        }

        return timeline.count >= 2 ? timeline : metric.timelineSamples
    }

    private func ouraTimelineContext(at timestamp: Date, source: String?, workouts: [OuraWorkout]) -> String {
        if workouts.contains(where: { workout in
            guard let start = workout.startDateTime, let end = workout.endDateTime else { return false }
            return start <= timestamp && end >= timestamp
        }) {
            return "workout"
        }
        if let latestWorkoutEnd = workouts
            .compactMap(\.endDateTime)
            .filter({ $0 <= timestamp })
            .max(),
           timestamp.timeIntervalSince(latestWorkoutEnd) <= 12 * 60 {
            return "cooldown"
        }

        let normalizedSource = (source ?? "").lowercased()
        if normalizedSource.contains("workout") || normalizedSource.contains("activity") {
            return "active"
        }
        if normalizedSource.contains("awake") {
            return "rest"
        }
        return "unknown"
    }

    private func downsample(_ samples: [OuraHeartRate], maximumCount: Int) -> [OuraHeartRate] {
        guard samples.count > maximumCount, maximumCount > 1 else { return samples }
        let stride = max(1, samples.count / maximumCount)
        var reduced = samples.enumerated().compactMap { index, sample in
            index.isMultiple(of: stride) || index == samples.count - 1 ? sample : nil
        }
        if reduced.first?.timestamp != samples.first?.timestamp {
            reduced.insert(samples[0], at: 0)
        }
        var limited = Array(reduced.prefix(max(1, maximumCount - 1)))
        if limited.last?.timestamp != samples.last?.timestamp {
            limited.append(samples[samples.count - 1])
        }
        return limited
    }

    private func robustAverage(_ values: [Double]) -> Double? {
        let sorted = values.filter { $0.isFinite }.sorted()
        guard !sorted.isEmpty else { return nil }
        if sorted.count >= 5 {
            let trimmed = sorted.dropFirst().dropLast()
            return trimmed.reduce(0, +) / Double(trimmed.count)
        }
        return sorted.reduce(0, +) / Double(sorted.count)
    }

    private func percentile(_ values: [Double], fraction: Double) -> Double? {
        let sorted = values.filter { $0.isFinite }.sorted()
        guard !sorted.isEmpty else { return nil }
        let index = Int((Double(sorted.count - 1) * ScoreMath.clamp(fraction)).rounded(.down))
        return sorted[min(sorted.count - 1, max(0, index))]
    }

    private func standardDeviation(_ values: [Double]) -> Double {
        let values = values.filter { $0.isFinite }
        guard values.count >= 2 else { return 8 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(max(1, values.count - 1))
        return sqrt(variance)
    }

    private func ouraDailyStressInsights(
        dailyStress: OuraDailyStress?,
        resilience: OuraDailyResilience?
    ) -> [String] {
        var insights: [String] = []
        if let summary = dailyStress?.daySummary {
            insights.append("Oura daily stress context: \(summary).")
        }
        if let resilienceLevel = resilience?.level {
            insights.append("Oura resilience context: \(resilienceLevel).")
        }
        let stressHigh = max(0, dailyStress?.stressHigh ?? 0)
        if stressHigh > 0 {
            insights.append("\(Int((stressHigh / 60).rounded())) high-stress minutes from Oura daily summary.")
        }
        return insights
    }

    private func healthValue(
        _ kind: PulsarHealthMetricSyncKind,
        value: Double?,
        status: PulsarHealthMetricSyncStatus,
        comparison: String
    ) -> PulsarHealthMetricSyncValue {
        PulsarHealthMetricSyncValue(
            kind: kind,
            value: value,
            status: value == nil ? .noData : status,
            baselineValue: nil,
            comparisonText: value == nil ? missingHealthValueText(for: kind) : comparison,
            sourceNames: ["Oura Ring"]
        )
    }

    private func ouraTemperatureTrend(readiness: OuraDailyReadiness?, sleep: OuraSleepPeriod?) -> Double? {
        readiness?.temperatureTrendDeviation ??
            readiness?.temperatureDeviation ??
            sleep?.temperatureTrendDeviation ??
            sleep?.temperatureDeviation
    }

    private func makeCanonicalSamples(
        sleepMetric: PulsarSleepSyncMetric?,
        recoveryMetric: PulsarRecoverySyncMetric?,
        strainMetric: PulsarStrainSyncMetric?,
        stressMetric: PulsarStressSyncMetric?,
        healthMonitorMetric: PulsarHealthMonitorSyncMetric?,
        heartRates: [OuraHeartRate],
        workouts: [OuraWorkout],
        syncedAt: Date
    ) -> [CanonicalHealthSample] {
        var samples: [CanonicalHealthSample] = []
        if let sleepMetric {
            samples.append(sample(metric: .sleep, recordID: "oura-sleep-\(sleepMetric.sleepDateKey)", start: sleepMetric.sleepStart, end: sleepMetric.sleepEnd, value: sleepMetric.totalSleepMinutes, unit: "min", syncedAt: syncedAt))
        }
        if let recoveryMetric {
            samples.append(sample(metric: .recovery, recordID: "oura-recovery-\(recoveryMetric.computedAt.timeIntervalSinceReferenceDate)", start: recoveryMetric.computedAt, value: Double(recoveryMetric.score), unit: "score", syncedAt: syncedAt))
            if let hrv = recoveryMetric.hrvSDNN {
                samples.append(sample(metric: .hrv, recordID: "oura-hrv-\(recoveryMetric.computedAt.timeIntervalSinceReferenceDate)", start: recoveryMetric.computedAt, value: hrv, unit: "ms", syncedAt: syncedAt))
            }
            if let restingHeartRate = recoveryMetric.restingHeartRate {
                samples.append(sample(metric: .restingHeartRate, recordID: "oura-rhr-\(recoveryMetric.computedAt.timeIntervalSinceReferenceDate)", start: recoveryMetric.computedAt, value: restingHeartRate, unit: "bpm", syncedAt: syncedAt))
            }
        }
        if let strainMetric {
            samples.append(sample(metric: .activity, recordID: "oura-activity-\(strainMetric.computedAt.timeIntervalSinceReferenceDate)", start: strainMetric.computedAt, value: Double(strainMetric.steps), unit: "steps", syncedAt: syncedAt))
        }
        if let stressMetric {
            samples.append(sample(metric: .stress, recordID: "oura-stress-\(stressMetric.computedAt.timeIntervalSinceReferenceDate)", start: stressMetric.computedAt, value: Double(stressMetric.score), unit: "score", syncedAt: syncedAt))
        }
        if let healthMonitorMetric {
            for value in healthMonitorMetric.metrics where value.value != nil {
                samples.append(sample(metric: metricType(for: value.kind), recordID: "oura-\(value.kind.rawValue)-\(healthMonitorMetric.computedAt.timeIntervalSinceReferenceDate)", start: healthMonitorMetric.computedAt, value: value.value, unit: nil, syncedAt: syncedAt))
            }
        }
        for heartRate in heartRates {
            samples.append(sample(metric: .heartRate, recordID: "oura-hr-\(heartRate.timestamp.timeIntervalSinceReferenceDate)", start: heartRate.timestamp, value: heartRate.bpm, unit: "bpm", syncedAt: syncedAt))
        }
        for workout in workouts {
            guard let start = workout.startDateTime, let end = workout.endDateTime else { continue }
            samples.append(sample(metric: .workouts, recordID: workout.id ?? "oura-workout-\(start.timeIntervalSinceReferenceDate)", start: start, end: end, value: workout.calories, unit: "kcal", syncedAt: syncedAt))
        }
        return samples
    }

    private func sample(
        metric: MeasurementHealthMetricType,
        recordID: String,
        start: Date,
        end: Date? = nil,
        value: Double?,
        unit: String?,
        syncedAt: Date
    ) -> CanonicalHealthSample {
        CanonicalHealthSample(
            id: "oura:\(metric.rawValue):\(recordID)",
            metric: metric,
            sourceID: .ouraRing,
            sourceRecordID: recordID,
            startAt: start,
            endAt: end,
            value: value,
            unit: unit,
            syncedAt: syncedAt
        )
    }

    private func metricType(for kind: PulsarHealthMetricSyncKind) -> MeasurementHealthMetricType {
        switch kind {
        case .respiratoryRate:
            return .respiratoryRate
        case .restingHeartRate:
            return .restingHeartRate
        case .hrv:
            return .hrv
        case .oxygenSaturation:
            return .oxygenSaturation
        case .wristTemperature:
            return .temperature
        case .sleep:
            return .sleep
        }
    }

    private func contributorRatio(_ value: Int?) -> Double {
        ScoreMath.clamp(Double(value ?? 70) / 100)
    }

    private func normalizedSpo2(_ value: Double?) -> Double? {
        guard let value else { return nil }
        if value > 1 {
            return value / 100
        }
        return value
    }

    private func healthMonitorValue(_ kind: PulsarHealthMetricSyncKind, value: Double?) -> Double? {
        switch kind {
        case .respiratoryRate:
            return validatedValue(value, in: 4...40)
        case .restingHeartRate:
            return validatedValue(value, in: 25...160)
        case .hrv:
            return validatedValue(value, in: 5...250)
        case .oxygenSaturation:
            return validatedValue(value, in: 0.5...1)
        case .wristTemperature:
            return validatedValue(value, in: (-10)...10)
        case .sleep:
            return validatedValue(value, in: 0...1_440)
        }
    }

    private func validatedValue(_ value: Double?, in range: ClosedRange<Double>) -> Double? {
        guard let value, value.isFinite, range.contains(value) else { return nil }
        return value
    }

    private func missingHealthValueText(for kind: PulsarHealthMetricSyncKind) -> String {
        switch kind {
        case .respiratoryRate:
            return "Oura did not provide a valid overnight respiratory-rate sample for this day."
        case .restingHeartRate:
            return "Oura did not provide a valid sleep/rest resting-heart-rate sample for this day."
        case .hrv:
            return "Oura did not provide a valid overnight HRV sample for this day."
        case .oxygenSaturation:
            return "Oura did not provide a valid sleep SpO2 average for this day."
        case .wristTemperature:
            return "Oura did not provide a valid temperature trend for this day."
        case .sleep:
            return "Oura did not provide a valid sleep summary for this day."
        }
    }

    private func resilienceScoreOffset(for level: String?) -> Double {
        switch level?.lowercased() {
        case "exceptional":
            return -12
        case "strong":
            return -8
        case "solid":
            return -4
        case "adequate":
            return 0
        case "limited":
            return 8
        default:
            return 0
        }
    }

    private func recoveryStatus(for score: Int) -> RecoveryStatus {
        switch score {
        case 85...100:
            return .excellent
        case 70..<85:
            return .balanced
        case 60..<70:
            return .moderate
        case 1..<60:
            return .low
        default:
            return .unknown
        }
    }

    private func workoutLoad(for workout: OuraWorkout) -> Double {
        guard let start = workout.startDateTime, let end = workout.endDateTime, end > start else { return 0 }
        let minutes = end.timeIntervalSince(start) / 60
        let multiplier: Double
        switch workout.intensity?.lowercased() {
        case "hard", "high":
            multiplier = 1.2
        case "moderate", "medium":
            multiplier = 0.75
        case "easy", "low":
            multiplier = 0.45
        default:
            multiplier = 0.6
        }
        return min(80, minutes * multiplier)
    }
}
