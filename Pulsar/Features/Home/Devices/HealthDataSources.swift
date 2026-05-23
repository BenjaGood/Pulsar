//
//  HealthDataSources.swift
//  Pulsar
//

import Foundation

enum HealthSourceDisplayCopy {
    static let preferredSource = "Preferred source"
    static let activeSource = "Active source"
    static let preferredSourceTitle = "Preferred Source"
    static let activeSourceTitle = "Active Source"
}

enum HealthSourceID: String, CaseIterable, Hashable, Identifiable, Codable {
    case appleWatch
    case ouraRing
    case iPhone
    case manual

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleWatch:
            return "Apple Watch"
        case .ouraRing:
            return "Oura Ring"
        case .iPhone:
            return "iPhone"
        case .manual:
            return "Manual Entry"
        }
    }
}

enum SourceConnectionState: Equatable, Hashable {
    case connected
    case available
    case setupRequired
    case syncing
    case authExpired
    case missingScopes(Set<OuraScope>)
    case rateLimited(retryAfter: Date?)
    case syncError(String)
    case disconnected

    var canProvideData: Bool {
        switch self {
        case .connected, .available, .syncing, .rateLimited, .syncError:
            return true
        case .setupRequired, .authExpired, .missingScopes, .disconnected:
            return false
        }
    }
}

enum HealthSourceSyncState: Equatable, Hashable {
    case idle
    case syncing
    case failed(message: String)
}

enum HealthSourceSelectionMode: Equatable, Hashable {
    case automatic
    case manual(HealthSourceID)
}

struct HealthSourceSnapshot: Equatable, Hashable {
    var sourceID: HealthSourceID
    var connectionState: SourceConnectionState
    var syncState: HealthSourceSyncState
    var supportedMetrics: Set<MeasurementHealthMetricType>
    var lastSyncAt: Date?
    var batteryPercentage: Int?
}

struct HealthSyncRequest: Equatable {
    var metrics: Set<MeasurementHealthMetricType>
    var interval: DateInterval
}

struct CanonicalHealthSample: Equatable, Identifiable {
    var id: String
    var metric: MeasurementHealthMetricType
    var sourceID: HealthSourceID
    var sourceRecordID: String
    var startAt: Date
    var endAt: Date?
    var value: Double?
    var unit: String?
    var syncedAt: Date
}

struct HealthSyncResult: Equatable {
    var sourceID: HealthSourceID
    var samples: [CanonicalHealthSample]
    var syncedAt: Date
    var batteryPercentage: Int?
}

enum HealthDataSourceError: LocalizedError, Equatable {
    case notConfigured(String)
    case unsupportedMetric(MeasurementHealthMetricType)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let message):
            return message
        case .unsupportedMetric(let metric):
            return "\(metric.label) is not supported by this source."
        }
    }
}

protocol HealthDataSource {
    var sourceID: HealthSourceID { get }
    var displayName: String { get }
    var supportedMetrics: Set<MeasurementHealthMetricType> { get }

    func snapshot() -> HealthSourceSnapshot
    func sync(_ request: HealthSyncRequest) async throws -> HealthSyncResult
}

struct SourcePriorityRule: Equatable, Hashable {
    var metric: MeasurementHealthMetricType
    var primarySource: HealthSourceID
    var backupSource: HealthSourceID?
    var staleAfter: TimeInterval

    static let pulsarDefaults: [SourcePriorityRule] = [
        SourcePriorityRule(metric: .heartRate, primarySource: .appleWatch, backupSource: .ouraRing, staleAfter: 3 * 60 * 60),
        SourcePriorityRule(metric: .hrv, primarySource: .appleWatch, backupSource: .ouraRing, staleAfter: 36 * 60 * 60),
        SourcePriorityRule(metric: .respiratoryRate, primarySource: .ouraRing, backupSource: .appleWatch, staleAfter: 36 * 60 * 60),
        SourcePriorityRule(metric: .sleep, primarySource: .ouraRing, backupSource: .appleWatch, staleAfter: 36 * 60 * 60),
        SourcePriorityRule(metric: .activity, primarySource: .appleWatch, backupSource: .ouraRing, staleAfter: 3 * 60 * 60),
        SourcePriorityRule(metric: .workouts, primarySource: .appleWatch, backupSource: .ouraRing, staleAfter: 12 * 60 * 60),
        SourcePriorityRule(metric: .recovery, primarySource: .ouraRing, backupSource: .appleWatch, staleAfter: 36 * 60 * 60),
        SourcePriorityRule(metric: .readiness, primarySource: .ouraRing, backupSource: .appleWatch, staleAfter: 36 * 60 * 60),
        SourcePriorityRule(metric: .restingHeartRate, primarySource: .ouraRing, backupSource: .appleWatch, staleAfter: 36 * 60 * 60),
        SourcePriorityRule(metric: .oxygenSaturation, primarySource: .ouraRing, backupSource: .appleWatch, staleAfter: 36 * 60 * 60),
        SourcePriorityRule(metric: .strain, primarySource: .appleWatch, backupSource: nil, staleAfter: 3 * 60 * 60),
        SourcePriorityRule(metric: .stress, primarySource: .appleWatch, backupSource: nil, staleAfter: 3 * 60 * 60),
        SourcePriorityRule(metric: .temperature, primarySource: .ouraRing, backupSource: .appleWatch, staleAfter: 36 * 60 * 60),
        SourcePriorityRule(metric: .cycle, primarySource: .ouraRing, backupSource: .iPhone, staleAfter: 36 * 60 * 60)
    ]
}

