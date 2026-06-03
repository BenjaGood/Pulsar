//
//  WorkoutHeartRateSourceModels.swift
//  Pulsar
//

import Foundation

enum WorkoutHeartRateSourceKind: String, Codable, CaseIterable, Hashable {
    case appleWatch
    case garmin
    case airPodsPro3
    case healthKit
    case unknown

    nonisolated var displayName: String {
        switch self {
        case .appleWatch:
            return "Apple Watch"
        case .garmin:
            return "Garmin"
        case .airPodsPro3:
            return "AirPods Pro 3"
        case .healthKit:
            return "Generic HealthKit"
        case .unknown:
            return "Generic HealthKit"
        }
    }

    nonisolated var canBePrimaryWorkoutSource: Bool {
        self == .appleWatch || self == .garmin
    }
}

struct WorkoutHeartRateSourceMetadata: Codable, Hashable {
    var sourceName: String?
    var sourceBundleIdentifier: String?
    var sourceVersion: String?
    var operatingSystemVersion: String?
    var productType: String?
    var deviceName: String?
    var deviceManufacturer: String?
    var deviceModel: String?
    var sourceKind: WorkoutHeartRateSourceKind

    nonisolated init(
        sourceName: String? = nil,
        sourceBundleIdentifier: String? = nil,
        sourceVersion: String? = nil,
        operatingSystemVersion: String? = nil,
        productType: String? = nil,
        deviceName: String? = nil,
        deviceManufacturer: String? = nil,
        deviceModel: String? = nil,
        sourceKind: WorkoutHeartRateSourceKind = .unknown
    ) {
        self.sourceName = sourceName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.sourceVersion = sourceVersion
        self.operatingSystemVersion = operatingSystemVersion
        self.productType = productType
        self.deviceName = deviceName
        self.deviceManufacturer = deviceManufacturer
        self.deviceModel = deviceModel
        self.sourceKind = sourceKind
    }

    nonisolated var displayName: String {
        if sourceKind != .unknown {
            return sourceKind.displayName
        }
        let candidates = [deviceName, sourceName, productType, deviceModel]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? sourceKind.displayName
    }
}

struct WorkoutHeartRateSourceSegment: Codable, Hashable, Identifiable {
    var sourceKind: WorkoutHeartRateSourceKind
    var startedAt: Date
    var endedAt: Date?
    var metadata: WorkoutHeartRateSourceMetadata?
    var isFallback: Bool

    nonisolated var id: String {
        [
            sourceKind.rawValue,
            String(Int(startedAt.timeIntervalSinceReferenceDate)),
            endedAt.map { String(Int($0.timeIntervalSinceReferenceDate)) } ?? "live",
            isFallback ? "fallback" : "primary"
        ].joined(separator: "-")
    }

    nonisolated var displayName: String {
        metadata?.displayName ?? sourceKind.displayName
    }
}

enum WorkoutHeartRateFallbackStatus: String, Codable, Hashable {
    case primaryAppleWatch
    case primaryGarmin
    case backupAirPodsAvailable
    case appleWatchDisconnectedUsingAirPods
    case garminDisconnectedUsingAirPods
    case airPodsUnavailableHeartRatePaused

    nonisolated var message: String {
        switch self {
        case .primaryAppleWatch:
            return "Primary source: Apple Watch"
        case .primaryGarmin:
            return "Primary source: Garmin"
        case .backupAirPodsAvailable:
            return "Backup source available: AirPods Pro 3"
        case .appleWatchDisconnectedUsingAirPods:
            return "Apple Watch disconnected — using AirPods Pro 3 heart rate"
        case .garminDisconnectedUsingAirPods:
            return "Garmin disconnected — using AirPods Pro 3 heart rate"
        case .airPodsUnavailableHeartRatePaused:
            return "AirPods Pro 3 unavailable — heart rate paused"
        }
    }

    nonisolated var usesAirPodsFallback: Bool {
        self == .appleWatchDisconnectedUsingAirPods || self == .garminDisconnectedUsingAirPods
    }
}

struct WorkoutHeartRateFallbackState: Equatable {
    var status: WorkoutHeartRateFallbackStatus?
    var sourceHistory: [WorkoutHeartRateSourceSegment]
    var latestMetadata: WorkoutHeartRateSourceMetadata?

    nonisolated static let inactive = WorkoutHeartRateFallbackState(
        status: nil,
        sourceHistory: [],
        latestMetadata: nil
    )
}

struct WorkoutHeartRateFallbackSample: Equatable {
    var beatsPerMinute: Double
    var sampledAt: Date
    var metadata: WorkoutHeartRateSourceMetadata
}

struct WorkoutHeartRateFallbackPolicy: Equatable {
    var primaryStaleAfter: TimeInterval = 35
    var backupSampleFreshnessWindow: TimeInterval = 45

    nonisolated init(
        primaryStaleAfter: TimeInterval = 35,
        backupSampleFreshnessWindow: TimeInterval = 45
    ) {
        self.primaryStaleAfter = primaryStaleAfter
        self.backupSampleFreshnessWindow = backupSampleFreshnessWindow
    }

