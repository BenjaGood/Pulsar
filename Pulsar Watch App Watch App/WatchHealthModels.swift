//
//  WatchHealthModels.swift
//  Pulsar Watch App Watch App
//

import Foundation
import SwiftUI

struct WatchDailyHealthSnapshot: Equatable {
    var date: Date
    var healthKitState: WatchHealthKitState
    var source: WatchSnapshotSource
    var sleep: WatchSleepSummary
    var alarm: WatchSleepAlarmSummary
    var recovery: WatchRecoverySummary
    var strain: WatchStrainSummary
    var stress: WatchStressSummary
    var activity: WatchActivitySummary
    var heart: WatchHeartMetricsSummary
    var workouts: [WatchWorkoutSummary]
    var detectedSources: [String]

    static let empty = WatchDailyHealthSnapshot(
        date: Date(),
        healthKitState: .notRequested,
        source: .none,
        sleep: .empty,
        alarm: .empty,
        recovery: .empty,
        strain: .empty,
        stress: .empty,
        activity: .empty,
        heart: .empty,
        workouts: [],
        detectedSources: []
    )
}

enum WatchSnapshotSource: String, Equatable {
    case none
    case iPhoneSync
    case watchHealthKit
    case healthKitAuto

    var label: String {
        switch self {
        case .none: "No data"
        case .iPhoneSync: "iPhone sync"
        case .watchHealthKit: "Watch HealthKit"
        case .healthKitAuto: "HealthKit Auto"
        }
    }
}

enum WatchHealthKitState: Equatable {
    case notRequested
    case connected
    case needsPermission
    case unavailable

    var label: String {
        switch self {
        case .notRequested: "Set Up"
        case .connected: "Connected"
        case .needsPermission: "Needs Permission"
        case .unavailable: "Unavailable"
        }
    }

    var tint: Color {
        switch self {
        case .connected: .green
        case .needsPermission: .orange
        case .notRequested: .blue
        case .unavailable: .secondary
        }
    }
}

enum WatchSyncBannerState: Equatable {
    case syncing(String)
    case success(String)
    case failure(String)

    var message: String {
        switch self {
        case .syncing(let message), .success(let message), .failure(let message):
            message
        }
    }

    var tint: Color {
        switch self {
        case .syncing: .cyan
        case .success: .green
        case .failure: .orange
        }
    }

    var symbol: String {
        switch self {
        case .syncing: "heart.text.square.fill"
        case .success: "checkmark"
        case .failure: "exclamationmark"
        }
    }

    var isSyncing: Bool {
        if case .syncing = self { return true }
        return false
    }
}

struct WatchSleepSummary: Equatable {
    var score: Int?
    var totalSleepMinutes: Double
    var timeInBedMinutes: Double
    var efficiency: Double?
    var consistency: Double?
    var awakeMinutes: Double
    var remMinutes: Double
    var coreMinutes: Double
    var deepMinutes: Double
    var asleepUnspecifiedMinutes: Double
    var sourceName: String?

    static let empty = WatchSleepSummary(score: nil, totalSleepMinutes: 0, timeInBedMinutes: 0, efficiency: nil, consistency: nil, awakeMinutes: 0, remMinutes: 0, coreMinutes: 0, deepMinutes: 0, asleepUnspecifiedMinutes: 0, sourceName: nil)
}

struct WatchSleepAlarmSummary: Equatable {
    var isEnabled: Bool
    var timeMinutesFromMidnight: Int?
    var hapticsEnabled: Bool
    var snoozeEnabled: Bool
    var smartWakeEnabled: Bool
    var usesWakeTime: Bool
    var soundName: String?
    var sleepGoalDaysLabel: String?
    var syncedAt: Date?

    static let empty = WatchSleepAlarmSummary(
        isEnabled: false,
        timeMinutesFromMidnight: nil,
        hapticsEnabled: false,
        snoozeEnabled: false,
        smartWakeEnabled: false,
        usesWakeTime: true,
        soundName: nil,
        sleepGoalDaysLabel: nil,
        syncedAt: nil
    )
}

struct WatchRecoverySummary: Equatable {
    var score: Int?
    var label: String
    var hrv: Double?
    var restingHeartRate: Double?
    var respiratoryRate: Double?
    var sleepPerformance: Double?

    static let empty = WatchRecoverySummary(score: nil, label: "No data", hrv: nil, restingHeartRate: nil, respiratoryRate: nil, sleepPerformance: nil)
}

struct WatchStrainSummary: Equatable {
    var score: Int?
    var activeStrain: Double
    var passiveStrain: Double
    var workoutMinutes: Double
    var activeEnergy: Double
    var steps: Double
    var zoneMinutes: [WatchHeartZoneMinutes]
    var lastWorkout: WatchWorkoutSummary?

