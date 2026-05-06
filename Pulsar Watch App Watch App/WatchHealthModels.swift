//
//  WatchHealthModels.swift
//  Pulsar Watch App Watch App
//

import Foundation
import SwiftUI

struct WatchDailyHealthSnapshot: Equatable {
    var date: Date
    var healthKitState: WatchHealthKitState
    var sleep: WatchSleepSummary
    var recovery: WatchRecoverySummary
    var strain: WatchStrainSummary
    var activity: WatchActivitySummary
    var heart: WatchHeartMetricsSummary
    var workouts: [WatchWorkoutSummary]
    var detectedSources: [String]

    static let empty = WatchDailyHealthSnapshot(
        date: Date(),
        healthKitState: .notRequested,
        sleep: .empty,
        recovery: .empty,
        strain: .empty,
        activity: .empty,
        heart: .empty,
        workouts: [],
        detectedSources: []
    )
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
    var workoutMinutes: Double
    var activeEnergy: Double
    var steps: Double
    var zoneMinutes: [WatchHeartZoneMinutes]
    var lastWorkout: WatchWorkoutSummary?

    static let empty = WatchStrainSummary(score: nil, workoutMinutes: 0, activeEnergy: 0, steps: 0, zoneMinutes: [], lastWorkout: nil)
}

struct WatchActivitySummary: Equatable {
    var steps: Double
    var activeEnergy: Double
    var workoutMinutes: Double

    static let empty = WatchActivitySummary(steps: 0, activeEnergy: 0, workoutMinutes: 0)
}

struct WatchHeartMetricsSummary: Equatable {
    var latestHeartRate: Double?
    var restingHeartRate: Double?
    var hrvSDNN: Double?
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

    static func steps(_ value: Double) -> String {
        guard value > 0 else { return "--" }
        return Int(value.rounded()).formatted()
    }
}

enum WatchPreviewData {
    static let snapshot = WatchDailyHealthSnapshot(
        date: Date(),
        healthKitState: .connected,
        sleep: WatchSleepSummary(score: 84, totalSleepMinutes: 456, timeInBedMinutes: 492, efficiency: 0.91, consistency: 0.78, awakeMinutes: 22, remMinutes: 82, coreMinutes: 246, deepMinutes: 76, asleepUnspecifiedMinutes: 0, sourceName: "Apple Watch"),
        recovery: WatchRecoverySummary(score: 78, label: "Ready", hrv: 62, restingHeartRate: 51, respiratoryRate: 14.6, sleepPerformance: 0.86),
        strain: WatchStrainSummary(score: 64, workoutMinutes: 42, activeEnergy: 680, steps: 11840, zoneMinutes: [WatchHeartZoneMinutes(zone: 2, minutes: 18), WatchHeartZoneMinutes(zone: 3, minutes: 14), WatchHeartZoneMinutes(zone: 4, minutes: 6)], lastWorkout: WatchWorkoutSummary(id: UUID(), type: "Run", start: Date().addingTimeInterval(-7200), durationMinutes: 42, activeEnergy: 420, averageHeartRate: 148, sourceName: "Apple Watch")),
        activity: WatchActivitySummary(steps: 11840, activeEnergy: 680, workoutMinutes: 42),
        heart: WatchHeartMetricsSummary(latestHeartRate: 74, restingHeartRate: 51, hrvSDNN: 62, respiratoryRate: 14.6),
        workouts: [WatchWorkoutSummary(id: UUID(), type: "Run", start: Date().addingTimeInterval(-7200), durationMinutes: 42, activeEnergy: 420, averageHeartRate: 148, sourceName: "Apple Watch")],
        detectedSources: ["Apple Watch", "iPhone"]
    )
}
