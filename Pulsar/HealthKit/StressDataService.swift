//
//  StressDataService.swift
//  Pulsar
//

import Foundation
import HealthKit

protocol StressSummaryProviding {
    func stressSummary(
        profile: UserProfile,
        date: Date,
        calendar: Calendar,
        refreshedAt: Date,
        sleep: SleepSummary,
        strain: StrainSummary
    ) async throws -> StressSummary
}

struct StressDataService: StressSummaryProviding {
    var healthKit: HealthKitGateway
    var cache: StressSummaryCache

    init(healthKit: HealthKitGateway = HealthKitGateway(), cache: StressSummaryCache = StressSummaryCache()) {
        self.healthKit = healthKit
        self.cache = cache
    }

    func stressSummary(
        profile: UserProfile,
        date: Date,
        calendar: Calendar,
        refreshedAt: Date,
        sleep: SleepSummary,
        strain: StrainSummary
    ) async throws -> StressSummary {
        let interval = queryInterval(for: date, calendar: calendar, refreshedAt: refreshedAt)
        let dateKey = PulsarDailyMetricsDateKey.dateKey(for: date, calendar: calendar)
        let previousSummary = cache.latestSummary(for: dateKey)
        let previousStressScore = previousSummary?.score
        let previousStressTimestamp = previousSummary?.lastUpdated

        async let biometrics = healthKit.fetchDailyBiometrics(date: date, calendar: calendar)
        async let walkingHeartRate = healthKit.fetchWalkingHeartRateAverage(date: date, calendar: calendar)
        async let heartSamples = healthKit.fetchHeartRateSamples(start: interval.start, end: interval.end)
        async let baseline = baselineSignals(before: interval.start, calendar: calendar)
        async let hrvSample = healthKit.fetchMostRecentQuantitySample(
            identifier: .heartRateVariabilitySDNN,
            unit: .secondUnit(with: .milli),
            start: interval.start,
            end: interval.end
        )

        let values = await (biometrics, walkingHeartRate, heartSamples, baseline, hrvSample)
        let referenceDate = effectiveReferenceDate(
            heartSamples: values.2,
            sleep: sleep,
            strain: strain,
            interval: interval,
            refreshedAt: refreshedAt
        )
        let recentActivityWindow = recentMovementWindow(referenceDate: referenceDate, interval: interval)
        let recentActivity = await healthKit.fetchActivity(start: recentActivityWindow.start, end: recentActivityWindow.end)
        let today = todaySignals(
            date: date,
            biometrics: values.0,
            hrvSample: values.4,
            walkingHeartRate: values.1,
            sleep: sleep,
            strain: strain,
            heartSamples: values.2,
            recentActivity: recentActivity,
            interval: interval,
            referenceDate: referenceDate,
            refreshedAt: refreshedAt,
            previousStressScore: previousStressScore,
            previousStressTimestamp: previousStressTimestamp,
            calendar: calendar
        )
        let inputHash = StressInputFingerprint.make(
            dateKey: dateKey,
            queryStart: interval.start,
            referenceDate: referenceDate,
            today: today,
            baselineDays: values.3,
            heartSamples: values.2,
            sleep: sleep,
            strain: strain
        )

        if let cached = cache.summary(for: dateKey, inputHash: inputHash) {
            PulsarSyncDebugLogger.log("Stress cache hit dateKey=\(dateKey) inputHash=\(inputHash)")
            return cached
        }
        PulsarSyncDebugLogger.log("Stress recalculated dateKey=\(dateKey) reason=input hash changed or cache miss inputHash=\(inputHash)")

        var summary = StressScoringService().summary(today: today, baselineDays: values.3)
        summary.date = date
        summary.queryStart = interval.start
        summary.queryEnd = referenceDate
        summary.lastUpdated = refreshedAt
        summary.dailySamples = StressTimelinePointBuilder().samples(
            summary: summary,
            today: today,
            baseline: StressBaselineBuilder().build(from: values.3),
            heartSamples: values.2,
            sleep: sleep,
            strain: strain,
            interval: interval,
            referenceDate: referenceDate
        )
        summary.dailyAverageScore = dailyAverageStress(from: summary).map(PulsarStressScale.roundedScore)
        logStressPipeline(
            summary: summary,
            dateKey: dateKey,
            today: today,
            baselineDays: values.3,
            referenceDate: referenceDate
        )
        cache.save(summary, for: dateKey, inputHash: inputHash, calculatedAt: refreshedAt)
        return summary
    }