struct ActiveSourceSelector {
    var rules: [SourcePriorityRule] = SourcePriorityRule.pulsarDefaults
    var defaultSource: HealthSourceID = .appleWatch

    func activeSource(
        for metric: MeasurementHealthMetricType,
        mode: HealthSourceSelectionMode,
        snapshots: [HealthSourceSnapshot],
        now: Date = .now
    ) -> HealthSourceID {
        let snapshotsByID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.sourceID, $0) })

        if case .manual(let manualSource) = mode,
           let snapshot = snapshotsByID[manualSource],
           snapshot.supportedMetrics.contains(metric),
           snapshot.connectionState.canProvideData {
            return manualSource
        }

        let rule = rules.first { $0.metric == metric }
            ?? SourcePriorityRule(metric: metric, primarySource: defaultSource, backupSource: nil, staleAfter: 3 * 60 * 60)

        if let primary = snapshotsByID[rule.primarySource],
           isUsable(primary, for: metric, staleAfter: rule.staleAfter, now: now) {
            return primary.sourceID
        }

        if let backupSource = rule.backupSource,
           let backup = snapshotsByID[backupSource],
           isUsable(backup, for: metric, staleAfter: rule.staleAfter, now: now) {
            return backup.sourceID
        }

        return rule.primarySource
    }

    private func isUsable(
        _ snapshot: HealthSourceSnapshot,
        for metric: MeasurementHealthMetricType,
        staleAfter: TimeInterval,
        now: Date
    ) -> Bool {
        guard snapshot.supportedMetrics.contains(metric),
              snapshot.connectionState.canProvideData else {
            return false
        }

        guard let lastSyncAt = snapshot.lastSyncAt else {
            return snapshot.sourceID == defaultSource
        }

        return now.timeIntervalSince(lastSyncAt) <= staleAfter
    }
}

final class HealthSourceManager {
    private let sources: [HealthSourceID: any HealthDataSource]
    private let selector: ActiveSourceSelector

    init(
        sources: [any HealthDataSource],
        selector: ActiveSourceSelector = ActiveSourceSelector()
    ) {
        self.sources = Dictionary(uniqueKeysWithValues: sources.map { ($0.sourceID, $0) })
        self.selector = selector
    }

    func snapshots() -> [HealthSourceSnapshot] {
        sources.values.map { $0.snapshot() }
    }

    func snapshot(for sourceID: HealthSourceID) -> HealthSourceSnapshot? {
        sources[sourceID]?.snapshot()
    }

    func activeSource(
        for metric: MeasurementHealthMetricType,
        mode: HealthSourceSelectionMode,
        now: Date = .now
    ) -> HealthSourceID {
        selector.activeSource(for: metric, mode: mode, snapshots: snapshots(), now: now)
    }
}

struct AppleWatchHealthDataSource: HealthDataSource {
    var batteryPercentage: Int?
    var lastSyncAt: Date?

    let sourceID: HealthSourceID = .appleWatch
    let displayName = "Apple Watch"
    let supportedMetrics: Set<MeasurementHealthMetricType> = [
        .heartRate,
        .hrv,
        .respiratoryRate,
        .sleep,
        .activity,
        .workouts,
        .recovery,
        .restingHeartRate,
        .oxygenSaturation,
        .strain,
        .stress,
        .temperature,
        .cycle
    ]

    func snapshot() -> HealthSourceSnapshot {
        HealthSourceSnapshot(
            sourceID: sourceID,
            connectionState: .connected,
            syncState: .idle,
            supportedMetrics: supportedMetrics,
            lastSyncAt: lastSyncAt,
            batteryPercentage: batteryPercentage
        )
    }

    func sync(_ request: HealthSyncRequest) async throws -> HealthSyncResult {
        throw HealthDataSourceError.notConfigured("Apple Watch syncing is still handled by HealthKitGateway and WatchConnectivity.")
    }
}

enum OuraScope: String, CaseIterable, Hashable, Codable {
    case daily
    case heartrate
    case workout
    case spo2
    case personal
    case email
    case tag
    case session
    case ringConfiguration = "ring_configuration"
}
