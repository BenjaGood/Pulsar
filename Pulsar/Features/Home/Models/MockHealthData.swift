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
                sleepPerformance: 0.78,
                priorDayStrain: 0.45,
                provenance: ["hrv": .sample, "rhr": .sample, "respiratory": .sample]
            )
        }
    }

    static var todayBiometrics: DailyBiometrics {
        DailyBiometrics(
            date: calendar.date(from: DateComponents(year: 2026, month: 5, day: 3))!,
            hrvSDNNMilliseconds: 63,
            restingHeartRateBPM: 51,
            respiratoryRate: 14.4,
            sleepPerformance: sleepSummary.sleepPerformance,
            priorDayStrain: 0.62,
            provenance: ["hrv": .sample, "rhr": .sample, "respiratory": .sample]
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
}