    private func queryInterval(for date: Date, calendar: Calendar, refreshedAt: Date) -> DateInterval {
        let day = calendar.startOfDay(for: date)
        let dayInterval = calendar.dateInterval(of: .day, for: day) ?? DateInterval(start: day, duration: 86_400)
        if calendar.isDate(day, inSameDayAs: refreshedAt) {
            return DateInterval(start: dayInterval.start, end: min(refreshedAt, dayInterval.end))
        }
        return dayInterval
    }

    private func recentMovementWindow(referenceDate: Date, interval: DateInterval) -> DateInterval {
        let end = min(max(referenceDate, interval.start), interval.end)
        let start = max(interval.start, end.addingTimeInterval(-15 * 60))
        return DateInterval(start: start, end: max(start, end))
    }

    private func baselineSignals(before date: Date, calendar: Calendar) async -> [StressDailySignals] {
        guard let start = calendar.date(byAdding: .day, value: -StressBaselineBuilder.rollingWindowDays, to: date) else { return [] }
        let activeEnergyValues = await healthKit.dailyStatisticsCollection(
            identifier: .activeEnergyBurned,
            unit: .kilocalorie(),
            start: start,
            end: date,
            calendar: calendar
        )
        let loadByDay = Dictionary(uniqueKeysWithValues: activeEnergyValues.map { (calendar.startOfDay(for: $0.0), max(0, $0.1 / 8)) })

        var days: [StressDailySignals] = []
        for offset in 1...StressBaselineBuilder.rollingWindowDays {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: date) else { continue }
            let dayStart = calendar.startOfDay(for: day)
            let biometrics = await healthKit.fetchDailyBiometrics(date: dayStart, calendar: calendar)
            let walkingHeartRate = await healthKit.fetchWalkingHeartRateAverage(date: dayStart, calendar: calendar)
            let sleep = await sleepSignals(wakeUpDate: dayStart, calendar: calendar)

            days.append(
                StressDailySignals(
                    date: dayStart,
                    heartRateVariabilitySDNN: biometrics.hrvSDNNMilliseconds,
                    restingHeartRate: biometrics.restingHeartRateBPM,
                    walkingHeartRateAverage: walkingHeartRate?.value,
                    sleepRespiratoryRate: biometrics.respiratoryRate,
                    wristTemperatureDelta: biometrics.wristTemperatureDeviationCelsius,
                    sleepDurationHours: sleep.durationHours,
                    sleepInterruptions: sleep.interruptions,
                    bedtimeConsistency: nil,
                    bedtimeMinutesFromMidnight: sleep.bedtimeMinutesFromMidnight,
                    recentWorkoutLoad: loadByDay[dayStart],
                    strainScore: nil,
                    currentMotionContext: .unknown,
                    currentHeartRate: nil,
                    recentHeartRate: nil,
                    minutesSinceWorkout: nil,
                    overnightWearMinutes: sleep.overnightWearMinutes,
                    motionArtifactLevel: nil,
                    signalQuality: nil,
                    sourceBadges: SourceResolver.uniqueSourceBadges(
                        Array(biometrics.provenance.values) +
                            [walkingHeartRate?.provenance].compactMap { $0 }
                    )
                )
            )
        }
        return days
    }

    private func todaySignals(
        date: Date,
        biometrics: DailyBiometrics,
        hrvSample: (value: Double, start: Date, end: Date, provenance: SourceProvenance)?,
        walkingHeartRate: (value: Double, provenance: SourceProvenance)?,
        sleep: SleepSummary,
        strain: StrainSummary,
        heartSamples: [HeartRateSample],
        recentActivity: DailyActivityInput,
        interval: DateInterval,
        referenceDate: Date,
        refreshedAt: Date,
        previousStressScore: Int?,
        previousStressTimestamp: Date?,
        calendar: Calendar
    ) -> StressDailySignals {
        let referenceDate = min(max(referenceDate, interval.start), interval.end)
        let context = motionContext(strain: strain, referenceDate: referenceDate)
        let recentHeartRate = recentHeartRateContext(from: heartSamples, referenceDate: referenceDate)
        let sleepDurationHours = sleep.totalSleepMinutes > 0 ? sleep.totalSleepMinutes / 60 : nil
        let interruptions = sleep.awakenings > 0 ? Double(sleep.awakenings) : (sleep.wasoMinutes > 0 ? max(1, sleep.wasoMinutes / 12) : nil)
        let overnightWearMinutes = sleep.timeInBedMinutes > 0 ? sleep.timeInBedMinutes : (sleep.totalSleepMinutes > 0 ? sleep.totalSleepMinutes : nil)

        return StressDailySignals(
            date: date,
            computedAt: refreshedAt,
            heartRateVariabilitySDNN: hrvSample?.value ?? biometrics.hrvSDNNMilliseconds,
            heartRateVariabilityTimestamp: hrvSample?.end,
            restingHeartRate: biometrics.restingHeartRateBPM,
            walkingHeartRateAverage: walkingHeartRate?.value,
            sleepRespiratoryRate: biometrics.respiratoryRate,
            wristTemperatureDelta: biometrics.wristTemperatureDeviationCelsius,
            sleepDurationHours: sleepDurationHours,
            sleepInterruptions: interruptions,
            bedtimeConsistency: sleep.sleepConsistency > 0 ? sleep.sleepConsistency : nil,
            bedtimeMinutesFromMidnight: sleep.sleepStart.map { minutesFromMidnight($0, calendar: calendar) },
            recentWorkoutLoad: strain.rawLoad > 0 ? strain.rawLoad : strain.activeEnergyKilocalories.map { max(0, $0 / 8) },
            strainScore: strain.score > 0 ? Double(strain.score) : nil,
            currentMotionContext: context.context,
            currentHeartRate: recentHeartRate.value,
            currentHeartRateTimestamp: recentHeartRate.timestamp,
            recentHeartRate: recentHeartRate.value,
            minutesSinceWorkout: context.minutesSinceWorkout,
            lastWorkoutEnd: context.lastWorkoutEnd,
            recentSteps: recentActivity.steps,
            recentActiveEnergyKilocalories: recentActivity.activeEnergyKilocalories,
            recentExerciseMinutes: recentActivity.exerciseMinutes,
            previousStressScore: previousStressScore,
            previousStressTimestamp: previousStressTimestamp,
            overnightWearMinutes: overnightWearMinutes,
            motionArtifactLevel: nil,
            signalQuality: signalQuality(heartSamples: heartSamples, sleep: sleep, biometrics: biometrics),
            sourceBadges: SourceResolver.uniqueSourceBadges(
                Array(biometrics.provenance.values) +
                    [walkingHeartRate?.provenance].compactMap { $0 } +
                    [hrvSample?.provenance].compactMap { $0 } +
                    heartSamples.map(\.provenance)
            )
        )
    }

    private struct StressSleepSignals {
        var durationHours: Double?
        var interruptions: Double?
        var bedtimeMinutesFromMidnight: Double?
        var overnightWearMinutes: Double?
        var sourceBadges: [SourceProvenance]
    }

    private func sleepSignals(wakeUpDate: Date, calendar: Calendar) async -> StressSleepSignals {
        let window = SleepWindowResolver.window(forWakeUpDate: wakeUpDate, calendar: calendar)
        let segments = await healthKit.fetchSleepSegments(start: window.start, end: window.end)
        let primary = SourceResolver.primarySleepSegments(from: segments, nightStart: window.start, nightEnd: window.end)
        let sleepSegments = primary.filter { $0.stage.isSleep }
        let sourceBadges = SourceResolver.uniqueSourceBadges(primary.map(\.provenance))
        guard let sleepStart = sleepSegments.first?.start,
              let sleepEnd = sleepSegments.last?.end else {
            return StressSleepSignals(durationHours: nil, interruptions: nil, bedtimeMinutesFromMidnight: nil, overnightWearMinutes: nil, sourceBadges: sourceBadges)
        }

        let sleepMinutes = sleepSegments.reduce(0) { $0 + $1.durationMinutes }
        let interruptions = primary.filter {
            $0.stage == .awake &&
                $0.start > sleepStart &&
                $0.end < sleepEnd &&
                $0.durationMinutes >= 2
        }.count
        let wearMinutes = primary.reduce(0) { $0 + $1.durationMinutes }

        return StressSleepSignals(
            durationHours: sleepMinutes > 0 ? sleepMinutes / 60 : nil,
            interruptions: Double(interruptions),
            bedtimeMinutesFromMidnight: minutesFromMidnight(sleepStart, calendar: calendar),
            overnightWearMinutes: wearMinutes > 0 ? wearMinutes : nil,
            sourceBadges: sourceBadges
        )
    }

    private func motionContext(strain: StrainSummary, referenceDate: Date) -> (context: StressMotionContext, minutesSinceWorkout: Double?, lastWorkoutEnd: Date?) {
        if strain.workoutBands.contains(where: { $0.startDate <= referenceDate && $0.endDate >= referenceDate }) {
            return (.workout, 0, nil)
        }

        let latestWorkout = strain.workoutBands
            .filter { $0.endDate <= referenceDate }
            .sorted { $0.endDate > $1.endDate }
            .first
        if let latestWorkout {
            let minutesSince = referenceDate.timeIntervalSince(latestWorkout.endDate) / 60
            if minutesSince <= 12 {
                return (.postWorkout, minutesSince, latestWorkout.endDate)
            }
        }

        guard let latestInterval = strain.timeline
            .filter({ $0.startDate <= referenceDate && $0.endDate >= referenceDate })
            .last else {
            return (.unknown, latestWorkout.map { referenceDate.timeIntervalSince($0.endDate) / 60 }, latestWorkout?.endDate)
        }

        switch latestInterval.intensity {
        case .rest:
            return (.resting, latestWorkout.map { referenceDate.timeIntervalSince($0.endDate) / 60 }, latestWorkout?.endDate)
        case .light:
            return (.light, latestWorkout.map { referenceDate.timeIntervalSince($0.endDate) / 60 }, latestWorkout?.endDate)
        case .moderate, .hard, .peak:
            return (.active, latestWorkout.map { referenceDate.timeIntervalSince($0.endDate) / 60 }, latestWorkout?.endDate)
        }
    }

    private func recentHeartRateContext(from samples: [HeartRateSample], referenceDate: Date) -> (value: Double?, timestamp: Date?) {
        func windowedSamples(minutes: Double) -> [HeartRateSample] {
            samples.filter {
                $0.bpm > 0 &&
                    $0.end <= referenceDate &&
                    referenceDate.timeIntervalSince($0.end) <= minutes * 60
            }
        }

        func robustAverage(_ samples: [HeartRateSample]) -> Double? {
            let values = samples.map(\.bpm).filter { $0.isFinite && $0 > 30 && $0 < 220 }.sorted()
            guard !values.isEmpty else { return nil }
            if values.count >= 5 {
                let trimmed = values.dropFirst().dropLast()
                return trimmed.reduce(0, +) / Double(trimmed.count)
            }
            if values.count >= 3 {
                return values[values.count / 2]
            }
            return values.reduce(0, +) / Double(values.count)
        }

        let fiveMinute = windowedSamples(minutes: 5)
        if fiveMinute.count >= 2, let average = robustAverage(fiveMinute) {
            return (average, fiveMinute.map(\.end).max())
        }

        let recent = windowedSamples(minutes: 15)
        if !recent.isEmpty, let average = robustAverage(recent) {
            return (average, recent.map(\.end).max())
        }

        let latest = samples.filter {
            $0.bpm > 0 &&
                $0.end <= referenceDate
        }.sorted(by: { $0.end > $1.end }).first
        guard let latest else { return (nil, nil) }
        return (latest.bpm, latest.end)
    }

    private func signalQuality(heartSamples: [HeartRateSample], sleep: SleepSummary, biometrics: DailyBiometrics) -> Double? {
        let hasOvernightVitals = biometrics.hrvSDNNMilliseconds != nil || biometrics.restingHeartRateBPM != nil || biometrics.respiratoryRate != nil
        if hasOvernightVitals { return nil }
        if sleep.totalSleepMinutes < 180 && heartSamples.count < 3 { return 0.35 }
        return nil
    }

    private func effectiveReferenceDate(
        heartSamples: [HeartRateSample],
        sleep: SleepSummary,
        strain: StrainSummary,
        interval: DateInterval,
        refreshedAt: Date
    ) -> Date {
        func stableCandidate(_ date: Date?) -> Date? {
            guard let date,
                  date <= refreshedAt,
                  date >= interval.start,
                  date <= interval.end else { return nil }
            return date
        }

        let latestHeartSample = heartSamples
            .compactMap { stableCandidate($0.end) }
            .max()
        let latestStrainSample = strain.heartRatePoints
            .compactMap { stableCandidate($0.date) }
            .max()
        let latestWorkout = strain.workoutBands
            .compactMap { stableCandidate($0.endDate) }
            .max()
        let latestSleep = stableCandidate(sleep.wakeTime)
        let stableSignalDate = [
            latestHeartSample,
            latestStrainSample,
            latestWorkout,
            latestSleep
        ].compactMap { $0 }.max()
        return stableSignalDate ?? interval.start
    }

    private func minutesFromMidnight(_ date: Date, calendar: Calendar) -> Double {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
    }

    private func logStressPipeline(
        summary: StressSummary,
        dateKey: String,
        today: StressDailySignals,
        baselineDays: [StressDailySignals],
        referenceDate: Date
    ) {
        let source = summary.sourceBadges.map(\.displayName).sorted().joined(separator: "+")
        let baseline = StressBaselineBuilder().build(from: baselineDays)
        let dailyAverage = dailyAverageStress(from: summary)
        let zoneDurations = PulsarStressTimelineDistribution.buckets(
            samples: summary.dailySamples.map { PulsarStressTimelineSample(timestamp: $0.timestamp, score: $0.score) }
        )
            .map { "\($0.category.rawValue)=\(Int(($0.duration / 60).rounded()))m" }
            .joined(separator: ",")
        let missingSignals = [
            today.currentHeartRate == nil && today.recentHeartRate == nil ? "heartRate" : nil,
            today.heartRateVariabilitySDNN == nil ? "hrv" : nil,
            today.restingHeartRate == nil ? "restingHeartRate" : nil
        ].compactMap { $0 }.joined(separator: ",")
        PulsarSyncDebugLogger.log("stress pipeline dateKey=\(dateKey) selectedDay=\(today.date) reference=\(referenceDate) sourceUsed=\(source.isEmpty ? "HealthKit" : source) currentHR=\(today.currentHeartRate ?? today.recentHeartRate ?? -1) HRBaseline=\(baseline.restingHeartRate?.mean ?? -1) currentHRV=\(today.heartRateVariabilitySDNN ?? -1) HRVBaseline=\(baseline.hrvSDNN?.mean ?? -1) movementLevel=\(today.currentMotionContext.rawValue) workoutState=\(today.currentMotionContext == .workout ? "active" : "inactive") cooldownState=\(today.currentMotionContext == .postWorkout ? "active" : "inactive") steps=\(today.recentSteps ?? 0) activeEnergy=\(today.recentActiveEnergyKilocalories ?? 0) confidence=\(summary.confidence.rawValue) rawStress=\(summary.nonActivityStress.map(String.init) ?? "nil") movementAdjustedStress=\(summary.activityAdjustedStress.map(String.init) ?? "nil") finalCurrentStress=\(summary.score.map(String.init) ?? "nil") dailyAverageStress=\(dailyAverage.map { String(format: "%.1f", $0) } ?? "nil") zoneDurations=\(zoneDurations.isEmpty ? "none" : zoneDurations) missingSignals=\(missingSignals.isEmpty ? "none" : missingSignals)")
    }

    private func dailyAverageStress(from summary: StressSummary) -> Double? {
        PulsarStressTimelineDistribution.weightedAverage(
            samples: summary.dailySamples.map { PulsarStressTimelineSample(timestamp: $0.timestamp, score: $0.score) }
        ) ?? summary.currentScore
    }
}

