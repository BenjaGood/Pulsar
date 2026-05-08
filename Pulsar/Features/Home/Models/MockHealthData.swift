//
//  MockHealthData.swift
//  Pulsar
//

import Foundation

enum MockHealthData {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    static let profile: UserProfile = {
        var profile = UserProfile.empty
        profile.name = "Alex"
        profile.heightCentimeters = 178
        profile.weightKilograms = 72
        profile.dateOfBirth = calendar.date(from: DateComponents(year: 1994, month: 5, day: 3))
        profile.biologicalSex = .notSet
        profile.manualMaxHeartRate = 188
        profile.sleepSchedule = SleepSchedule(targetBedtimeHour: 22, targetBedtimeMinute: 45, targetWakeHour: 6, targetWakeMinute: 45, targetSleepHours: 8)
        return profile
    }()

    static var sleepNight: NightlySleepInput {
        let start = calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 22, minute: 42))!
        let segments: [(SleepStage, Int)] = [
            (.awake, 14),
            (.core, 82),
            (.deep, 58),
            (.core, 96),
            (.rem, 34),
            (.awake, 12),
            (.core, 74),
            (.rem, 48),
            (.core, 44),
            (.awake, 10)
        ]
        var cursor = start
        let sleepSegments = segments.map { stage, minutes in
            let next = calendar.date(byAdding: .minute, value: minutes, to: cursor)!
            defer { cursor = next }
            return SleepSegment(stage: stage, start: cursor, end: next, provenance: .sample)
        }
        return NightlySleepInput(nightStart: start, nightEnd: cursor, segments: sleepSegments)
    }

    static var recentSleepNights: [NightlySleepInput] {
        let base = calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 22, minute: 35))!
        return (1...8).map { offset in
            let baseStart = calendar.date(byAdding: .day, value: -offset, to: base)!
            let start = calendar.date(byAdding: .minute, value: offset % 4 * 4, to: baseStart)!
            let end = calendar.date(byAdding: .minute, value: 458 - offset % 3 * 8, to: start)!
            return NightlySleepInput(
                nightStart: start,
                nightEnd: end,
                segments: [SleepSegment(stage: .asleepUnspecified, start: start, end: end, provenance: .sample)]
            )
        }
    }

    static var sleepSummary: SleepSummary {
        SleepScoringEngine(calendar: calendar).score(night: sleepNight, recentNights: recentSleepNights, schedule: profile.sleepSchedule)
    }

    static var baselineBiometrics: [DailyBiometrics] {
        let base = calendar.date(from: DateComponents(year: 2026, month: 5, day: 3))!
        return (1...28).map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: base)!
            return DailyBiometrics(
                date: date,
                hrvSDNNMilliseconds: 58 + Double(offset % 5 - 2) * 2,
                restingHeartRateBPM: 52 + Double(offset % 4),
                respiratoryRate: 14.2 + Double(offset % 3) * 0.2,
                oxygenSaturation: 0.976 + Double(offset % 3) * 0.003,
                wristTemperatureDeviationCelsius: Double(offset % 5 - 2) * 0.04,
                sleepPerformance: 0.78,
                priorDayStrain: 0.45,
                provenance: [
                    "hrv": .sample,
                    "rhr": .sample,
                    "respiratory": .sample,
                    "oxygen": .sample,
                    "wristTemperature": .sample
                ]
            )
        }
    }

    static var todayBiometrics: DailyBiometrics {
        DailyBiometrics(
            date: calendar.date(from: DateComponents(year: 2026, month: 5, day: 3))!,
            hrvSDNNMilliseconds: 63,
            restingHeartRateBPM: 51,
            respiratoryRate: 14.4,
            oxygenSaturation: 0.984,
            wristTemperatureDeviationCelsius: 0.1,
            sleepPerformance: sleepSummary.sleepPerformance,
            priorDayStrain: 0.62,
            provenance: [
                "hrv": .sample,
                "rhr": .sample,
                "respiratory": .sample,
                "oxygen": .sample,
                "wristTemperature": .sample
            ]
        )
    }

    static var recoverySummary: RecoverySummary {
        let date = calendar.date(from: DateComponents(year: 2026, month: 5, day: 3))!
        let interval = calendar.dateInterval(of: .day, for: date) ?? DateInterval(start: date, duration: 86_400)
        return RecoveryAnalyzer().analyze(
            RecoveryAnalysisInput(
                date: date,
                biometrics: todayBiometrics,
                baselineDays: baselineBiometrics,
                trendDays: Array(baselineBiometrics.prefix(6).reversed()) + [todayBiometrics],
                sleep: sleepSummary,
                strain: strainSummary,
                queryInterval: interval,
                refreshedAt: interval.end.addingTimeInterval(-1)
            )
        )
    }

    static var strainInput: DailyStrainInput {
        let start = calendar.date(from: DateComponents(year: 2026, month: 5, day: 3, hour: 7, minute: 10))!
        let heartRateSamples = stride(from: 0, to: 48, by: 2).map { minute -> HeartRateSample in
            let sampleStart = calendar.date(byAdding: .minute, value: minute, to: start)!
            let sampleEnd = calendar.date(byAdding: .minute, value: minute + 2, to: start)!
            let bpm = [118, 126, 137, 151, 162, 171, 155, 144][(minute / 2) % 8]
            return HeartRateSample(start: sampleStart, end: sampleEnd, bpm: Double(bpm), provenance: .sample)
        }
        let workout = WorkoutLoadInput(
            type: "Tempo Run",
            start: start,
            end: calendar.date(byAdding: .minute, value: 48, to: start)!,
            heartRateSamples: heartRateSamples,
            activeEnergyKilocalories: 520,
            distanceMeters: 9200,
            provenance: .sample
        )
        let activity = DailyActivityInput(
            date: start,
            steps: 12_850,
            activeEnergyKilocalories: 790,
            basalEnergyKilocalories: 1620,
            distanceMeters: 11_300,
            exerciseMinutes: 63,
            provenance: [.sample]
        )
        return DailyStrainInput(
            date: start,
            maxHeartRate: profile.manualMaxHeartRate,
            workouts: [workout],
            activity: activity,
            recentRawLoads: [90, 105, 88, 126, 76, 144, 118, 95, 102, 132, 85, 111, 124, 98],
            sevenDayRawLoad: 720,
            twentyEightDayRawLoad: 2_540
        )
    }

    static var strainSummary: StrainSummary {
        let interval = calendar.dateInterval(of: .day, for: strainInput.date) ?? DateInterval(start: strainInput.date, duration: 86_400)
        return StrainAnalyzer().analyze(
            StrainAnalysisInput(
                strainInput: strainInput,
                biometrics: todayBiometrics,
                dayHeartRateSamples: strainInput.workouts.flatMap(\.heartRateSamples),
                queryInterval: interval,
                refreshedAt: interval.end.addingTimeInterval(-1)
            )
        )
    }

    static var stressBaselineSignals: [StressDailySignals] {
        let base = calendar.date(from: DateComponents(year: 2026, month: 5, day: 3))!
        return (1...21).map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: base)!
            return StressDailySignals(
                date: date,
                heartRateVariabilitySDNN: 58 + Double(offset % 5 - 2) * 2,
                restingHeartRate: 52 + Double(offset % 4),
                walkingHeartRateAverage: 92 + Double(offset % 5),
                sleepRespiratoryRate: 14.2 + Double(offset % 3) * 0.2,
                wristTemperatureDelta: Double(offset % 5 - 2) * 0.03,
                sleepDurationHours: 7.55 + Double(offset % 4) * 0.08,
                sleepInterruptions: Double(2 + offset % 3),
                bedtimeConsistency: 0.86,
                bedtimeMinutesFromMidnight: 22 * 60 + 40 + Double(offset % 5),
                recentWorkoutLoad: 95 + Double(offset % 6) * 4,
                strainScore: nil,
                currentMotionContext: .unknown,
                currentHeartRate: nil,
                recentHeartRate: nil,
                minutesSinceWorkout: nil,
                overnightWearMinutes: 455,
                motionArtifactLevel: nil,
                signalQuality: nil,
                sourceBadges: [.sample]
            )
        }
    }

    static var stressTodaySignals: StressDailySignals {
        StressDailySignals(
            date: calendar.date(from: DateComponents(year: 2026, month: 5, day: 3))!,
            heartRateVariabilitySDNN: todayBiometrics.hrvSDNNMilliseconds,
            restingHeartRate: todayBiometrics.restingHeartRateBPM,
            walkingHeartRateAverage: 94,
            sleepRespiratoryRate: todayBiometrics.respiratoryRate,
            wristTemperatureDelta: 0.02,
            sleepDurationHours: sleepSummary.totalSleepMinutes / 60,
            sleepInterruptions: Double(sleepSummary.awakenings),
            bedtimeConsistency: sleepSummary.sleepConsistency,
            bedtimeMinutesFromMidnight: sleepSummary.sleepStart.map { date in
                let components = calendar.dateComponents([.hour, .minute], from: date)
                return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
            },
            recentWorkoutLoad: strainSummary.rawLoad,
            strainScore: Double(strainSummary.score),
            currentMotionContext: .resting,
            currentHeartRate: 76,
            recentHeartRate: 76,
            minutesSinceWorkout: 240,
            overnightWearMinutes: sleepSummary.timeInBedMinutes,
            motionArtifactLevel: nil,
            signalQuality: nil,
            sourceBadges: [.sample]
        )
    }

    static var stressSummary: StressSummary {
        StressEngine().score(today: stressTodaySignals, baselineDays: stressBaselineSignals)
    }

    static var stressDetailSummary: StressSummary {
        var summary = stressSummary
        let date = calendar.date(from: DateComponents(year: 2026, month: 5, day: 3))!
        summary.date = date
        summary.queryStart = calendar.startOfDay(for: date)
        summary.queryEnd = calendar.date(bySettingHour: 20, minute: 30, second: 0, of: date)
        summary.lastUpdated = summary.queryEnd
        summary.dailySamples = stressTimelineSamples
        return summary
    }

    static var stressTimelineSamples: [StressSample] {
        let day = calendar.date(from: DateComponents(year: 2026, month: 5, day: 3))!
        let points: [(Int, Int, Double, StressContext)] = [
            (0, 30, 28, .sleep),
            (2, 0, 24, .sleep),
            (4, 30, 22, .sleep),
            (6, 45, 34, .recovery),
            (8, 15, 42, .active),
            (10, 30, 58, .active),
            (12, 20, 66, .active),
            (13, 45, 72, .workout),
            (15, 0, 63, .recovery),
            (16, 45, 54, .rest),
            (18, 15, 61, .active),
            (20, 30, 48, .rest)
        ]

        return points.compactMap { hour, minute, score, context in
            guard let timestamp = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { return nil }
            return StressSample(timestamp: timestamp, score: score, confidence: .high, context: context)
        }
    }

    static func stressPreviewSummary(score: Int, confidence: ConfidenceGrade = .high) -> StressSummary {
        var summary = stressDetailSummary
        summary.score = score
        summary.level = StressLevel.level(for: score)
        summary.confidence = confidence
        summary.state = confidence == .low ? .lowConfidence : .ready
        summary.driverInsights = Double(score) >= PulsarStressScale.highLowerBound
            ? ["Heart rate is elevated for context", "Recent training is contributing"]
            : ["Your physiology looks close to baseline", "Stress load is steady today"]
        summary.drivers = summary.driverInsights.enumerated().map { index, insight in
            StressDriver(
                id: "preview-driver-\(score)-\(index)",
                title: insight,
                detail: "Preview data compared with a recent personal baseline.",
                severity: Double(score) >= PulsarStressScale.highLowerBound ? .elevated : .supportive,
                relatedMetric: nil
            )
        }
        summary.dailySamples = stressTimelineSamples.map { sample in
            var adjusted = sample
            adjusted.score = ScoreMath.clamp(sample.score + Double(score - 56) * 0.45, 0, 100)
            adjusted.confidence = confidence
            return adjusted
        }
        return summary
    }

    static var healthMonitorSummary: HealthMonitorSummary {
        let now = calendar.date(from: DateComponents(year: 2026, month: 5, day: 3, hour: 20, minute: 30)) ?? .now
        return HealthMonitorSummary(
            date: calendar.date(from: DateComponents(year: 2026, month: 5, day: 3)),
            metrics: [
                HealthMetricModel(
                    kind: .respiratoryRate,
                    value: 14.4,
                    status: .normal,
                    baselineValue: 14.2,
                    comparisonText: "Close to your recent baseline.",
                    sourceBadges: [.sample],
                    lastUpdated: now
                ),
                HealthMetricModel(
                    kind: .restingHeartRate,
                    value: 51,
                    status: .lower,
                    baselineValue: 54,
                    comparisonText: "Lower than your recent baseline.",
                    sourceBadges: [.sample],
                    lastUpdated: now
                ),
                HealthMetricModel(
                    kind: .hrv,
                    value: 63,
                    status: .higher,
                    baselineValue: 57,
                    comparisonText: "Higher than your recent baseline.",
                    sourceBadges: [.sample],
                    lastUpdated: now
                ),
                HealthMetricModel(
                    kind: .oxygenSaturation,
                    value: 0.984,
                    status: .normal,
                    baselineValue: 0.978,
                    comparisonText: "Close to your recent baseline.",
                    sourceBadges: [.sample],
                    lastUpdated: now
                ),
                HealthMetricModel(
                    kind: .wristTemperature,
                    value: 0.1,
                    status: .normal,
                    baselineValue: 0.04,
                    comparisonText: "Close to your recent baseline.",
                    sourceBadges: [.sample],
                    lastUpdated: now
                ),
                HealthMetricModel(
                    kind: .sleep,
                    value: sleepSummary.totalSleepMinutes,
                    status: .normal,
                    baselineValue: 458,
                    comparisonText: "Close to your recent baseline.",
                    sourceBadges: [.sample],
                    lastUpdated: now
                )
            ],
            lastUpdated: now,
            baselineWindowDays: 14,
            sourceBadges: [.sample]
        )
    }

    static var homePolishPreviewDashboard: HomeDashboard {
        var sleep = sleepSummary
        sleep.score = 77

        var recovery = recoverySummary
        recovery.score = 45

        var strain = strainSummary
        strain.score = 98

        var stress = stressPreviewSummary(score: 86, confidence: .high)
        stress.lastUpdated = calendar.date(from: DateComponents(year: 2026, month: 5, day: 3, hour: 20, minute: 30))

        let generatedAt = calendar.date(from: DateComponents(year: 2026, month: 5, day: 3, hour: 20, minute: 30)) ?? .now
        return HomeDashboard(
            profile: profile,
            sleep: sleep,
            recovery: recovery,
            strain: strain,
            stress: stress,
            healthMonitor: healthMonitorSummary,
            generatedAt: generatedAt,
            usingSampleData: true
        )
    }
}