    static let empty = WatchStrainSummary(score: nil, activeStrain: 0, passiveStrain: 0, workoutMinutes: 0, activeEnergy: 0, steps: 0, zoneMinutes: [], lastWorkout: nil)
}

struct WatchStressSummary: Equatable {
    var score: Int?
    var level: String
    var confidence: PulsarSyncConfidence
    var driverInsights: [String]
    var hrv: Double?
    var hrvTimestamp: Date?
    var recentHeartRate: Double?
    var heartRateTimestamp: Date?
    var restingHeartRate: Double?
    var respiratoryRate: Double?
    var nonActivityStress: Double?
    var activityAdjustedStress: Double?
    var movementState: String?
    var calculationState: PulsarSharedStressCalculationState
    var isPaused: Bool
    var sleepDurationMinutes: Double?
    var strainScore: Double?
    var availableSignalCount: Int
    var baselineWindowDays: Int
    var timelineSamples: [WatchStressSample]
    var sourceName: String?

    static let empty = WatchStressSummary(
        score: nil,
        level: "Not enough data",
        confidence: .missing,
        driverInsights: ["Stress confidence improves with more signals"],
        hrv: nil,
        hrvTimestamp: nil,
        recentHeartRate: nil,
        heartRateTimestamp: nil,
        restingHeartRate: nil,
        respiratoryRate: nil,
        nonActivityStress: nil,
        activityAdjustedStress: nil,
        movementState: nil,
        calculationState: .lowConfidence,
        isPaused: false,
        sleepDurationMinutes: nil,
        strainScore: nil,
        availableSignalCount: 0,
        baselineWindowDays: 0,
        timelineSamples: [],
        sourceName: nil
    )
}

struct WatchStressSample: Identifiable, Equatable {
    var id: Date { timestamp }
    var timestamp: Date
    var score: Double
    var context: String?
}

struct WatchActivitySummary: Equatable {
    var steps: Double
    var activeEnergy: Double
    var workoutMinutes: Double

    static let empty = WatchActivitySummary(steps: 0, activeEnergy: 0, workoutMinutes: 0)
}

struct WatchHeartMetricsSummary: Equatable {
    var latestHeartRate: Double?
    var latestHeartRateTimestamp: Date? = nil
    var restingHeartRate: Double?
    var hrvSDNN: Double?
    var hrvTimestamp: Date? = nil
    var respiratoryRate: Double?

    static let empty = WatchHeartMetricsSummary(latestHeartRate: nil, restingHeartRate: nil, hrvSDNN: nil, respiratoryRate: nil)
}

struct WatchWorkoutSummary: Identifiable, Equatable {
    var id: UUID
    var type: String
    var start: Date
    var durationMinutes: Double
    var activeEnergy: Double?
    var averageHeartRate: Double?
    var sourceName: String?
}

struct WatchHeartZoneMinutes: Identifiable, Equatable {
    var id: Int { zone }
    var zone: Int
    var minutes: Double
}

enum WatchFormatters {
    static func score(_ value: Int?) -> String {
        value.map(String.init) ?? "--"
    }

    static func minutes(_ value: Double) -> String {
        guard value > 0 else { return "--" }
        let rounded = Int(value.rounded())
        if rounded >= 60 { return "\(rounded / 60)h \(rounded % 60)m" }
        return "\(rounded)m"
    }

    static func percent(_ value: Double?) -> String {
        guard let value, value > 0 else { return "--" }
        return "\(Int((value * 100).rounded()))%"
    }

    static func bpm(_ value: Double?) -> String {
        guard let value, value > 0 else { return "--" }
        return "\(Int(value.rounded()))"
    }

    static func milliseconds(_ value: Double?) -> String {
        guard let value, value > 0 else { return "--" }
        return "\(Int(value.rounded()))"
    }

    static func calories(_ value: Double) -> String {
        guard value > 0 else { return "--" }
        return "\(Int(value.rounded()))"
    }

    static func confidence(_ value: PulsarSyncConfidence) -> String {
        switch value {
        case .high: "High confidence"
        case .moderate: "Moderate confidence"
        case .low: "Low confidence"
        case .missing: "No data"
        }
    }

    static func steps(_ value: Double) -> String {
        guard value > 0 else { return "--" }
        return Int(value.rounded()).formatted()
    }