struct StressSummaryCache {
    private struct Entry: Codable {
        var dateKey: String
        var inputHash: String
        var summary: StressSummary
        var calculatedAt: Date
        var dataWindowStart: Date?
        var dataWindowEnd: Date?
    }

    private let defaults: UserDefaults
    private let keyPrefix = "pulsar.stress.summary.cache.v1."
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func summary(for dateKey: String, inputHash: String) -> StressSummary? {
        guard let entry = entry(for: dateKey),
              entry.inputHash == inputHash else { return nil }
        return entry.summary
    }

    func latestSummary(for dateKey: String) -> StressSummary? {
        entry(for: dateKey)?.summary
    }

    func save(_ summary: StressSummary, for dateKey: String, inputHash: String, calculatedAt: Date) {
        let entry = Entry(
            dateKey: dateKey,
            inputHash: inputHash,
            summary: summary,
            calculatedAt: calculatedAt,
            dataWindowStart: summary.queryStart,
            dataWindowEnd: summary.queryEnd
        )
        guard let data = try? encoder.encode(entry) else { return }
        defaults.set(data, forKey: storageKey(for: dateKey))
    }

    func clear(for dateKey: String) {
        defaults.removeObject(forKey: storageKey(for: dateKey))
    }

    private func entry(for dateKey: String) -> Entry? {
        guard let data = defaults.data(forKey: storageKey(for: dateKey)) else { return nil }
        return try? decoder.decode(Entry.self, from: data)
    }