    nonisolated func status(
        primarySource: WorkoutHeartRateSourceKind,
        primaryLastSeenAt: Date?,
        airPodsLastSeenAt: Date?,
        workoutStartedAt: Date,
        now: Date,
        isWorkoutActive: Bool,
        primaryMarkedUnavailable: Bool = false
    ) -> WorkoutHeartRateFallbackStatus? {
        guard isWorkoutActive,
              primarySource.canBePrimaryWorkoutSource else {
            return nil
        }

        let hasRecentAirPodsSample = airPodsLastSeenAt
            .map { now.timeIntervalSince($0) <= backupSampleFreshnessWindow } ?? false

        let primaryIsFresh: Bool
        if primaryMarkedUnavailable {
            primaryIsFresh = false
        } else if let primaryLastSeenAt {
            primaryIsFresh = now.timeIntervalSince(primaryLastSeenAt) <= primaryStaleAfter
        } else {
            primaryIsFresh = now.timeIntervalSince(workoutStartedAt) <= primaryStaleAfter
        }

        if primaryIsFresh {
            if hasRecentAirPodsSample {
                return .backupAirPodsAvailable
            }
            return primarySource == .garmin ? .primaryGarmin : .primaryAppleWatch
        }

        if hasRecentAirPodsSample {
            return primarySource == .garmin
                ? .garminDisconnectedUsingAirPods
                : .appleWatchDisconnectedUsingAirPods
        }

        return .airPodsUnavailableHeartRatePaused
    }
}

enum WorkoutHeartRateSourceClassifier {
    nonisolated static func classify(
        sourceName: String?,
        sourceBundleIdentifier: String?,
        productType: String?,
        deviceName: String?,
        deviceManufacturer: String?,
        deviceModel: String?
    ) -> WorkoutHeartRateSourceKind {
        let normalizedText = [
            sourceName,
            sourceBundleIdentifier,
            productType,
            deviceName,
            deviceManufacturer,
            deviceModel
        ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        if normalizedText.contains("airpods") || normalizedText.contains("airpod") {
            return .airPodsPro3
        }
        if normalizedText.contains("garmin") {
            return .garmin
        }
        if normalizedText.contains("apple watch") ||
            normalizedText.contains("watch") ||
            normalizedText.contains("com.apple.watch") {
            return .appleWatch
        }
        if normalizedText.contains("healthkit") ||
            normalizedText.contains("apple health") ||
            normalizedText.contains("com.apple.health") {
            return .healthKit
        }
        return .unknown
    }
}

enum WorkoutHeartRateSourceSummaryFormatter {
    nonisolated static func summaryText(for history: [WorkoutHeartRateSourceSegment]) -> String? {
        let orderedSources = history
            .sorted { $0.startedAt < $1.startedAt }
            .reduce(into: [WorkoutHeartRateSourceSegment]()) { result, segment in
                if result.last?.sourceKind != segment.sourceKind {
                    result.append(segment)
                } else if let lastIndex = result.indices.last {
                    result[lastIndex] = segment
                }
            }

        guard !orderedSources.isEmpty else { return nil }

        let names = orderedSources.map { segment in
            if segment.sourceKind == .airPodsPro3, segment.isFallback {
                return "\(segment.displayName) fallback"
            }
            return segment.displayName
        }

        return "Heart rate source: \(names.joined(separator: " → "))"
    }
}

struct WorkoutHeartRateFallbackEnergyEstimator: Equatable {
    var estimatedActiveEnergyKilocalories: Double?
    private var lastSampleAt: Date?

    mutating func reset() {
        estimatedActiveEnergyKilocalories = nil
        lastSampleAt = nil
    }

    mutating func update(
        heartRate beatsPerMinute: Double,
        sampledAt: Date,
        currentEnergyKilocalories: Double?
    ) -> Double? {
        if let currentEnergyKilocalories {
            estimatedActiveEnergyKilocalories = max(
                estimatedActiveEnergyKilocalories ?? 0,
                currentEnergyKilocalories
            )
        }

        guard beatsPerMinute.isFinite, beatsPerMinute > 0 else {
            return estimatedActiveEnergyKilocalories
        }

        let previousSampleAt = lastSampleAt
        lastSampleAt = sampledAt

        guard let previousSampleAt else {
            return estimatedActiveEnergyKilocalories
        }

        let elapsedMinutes = max(0, min(sampledAt.timeIntervalSince(previousSampleAt), 20)) / 60
        guard elapsedMinutes > 0 else {
            return estimatedActiveEnergyKilocalories
        }

        let intensityMultiplier = max(0.75, min(3.25, beatsPerMinute / 95))
        let addedEnergy = elapsedMinutes * 4.5 * intensityMultiplier
        estimatedActiveEnergyKilocalories = (estimatedActiveEnergyKilocalories ?? 0) + addedEnergy
        return estimatedActiveEnergyKilocalories
    }
}