    static func clockTime(_ minutesFromMidnight: Int?) -> String {
        guard let minutesFromMidnight else { return "--" }
        let normalized = ((minutesFromMidnight % (24 * 60)) + 24 * 60) % (24 * 60)
        let components = DateComponents(hour: normalized / 60, minute: normalized % 60)
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

#if DEBUG
enum WatchPreviewData {
    static let snapshot = WatchDailyHealthSnapshot(
        date: Date(),
        healthKitState: .connected,
        source: .iPhoneSync,
        sleep: WatchSleepSummary(score: 77, totalSleepMinutes: 467, timeInBedMinutes: 501, efficiency: 0.90, consistency: 0.74, awakeMinutes: 24, remMinutes: 86, coreMinutes: 258, deepMinutes: 74, asleepUnspecifiedMinutes: 0, sourceName: "Apple Watch"),
        alarm: WatchSleepAlarmSummary(isEnabled: true, timeMinutesFromMidnight: 390, hapticsEnabled: true, snoozeEnabled: true, smartWakeEnabled: false, usesWakeTime: true, soundName: "Default", sleepGoalDaysLabel: "Every day", syncedAt: Date()),
        recovery: WatchRecoverySummary(score: 45, label: "Build more baseline data", hrv: 44, restingHeartRate: 61, respiratoryRate: 15.8, sleepPerformance: 0.74),
        strain: WatchStrainSummary(score: 86, activeStrain: 78, passiveStrain: 24, workoutMinutes: 76, activeEnergy: 860, steps: 14840, zoneMinutes: [WatchHeartZoneMinutes(zone: 2, minutes: 20), WatchHeartZoneMinutes(zone: 3, minutes: 24), WatchHeartZoneMinutes(zone: 4, minutes: 16), WatchHeartZoneMinutes(zone: 5, minutes: 6)], lastWorkout: WatchWorkoutSummary(id: UUID(), type: "Run", start: Date().addingTimeInterval(-7200), durationMinutes: 76, activeEnergy: 620, averageHeartRate: 158, sourceName: "Apple Watch")),
        stress: WatchStressSummary(
            score: 48,
            level: "Medium",
            confidence: .high,
            driverInsights: ["HR and HRV suggest elevated physiological load right now", "Movement effects are filtered out"],
            hrv: 36,
            hrvTimestamp: Date().addingTimeInterval(-1800),
            recentHeartRate: 68,
            heartRateTimestamp: Date().addingTimeInterval(-240),
            restingHeartRate: 61,
            respiratoryRate: 15.8,
            nonActivityStress: 52,
            activityAdjustedStress: 48,
            movementState: "Inactive",
            calculationState: .measuring,
            isPaused: false,
            sleepDurationMinutes: 467,
            strainScore: 53,
            availableSignalCount: 6,
            baselineWindowDays: 21,
            timelineSamples: WatchPreviewData.stressSamples,
            sourceName: "iPhone sync"
        ),
        activity: WatchActivitySummary(steps: 14840, activeEnergy: 860, workoutMinutes: 76),
        heart: WatchHeartMetricsSummary(latestHeartRate: 68, restingHeartRate: 61, hrvSDNN: 36, respiratoryRate: 15.8),
        workouts: [WatchWorkoutSummary(id: UUID(), type: "Run", start: Date().addingTimeInterval(-7200), durationMinutes: 76, activeEnergy: 620, averageHeartRate: 158, sourceName: "Apple Watch")],
        detectedSources: ["Apple Watch", "iPhone"]
    )

    static let missingSnapshot = WatchDailyHealthSnapshot(
        date: Date(),
        healthKitState: .connected,
        source: .healthKitAuto,
        sleep: .empty,
        alarm: .empty,
        recovery: WatchRecoverySummary(score: 45, label: "Build more baseline data", hrv: nil, restingHeartRate: 62, respiratoryRate: nil, sleepPerformance: nil),
        strain: WatchStrainSummary(score: nil, activeStrain: 0, passiveStrain: 0, workoutMinutes: 0, activeEnergy: 0, steps: 0, zoneMinutes: [], lastWorkout: nil),
        stress: .empty,
        activity: .empty,
        heart: WatchHeartMetricsSummary(latestHeartRate: nil, restingHeartRate: 62, hrvSDNN: nil, respiratoryRate: nil),
        workouts: [],
        detectedSources: []
    )

    static var stressSamples: [WatchStressSample] {
        let now = Date()
        return [
            WatchStressSample(timestamp: now.addingTimeInterval(-21_600), score: 34, context: "sleep"),
            WatchStressSample(timestamp: now.addingTimeInterval(-14_400), score: 48, context: "active"),
            WatchStressSample(timestamp: now.addingTimeInterval(-9_000), score: 8, context: "workout"),
            WatchStressSample(timestamp: now.addingTimeInterval(-5_400), score: 54, context: "active"),
            WatchStressSample(timestamp: now.addingTimeInterval(-1_800), score: 48, context: "rest")
        ]
    }
}
#endif