    private func storageKey(for dateKey: String) -> String {
        keyPrefix + dateKey
    }
}

enum StressInputFingerprint {
    nonisolated static func make(
        dateKey: String,
        queryStart: Date,
        referenceDate: Date,
        today: StressDailySignals,
        baselineDays: [StressDailySignals],
        heartSamples: [HeartRateSample],
        sleep: SleepSummary,
        strain: StrainSummary
    ) -> String {
        var parts: [String] = [
            "date:\(dateKey)",
            "queryStart:\(date(queryStart))",
            "reference:\(date(referenceDate))",
            "today:\(signals(today))",
            "sleep:\(sleep.score):\(number(sleep.totalSleepMinutes)):\(number(sleep.sleepPerformance)):\(sleep.analyzedSampleCount)",
            "strain:\(strain.score):\(number(strain.rawLoad)):\(strain.steps):\(number(strain.workoutMinutes)):\(strain.analyzedSampleCount)",
            "heart:\(heartSampleFingerprint(heartSamples))"
        ]

        let baselineFingerprint = baselineDays
            .sorted { $0.date < $1.date }
            .map(signals)
            .joined(separator: "|")
        parts.append("baseline:\(baselineFingerprint)")

        return fnv1a64(parts.joined(separator: "||"))
    }

    nonisolated private static func signals(_ value: StressDailySignals) -> String {
        [
            "d:\(date(value.date))",
            "computed:\(date(value.computedAt))",
            "hrv:\(number(value.heartRateVariabilitySDNN))",
            "hrvAt:\(date(value.heartRateVariabilityTimestamp))",
            "rhr:\(number(value.restingHeartRate))",
            "walk:\(number(value.walkingHeartRateAverage))",
            "rr:\(number(value.sleepRespiratoryRate))",
            "temp:\(number(value.wristTemperatureDelta))",
            "sleep:\(number(value.sleepDurationHours))",
            "wake:\(number(value.sleepInterruptions))",
            "cons:\(number(value.bedtimeConsistency))",
            "bed:\(number(value.bedtimeMinutesFromMidnight))",
            "load:\(number(value.recentWorkoutLoad))",
            "strain:\(number(value.strainScore))",
            "ctx:\(value.currentMotionContext.rawValue)",
            "hr:\(number(value.currentHeartRate))",
            "hrAt:\(date(value.currentHeartRateTimestamp))",
            "recent:\(number(value.recentHeartRate))",
            "post:\(number(value.minutesSinceWorkout))",
            "lastWorkout:\(date(value.lastWorkoutEnd))",
            "recentSteps:\(number(value.recentSteps))",
            "recentEnergy:\(number(value.recentActiveEnergyKilocalories))",
            "recentExercise:\(number(value.recentExerciseMinutes))",
            "wear:\(number(value.overnightWearMinutes))",
            "artifact:\(number(value.motionArtifactLevel))",
            "quality:\(number(value.signalQuality))"
        ].joined(separator: ",")
    }

    nonisolated private static func heartSampleFingerprint(_ samples: [HeartRateSample]) -> String {
        let valid = samples
            .filter { $0.bpm.isFinite && $0.bpm > 0 }
            .sorted { $0.end < $1.end }
        guard !valid.isEmpty else { return "empty" }
        let stride = max(1, valid.count / 36)
        let sampled = valid.enumerated().compactMap { index, sample in
            index.isMultiple(of: stride) || index == valid.count - 1 ? sample : nil
        }
        let mean = valid.map(\.bpm).reduce(0, +) / Double(valid.count)
        return [
            "count:\(valid.count)",
            "first:\(date(valid.first?.end))",
            "last:\(date(valid.last?.end))",
            "mean:\(number(mean))",
            sampled.map { "\(date($0.end))/\(number($0.bpm))" }.joined(separator: ";")
        ].joined(separator: ",")
    }

    nonisolated private static func date(_ value: Date?) -> String {
        guard let value else { return "nil" }
        return String(format: "%.0f", value.timeIntervalSinceReferenceDate)
    }

    nonisolated private static func number(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "nil" }
        return String(format: "%.3f", value)
    }

    nonisolated private static func fnv1a64(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}
