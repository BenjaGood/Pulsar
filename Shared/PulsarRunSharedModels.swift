//
//  PulsarRunSharedModels.swift
//  Pulsar
//

import Foundation
import CoreLocation
import HealthKit

enum PulsarWorkoutStartedFrom: String, Codable, Hashable {
    case iPhone
    case appleWatch = "AppleWatch"
    case iPhoneRequestedWatchStart

    nonisolated var displayName: String {
        switch self {
        case .iPhone: "iPhone"
        case .appleWatch: "Apple Watch"
        case .iPhoneRequestedWatchStart: "Apple Watch"
        }
    }

    nonisolated var isAppleWatchRecorder: Bool {
        switch self {
        case .appleWatch, .iPhoneRequestedWatchStart:
            true
        case .iPhone:
            false
        }
    }
}

enum PulsarWorkoutMetadata {
    nonisolated static let brandName = "Pulsar"
    nonisolated static let sessionIdKey = "pulsarWorkoutSessionId"
    nonisolated static let workoutTypeKey = "pulsarWorkoutType"
    nonisolated static let startedFromKey = "pulsarStartedFrom"
    nonisolated static let legacySessionIdKey = "PulsarSessionID"

    nonisolated static func base(
        sessionId: UUID,
        workoutType: String,
        startedFrom: PulsarWorkoutStartedFrom
    ) -> [String: Any] {
        [
            HKMetadataKeyWorkoutBrandName: brandName,
            sessionIdKey: sessionId.uuidString,
            workoutTypeKey: canonicalWorkoutType(workoutType) ?? workoutType,
            startedFromKey: startedFrom.rawValue
        ]
    }

    nonisolated static func sessionId(from metadata: [String: Any]?) -> UUID? {
        guard let metadata else { return nil }
        let rawValue = metadata[sessionIdKey] as? String ?? metadata[legacySessionIdKey] as? String
        return rawValue.flatMap(UUID.init(uuidString:))
    }

    nonisolated static func workoutType(from metadata: [String: Any]?) -> String? {
        let rawValue = (metadata?[workoutTypeKey] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return canonicalWorkoutType(rawValue) ?? rawValue
    }

    nonisolated static func startedFrom(from metadata: [String: Any]?) -> PulsarWorkoutStartedFrom? {
        guard let rawValue = (metadata?[startedFromKey] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return PulsarWorkoutStartedFrom(rawValue: rawValue)
    }

    nonisolated static func canonicalWorkoutType(_ rawValue: String?) -> String? {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else { return nil }
        if let outdoorKind = PulsarOutdoorWorkoutKind(workoutTypeRawValue: rawValue) {
            return outdoorKind.rawValue
        }
        return nil
    }
}

enum PulsarOutdoorWorkoutKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case running
    case walking
    case hiking
    case cycling
    case hiit
    case strength
    case yoga
    case pilates
    case swimming
    case rowing
    case dance
    case boxing
    case stretching
    case core
    case mobility
    case elliptical
    case stairClimber
    case cooldown
    case other

    nonisolated var id: String { rawValue }

    nonisolated init?(workoutTypeRawValue rawValue: String) {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()

        for kind in Self.allCases {
            if normalized == kind.rawValue.lowercased() ||
                normalized == kind.displayName
                    .replacingOccurrences(of: " ", with: "")
                    .lowercased() ||
                normalized == kind.shortName
                    .replacingOccurrences(of: " ", with: "")
                    .lowercased() {
                self = kind
                return
            }
        }

        return nil
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        if let kind = Self(workoutTypeRawValue: rawValue) {
            self = kind
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Invalid Pulsar outdoor workout kind: \(rawValue)"
        )
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    nonisolated var displayName: String {
        switch self {
        case .running: "Running"
        case .walking: "Walking"
        case .hiking: "Hiking"
        case .cycling: "Cycling"
        case .hiit: "HIIT"
        case .strength: "Strength"
        case .yoga: "Yoga"
        case .pilates: "Pilates"
        case .swimming: "Swimming"
        case .rowing: "Rowing"
        case .dance: "Dance"
        case .boxing: "Boxing"
        case .stretching: "Stretching"
        case .core: "Core"
        case .mobility: "Mobility"
        case .elliptical: "Elliptical"
        case .stairClimber: "Stairs"
        case .cooldown: "Cooldown"
        case .other: "Workout"
        }
    }

    nonisolated var shortName: String {
        switch self {
        case .running: "Run"
        case .walking: "Walk"
        case .hiking: "Hike"
        case .cycling: "Ride"
        case .hiit: "HIIT"
        case .strength: "Strength"
        case .yoga: "Yoga"
        case .pilates: "Pilates"
        case .swimming: "Swim"
        case .rowing: "Row"
        case .dance: "Dance"
        case .boxing: "Boxing"
        case .stretching: "Stretch"
        case .core: "Core"
        case .mobility: "Mobility"
        case .elliptical: "Elliptical"
        case .stairClimber: "Stairs"
        case .cooldown: "Cooldown"
        case .other: "Workout"
        }
    }

    nonisolated var actionName: String {
        switch self {
        case .running: "run"
        case .walking: "walk"
        case .hiking: "hike"
        case .cycling: "ride"
        case .hiit: "HIIT workout"
        case .strength: "strength workout"
        case .yoga: "yoga session"
        case .pilates: "pilates session"
        case .swimming: "swim"
        case .rowing: "row"
        case .dance: "dance workout"
        case .boxing: "boxing workout"
        case .stretching: "stretching session"
        case .core: "core workout"
        case .mobility: "mobility session"
        case .elliptical: "elliptical workout"
        case .stairClimber: "stair workout"
        case .cooldown: "cooldown"
        case .other: "workout"
        }
    }

    nonisolated var outdoorTitle: String {
        isOutdoorDistanceWorkout ? "Outdoor \(shortName)" : displayName
    }

    nonisolated var startTitle: String {
        "Start \(shortName)"
    }

    nonisolated var savedTitle: String {
        "\(shortName) Saved"
    }

    nonisolated var systemImageName: String {
        switch self {
        case .running: "figure.run"
        case .walking: "figure.walk"
        case .hiking: "mountain.2.fill"
        case .cycling: "bicycle"
        case .hiit: "flame.fill"
        case .strength: "figure.strengthtraining.traditional"
        case .yoga: "figure.yoga"
        case .pilates: "figure.core.training"
        case .swimming: "figure.pool.swim"
        case .rowing: "figure.rower"
        case .dance: "figure.dance"
        case .boxing: "figure.boxing"
        case .stretching: "figure.flexibility"
        case .core: "figure.core.training"
        case .mobility: "figure.cooldown"
        case .elliptical: "figure.elliptical"
        case .stairClimber: "figure.stair.stepper"
        case .cooldown: "figure.cooldown"
        case .other: "figure.mixed.cardio"
        }
    }

    nonisolated var healthKitActivityType: HKWorkoutActivityType {
        switch self {
        case .running: .running
        case .walking: .walking
        case .hiking: .hiking
        case .cycling: .cycling
        case .hiit: .highIntensityIntervalTraining
        case .strength: .traditionalStrengthTraining
        case .yoga: .yoga
        case .pilates: .pilates
        case .swimming: .swimming
        case .rowing: .rowing
        case .dance: .cardioDance
        case .boxing: .boxing
        case .stretching: .flexibility
        case .core: .coreTraining
        case .mobility: .other
        case .elliptical: .elliptical
        case .stairClimber: .stairClimbing
        case .cooldown: .cooldown
        case .other: .other
        }
    }

    nonisolated var defaultLocationType: HKWorkoutSessionLocationType {
        switch self {
        case .running, .walking, .hiking, .cycling:
            .outdoor
        case .swimming:
            .unknown
        case .hiit, .strength, .yoga, .pilates, .rowing, .dance, .boxing, .stretching, .core, .mobility, .elliptical, .stairClimber, .cooldown, .other:
            .indoor
        }
    }

    nonisolated var isOutdoorDistanceWorkout: Bool {
        switch self {
        case .running, .walking, .hiking, .cycling:
            true
        case .hiit, .strength, .yoga, .pilates, .swimming, .rowing, .dance, .boxing, .stretching, .core, .mobility, .elliptical, .stairClimber, .cooldown, .other:
            false
        }
    }

    nonisolated init(activityType: HKWorkoutActivityType) {
        switch activityType {
        case .running:
            self = .running
        case .walking:
            self = .walking
        case .hiking:
            self = .hiking
        case .cycling:
            self = .cycling
        case .highIntensityIntervalTraining:
            self = .hiit
        case .traditionalStrengthTraining, .functionalStrengthTraining:
            self = .strength
        case .yoga:
            self = .yoga
        case .pilates:
            self = .pilates
        case .swimming:
            self = .swimming
        case .rowing:
            self = .rowing
        case .cardioDance, .socialDance:
            self = .dance
        case .boxing, .kickboxing:
            self = .boxing
        case .flexibility:
            self = .stretching
        case .coreTraining:
            self = .core
        case .elliptical:
            self = .elliptical
        case .stairClimbing, .stairs:
            self = .stairClimber
        case .cooldown:
            self = .cooldown
        default:
            self = .other
        }
    }

    nonisolated init(metadata: [String: Any]?, fallbackActivityType: HKWorkoutActivityType) {
        if let rawType = PulsarWorkoutMetadata.workoutType(from: metadata),
           let workoutKind = PulsarOutdoorWorkoutKind(workoutTypeRawValue: rawType) {
            self = workoutKind
        } else {
            self = PulsarOutdoorWorkoutKind(activityType: fallbackActivityType)
        }
    }
}

enum PulsarActiveWorkoutSyncPhase: String, Codable, Hashable {
    case starting
    case active
    case paused
    case resumed
    case ending
    case ended
    case failed
    case cancelled

    nonisolated var isLive: Bool {
        switch self {
        case .starting, .active, .paused, .resumed, .ending:
            true
        case .ended, .failed, .cancelled:
            false
        }
    }

    nonisolated var isRestoreEligible: Bool {
        switch self {
        case .starting, .active, .paused, .resumed:
            true
        case .ending, .ended, .failed, .cancelled:
            false
        }
    }

    nonisolated var mergePriority: Int {
        switch self {
        case .starting:
            0
        case .active:
            1
        case .resumed:
            2
        case .paused:
            3
        case .ending:
            4
        case .ended:
            5
        case .cancelled:
            6
        case .failed:
            7
        }
    }
}

enum PulsarActiveWorkoutSyncKind: Codable, Hashable {
    case outdoor(PulsarOutdoorWorkoutKind)
    case gym(PulsarGymWorkoutKind)

    private enum CodingKeys: String, CodingKey {
        case category
        case outdoor
        case gym
    }

    private enum Category: String, Codable {
        case outdoor
        case gym
    }

    nonisolated var displayName: String {
        switch self {
        case .outdoor(let kind):
            kind.displayName
        case .gym(let kind):
            kind.displayName
        }
    }

    nonisolated var workoutTypeRawValue: String {
        switch self {
        case .outdoor(let kind):
            kind.rawValue
        case .gym(let kind):
            kind.rawValue
        }
    }

    nonisolated var outdoorWorkoutKind: PulsarOutdoorWorkoutKind? {
        if case .outdoor(let kind) = self { return kind }
        return nil
    }

    nonisolated var gymWorkoutKind: PulsarGymWorkoutKind? {
        if case .gym(let kind) = self { return kind }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Category.self, forKey: .category) {
        case .outdoor:
            self = .outdoor(try container.decode(PulsarOutdoorWorkoutKind.self, forKey: .outdoor))
        case .gym:
            self = .gym(try container.decode(PulsarGymWorkoutKind.self, forKey: .gym))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .outdoor(let kind):
            try container.encode(Category.outdoor, forKey: .category)
            try container.encode(kind, forKey: .outdoor)
        case .gym(let kind):
            try container.encode(Category.gym, forKey: .category)
            try container.encode(kind, forKey: .gym)
        }
    }
}

struct PulsarActiveWorkoutSyncState: Codable, Hashable, Identifiable {
    nonisolated var id: UUID { sessionId }

    var sessionId: UUID
    var kind: PulsarActiveWorkoutSyncKind
    var displayName: String
    var startedAt: Date
    var endedAt: Date?
    var startedFrom: PulsarWorkoutStartedFrom
    var lastUpdatedFrom: PulsarWorkoutStartedFrom
    var phase: PulsarActiveWorkoutSyncPhase
    var elapsedSeconds: Int
    var currentHeartRate: Double?
    var activeEnergyKilocalories: Double?
    var healthKitWorkoutUUID: UUID?
    var updatedAt: Date
    var sessionGeneration: Int?
    var runMetricsUpdatedAt: Date?
    var movingSeconds: Int?
    var distanceMeters: Double?
    var currentPaceSecondsPerKilometer: Double?
    var averagePaceSecondsPerKilometer: Double?
    var splitPaceSecondsPerKilometer: Double?
    var activeSplitIndex: Int?
    var elevationGainMeters: Double?
    var elevationLossMeters: Double?
    var currentElevationMeters: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var stepCount: Int?
    var cadenceStepsPerMinute: Double?
    var routePointCount: Int?
    var lastLatitude: Double?
    var lastLongitude: Double?
    var lastLocationUpdatedAt: Date?

    nonisolated var isEnded: Bool {
        phase == .ended || phase == .failed || phase == .cancelled
    }

    nonisolated var averageSpeedMetersPerSecond: Double? {
        guard let distanceMeters,
              distanceMeters > 0,
              let movingSeconds,
              movingSeconds > 0 else { return nil }
        return distanceMeters / Double(movingSeconds)
    }

    nonisolated init(
        sessionId: UUID,
        kind: PulsarActiveWorkoutSyncKind,
        displayName: String? = nil,
        startedAt: Date,
        endedAt: Date? = nil,
        startedFrom: PulsarWorkoutStartedFrom,
        lastUpdatedFrom: PulsarWorkoutStartedFrom,
        phase: PulsarActiveWorkoutSyncPhase,
        elapsedSeconds: Int,
        currentHeartRate: Double? = nil,
        activeEnergyKilocalories: Double? = nil,
        healthKitWorkoutUUID: UUID? = nil,
        updatedAt: Date = Date(),
        sessionGeneration: Int? = nil,
        runMetricsUpdatedAt: Date? = nil,
        movingSeconds: Int? = nil,
        distanceMeters: Double? = nil,
        currentPaceSecondsPerKilometer: Double? = nil,
        averagePaceSecondsPerKilometer: Double? = nil,
        splitPaceSecondsPerKilometer: Double? = nil,
        activeSplitIndex: Int? = nil,
        elevationGainMeters: Double? = nil,
        elevationLossMeters: Double? = nil,
        currentElevationMeters: Double? = nil,
        averageHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        stepCount: Int? = nil,
        cadenceStepsPerMinute: Double? = nil,
        routePointCount: Int? = nil,
        lastLatitude: Double? = nil,
        lastLongitude: Double? = nil,
        lastLocationUpdatedAt: Date? = nil
    ) {
        self.sessionId = sessionId
        self.kind = kind
        self.displayName = displayName ?? kind.displayName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.startedFrom = startedFrom
        self.lastUpdatedFrom = lastUpdatedFrom
        self.phase = phase
        self.elapsedSeconds = elapsedSeconds
        self.currentHeartRate = currentHeartRate
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.healthKitWorkoutUUID = healthKitWorkoutUUID
        self.updatedAt = updatedAt
        self.sessionGeneration = sessionGeneration ?? Int(startedAt.timeIntervalSince1970.rounded())
        self.runMetricsUpdatedAt = runMetricsUpdatedAt
        self.movingSeconds = movingSeconds
        self.distanceMeters = distanceMeters
        self.currentPaceSecondsPerKilometer = currentPaceSecondsPerKilometer
        self.averagePaceSecondsPerKilometer = averagePaceSecondsPerKilometer
        self.splitPaceSecondsPerKilometer = splitPaceSecondsPerKilometer
        self.activeSplitIndex = activeSplitIndex
        self.elevationGainMeters = elevationGainMeters
        self.elevationLossMeters = elevationLossMeters
        self.currentElevationMeters = currentElevationMeters
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.stepCount = stepCount
        self.cadenceStepsPerMinute = cadenceStepsPerMinute
        self.routePointCount = routePointCount
        self.lastLatitude = lastLatitude
        self.lastLongitude = lastLongitude
        self.lastLocationUpdatedAt = lastLocationUpdatedAt
    }
}

enum ActiveWorkoutUpdateDecision: Equatable {
    case appliedActive(UUID)
    case appliedPaused(UUID)
    case endedCurrent(UUID)
    case failedCurrentAndShouldAlert(UUID)
    case ignoredStaleFailed(UUID)
    case ignoredDuplicateStaleFailed(UUID)
    case ignoredInvalidNoSession
    case ignoredHistoricalOnly

    nonisolated var sessionID: UUID? {
        switch self {
        case .appliedActive(let sessionID),
             .appliedPaused(let sessionID),
             .endedCurrent(let sessionID),
             .failedCurrentAndShouldAlert(let sessionID),
             .ignoredStaleFailed(let sessionID),
             .ignoredDuplicateStaleFailed(let sessionID):
            sessionID
        case .ignoredInvalidNoSession, .ignoredHistoricalOnly:
            nil
        }
    }

    nonisolated var didApplySyncState: Bool {
        switch self {
        case .appliedActive, .appliedPaused, .endedCurrent, .failedCurrentAndShouldAlert:
            true
        case .ignoredStaleFailed, .ignoredDuplicateStaleFailed, .ignoredInvalidNoSession, .ignoredHistoricalOnly:
            false
        }
    }

    nonisolated var isIgnoredFailedUpdate: Bool {
        switch self {
        case .ignoredStaleFailed, .ignoredDuplicateStaleFailed:
            true
        case .appliedActive, .appliedPaused, .endedCurrent, .failedCurrentAndShouldAlert, .ignoredInvalidNoSession, .ignoredHistoricalOnly:
            false
        }
    }

    nonisolated static func appliedDecision(for state: PulsarActiveWorkoutSyncState) -> ActiveWorkoutUpdateDecision {
        switch state.phase {
        case .paused:
            .appliedPaused(state.sessionId)
        case .ended, .cancelled:
            .endedCurrent(state.sessionId)
        case .failed:
            .failedCurrentAndShouldAlert(state.sessionId)
        case .starting, .active, .resumed, .ending:
            .appliedActive(state.sessionId)
        }
    }

    nonisolated static func userInterfaceDecision(
        for state: PulsarActiveWorkoutSyncState?,
        currentSessionID: UUID?,
        currentSessionUpdatedAt: Date? = nil,
        currentSessionCanShowConnectionLostAlert: Bool = true,
        ignoredFailedSessionIDs: Set<UUID>
    ) -> ActiveWorkoutUpdateDecision {
        guard let state else { return .ignoredInvalidNoSession }

        if state.phase == .failed {
            if ignoredFailedSessionIDs.contains(state.sessionId) {
                return .ignoredDuplicateStaleFailed(state.sessionId)
            }
            guard let currentSessionID else {
                return .ignoredStaleFailed(state.sessionId)
            }
            guard currentSessionID == state.sessionId else {
                return .ignoredStaleFailed(state.sessionId)
            }
            guard currentSessionCanShowConnectionLostAlert else {
                return .ignoredStaleFailed(state.sessionId)
            }
            return .failedCurrentAndShouldAlert(state.sessionId)
        }

        if state.isEnded {
            guard currentSessionID == state.sessionId else {
                return .ignoredHistoricalOnly
            }
            if let currentSessionUpdatedAt,
               state.updatedAt < currentSessionUpdatedAt {
                return .ignoredHistoricalOnly
            }
            return .endedCurrent(state.sessionId)
        }

        if state.phase == .ending,
           currentSessionID != state.sessionId {
            return .ignoredHistoricalOnly
        }

        return appliedDecision(for: state)
    }

    nonisolated static func syncStoreFailedDecision(
        for state: PulsarActiveWorkoutSyncState,
        priorCurrentSessionID: UUID?,
        priorCurrentWorkoutCanShowConnectionLostAlert: Bool = true,
        priorSyncedSessionID: UUID?,
        ignoredFailedSessionIDs: Set<UUID>,
        isIncomingFromCounterpart: Bool
    ) -> ActiveWorkoutUpdateDecision {
        if ignoredFailedSessionIDs.contains(state.sessionId) {
            return .ignoredDuplicateStaleFailed(state.sessionId)
        }

        guard let priorCurrentSessionID else {
            return .ignoredStaleFailed(state.sessionId)
        }

        guard priorCurrentSessionID == state.sessionId,
              priorCurrentWorkoutCanShowConnectionLostAlert else {
            return .ignoredStaleFailed(state.sessionId)
        }

        return .failedCurrentAndShouldAlert(state.sessionId)
    }
}

struct ActiveWorkoutUpdateEvent: Equatable {
    var decision: ActiveWorkoutUpdateDecision
    var state: PulsarActiveWorkoutSyncState
    var source: String
}

extension PulsarActiveWorkoutSyncState {
    nonisolated init(runSnapshot snapshot: PulsarRunMetricSnapshot, startedFrom: PulsarWorkoutStartedFrom, lastUpdatedFrom: PulsarWorkoutStartedFrom) {
        let startedAt = snapshot.startedAt ?? Date()
        let sessionId = snapshot.pulsarWorkoutSessionId ?? UUID()
        self.init(
            sessionId: sessionId,
            kind: .outdoor(snapshot.workoutKind),
            displayName: snapshot.workoutKind.displayName,
            startedAt: startedAt,
            endedAt: snapshot.endedAt,
            startedFrom: startedFrom,
            lastUpdatedFrom: lastUpdatedFrom,
            phase: PulsarActiveWorkoutSyncPhase(runPhase: snapshot.phase),
            elapsedSeconds: Int(snapshot.elapsedTime.rounded()),
            currentHeartRate: snapshot.currentHeartRate,
            activeEnergyKilocalories: snapshot.activeEnergyKilocalories,
            healthKitWorkoutUUID: nil,
            runMetricsUpdatedAt: Date(),
            movingSeconds: Int(snapshot.movingTime.rounded()),
            distanceMeters: snapshot.distanceMeters,
            currentPaceSecondsPerKilometer: snapshot.currentPaceSecondsPerKilometer,
            averagePaceSecondsPerKilometer: snapshot.averagePaceSecondsPerKilometer,
            splitPaceSecondsPerKilometer: snapshot.splitPaceSecondsPerKilometer,
            activeSplitIndex: snapshot.activeSplitIndex,
            elevationGainMeters: snapshot.elevationGainMeters,
            elevationLossMeters: snapshot.elevationLossMeters,
            currentElevationMeters: snapshot.currentElevationMeters,
            averageHeartRate: snapshot.averageHeartRate,
            maxHeartRate: snapshot.maxHeartRate,
            stepCount: snapshot.stepCount,
            cadenceStepsPerMinute: snapshot.cadenceStepsPerMinute,
            routePointCount: snapshot.route.count,
            lastLatitude: snapshot.route.last?.latitude,
            lastLongitude: snapshot.route.last?.longitude,
            lastLocationUpdatedAt: snapshot.route.last?.timestamp
        )
    }

    nonisolated init(gymState state: ActiveGymWorkoutState, lastUpdatedFrom: PulsarWorkoutStartedFrom? = nil) {
        let workoutKind = state.workoutKind ?? PulsarGymWorkoutKind.inferred(
            routineName: state.routineName,
            exerciseCount: state.exercises.count
        )
        let startedFrom = state.startedFrom ?? .iPhone
        self.init(
            sessionId: state.sessionId,
            kind: .gym(workoutKind),
            displayName: workoutKind == .freeWorkout ? workoutKind.displayName : state.routineName,
            startedAt: state.startedAt,
            endedAt: state.isFinished ? state.updatedAt : nil,
            startedFrom: startedFrom,
            lastUpdatedFrom: lastUpdatedFrom ?? startedFrom,
            phase: state.isFinished ? .ended : .active,
            elapsedSeconds: state.elapsedSeconds,
            currentHeartRate: state.currentHeartRate,
            activeEnergyKilocalories: state.activeEnergyKilocalories,
            healthKitWorkoutUUID: state.healthKitWorkoutUUID,
            updatedAt: state.updatedAt
        )
    }
}

extension PulsarActiveWorkoutSyncPhase {
    nonisolated init(runPhase: PulsarRunPhase) {
        switch runPhase {
        case .idle:
            self = .ended
        case .requestingPermissions, .countingDown, .connectingToWatch:
            self = .starting
        case .running:
            self = .active
        case .paused:
            self = .paused
        case .finishing:
            self = .ending
        case .finished:
            self = .ended
        case .failed:
            self = .failed
        }
    }

    nonisolated var runPhase: PulsarRunPhase {
        switch self {
        case .starting:
            .connectingToWatch
        case .active, .resumed:
            .running
        case .paused:
            .paused
        case .ending:
            .finishing
        case .ended:
            .finished
        case .failed:
            .failed
        case .cancelled:
            .finished
        }
    }
}

enum PulsarRunRecordingSource: String, Codable, Hashable {
    case appleWatch
    case iPhone

    nonisolated var label: String {
        switch self {
        case .appleWatch: "Apple Watch"
        case .iPhone: "iPhone"
        }
    }
}

enum PulsarWatchRecorderFallbackReason: String, Codable, Hashable {
    case unsupported
    case activationPending
    case noPairedWatch
    case watchAppNotInstalled
    case notReachable
    case watchLaunchFailed
    case mirroringTimedOut

    nonisolated var logValue: String { rawValue }
}

struct PulsarWatchRecorderFallbackPrompt: Identifiable, Equatable {
    let id = UUID()
    var reason: PulsarWatchRecorderFallbackReason
    var title: String
    var message: String
}

enum PulsarRunPhase: String, Codable, Hashable {
    case idle
    case requestingPermissions
    case countingDown
    case connectingToWatch
    case running
    case paused
    case finishing
    case finished
    case failed
}

struct PulsarRunOptions: Codable, Equatable {
    var prefersWatchRecorder: Bool
    var autoPauseEnabled: Bool
    var audioCuesEnabled: Bool

    nonisolated static let `default` = PulsarRunOptions(
        prefersWatchRecorder: true,
        autoPauseEnabled: true,
        audioCuesEnabled: false
    )
}

struct PulsarRunCoordinate: Codable, Hashable, Identifiable {
    nonisolated var id: String { "\(timestamp.timeIntervalSince1970)-\(latitude)-\(longitude)" }
    var latitude: Double
    var longitude: Double
    var altitude: Double?
    var horizontalAccuracy: Double?
    var verticalAccuracy: Double?
    var timestamp: Date

    nonisolated init(
        latitude: Double,
        longitude: Double,
        altitude: Double? = nil,
        horizontalAccuracy: Double? = nil,
        verticalAccuracy: Double? = nil,
        timestamp: Date = Date()
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.timestamp = timestamp
    }
}

struct PulsarRunMetricSnapshot: Codable, Equatable {
    var pulsarWorkoutSessionId: UUID?
    var phase: PulsarRunPhase
    var source: PulsarRunRecordingSource
    var workoutKind: PulsarOutdoorWorkoutKind
    var startedAt: Date?
    var endedAt: Date?
    var elapsedTime: TimeInterval
    var movingTime: TimeInterval
    var distanceMeters: Double
    var currentPaceSecondsPerKilometer: Double?
    var averagePaceSecondsPerKilometer: Double?
    var splitPaceSecondsPerKilometer: Double?
    var activeSplitIndex: Int
    var elevationGainMeters: Double
    var elevationLossMeters: Double
    var currentElevationMeters: Double?
    var activeEnergyKilocalories: Double?
    var currentHeartRate: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var stepCount: Int?
    var cadenceStepsPerMinute: Double?
    var runningPowerWatts: Double?
    var strideLengthMeters: Double?
    var groundContactTimeMilliseconds: Double?
    var verticalOscillationCentimeters: Double?
    var route: [PulsarRunCoordinate]
    var splits: [PulsarRunSplit]
    var statusMessage: String?
    var heartRateSourceStatusMessage: String?
    var heartRateSourceHistory: [WorkoutHeartRateSourceSegment]?

    nonisolated static let empty = PulsarRunMetricSnapshot(
        pulsarWorkoutSessionId: nil,
        phase: .idle,
        source: .iPhone,
        workoutKind: .running,
        startedAt: nil,
        endedAt: nil,
        elapsedTime: 0,
        movingTime: 0,
        distanceMeters: 0,
        currentPaceSecondsPerKilometer: nil,
        averagePaceSecondsPerKilometer: nil,
        splitPaceSecondsPerKilometer: nil,
        activeSplitIndex: 1,
        elevationGainMeters: 0,
        elevationLossMeters: 0,
        currentElevationMeters: nil,
        activeEnergyKilocalories: nil,
        currentHeartRate: nil,
        averageHeartRate: nil,
        maxHeartRate: nil,
        stepCount: nil,
        cadenceStepsPerMinute: nil,
        runningPowerWatts: nil,
        strideLengthMeters: nil,
        groundContactTimeMilliseconds: nil,
        verticalOscillationCentimeters: nil,
        route: [],
        splits: [],
        statusMessage: nil,
        heartRateSourceStatusMessage: nil,
        heartRateSourceHistory: nil
    )
}

nonisolated struct PulsarRunSplit: Codable, Equatable, Identifiable {
    nonisolated var id: Int { index }
    var index: Int
    var distanceMeters: Double
    var movingTime: TimeInterval
    var elevationGainMeters: Double
    var elevationLossMeters: Double
    var averageHeartRate: Double?

    init(
        index: Int,
        distanceMeters: Double,
        movingTime: TimeInterval,
        elevationGainMeters: Double,
        elevationLossMeters: Double = 0,
        averageHeartRate: Double?
    ) {
        self.index = index
        self.distanceMeters = distanceMeters
        self.movingTime = movingTime
        self.elevationGainMeters = elevationGainMeters
        self.elevationLossMeters = elevationLossMeters
        self.averageHeartRate = averageHeartRate
    }

    private enum CodingKeys: String, CodingKey {
        case index
        case distanceMeters
        case movingTime
        case elevationGainMeters
        case elevationLossMeters
        case averageHeartRate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decode(Int.self, forKey: .index)
        distanceMeters = try container.decode(Double.self, forKey: .distanceMeters)
        movingTime = try container.decode(TimeInterval.self, forKey: .movingTime)
        elevationGainMeters = try container.decodeIfPresent(Double.self, forKey: .elevationGainMeters) ?? 0
        elevationLossMeters = try container.decodeIfPresent(Double.self, forKey: .elevationLossMeters) ?? 0
        averageHeartRate = try container.decodeIfPresent(Double.self, forKey: .averageHeartRate)
    }

    nonisolated var paceSecondsPerKilometer: Double? {
        guard distanceMeters > 0 else { return nil }
        return movingTime / (distanceMeters / 1_000)
    }
}

struct PulsarRunSummary: Codable, Equatable, Identifiable {
    var id: UUID
    var pulsarWorkoutSessionId: UUID?
    var workoutUUID: UUID?
    var workoutKind: PulsarOutdoorWorkoutKind
    var startedAt: Date
    var endedAt: Date
    var source: PulsarRunRecordingSource
    var sourceName: String?
    var heartRateSourceHistory: [WorkoutHeartRateSourceSegment]
    var heartRateSourceStatusMessage: String?
    var distanceMeters: Double
    var elapsedTime: TimeInterval
    var movingTime: TimeInterval
    var activeEnergyKilocalories: Double?
    var elevationGainMeters: Double
    var elevationLossMeters: Double
    var minimumElevationMeters: Double?
    var maximumElevationMeters: Double?
    var weatherSummary: String?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var steps: Int?
    var averageCadenceStepsPerMinute: Double?
    var route: [PulsarRunCoordinate]
    var splits: [PulsarRunSplit]

    nonisolated var averagePaceSecondsPerKilometer: Double? {
        guard distanceMeters > 0 else { return nil }
        return movingTime / (distanceMeters / 1_000)
    }

    nonisolated var averageSpeedMetersPerSecond: Double? {
        guard movingTime > 0, distanceMeters > 0 else { return nil }
        return distanceMeters / movingTime
    }

    nonisolated var stoppedTime: TimeInterval {
        max(0, elapsedTime - movingTime)
    }

    nonisolated var gpsRoute: GPSWorkoutRoute {
        GPSWorkoutRoute(
            runCoordinates: route,
            source: source == .appleWatch ? .healthKitRoute : .pulsarLive,
            capturedAt: endedAt
        )
    }

    nonisolated var effectiveElevationGainMeters: Double {
        elevationGainMeters > 0 ? elevationGainMeters : gpsRoute.elevationMetrics.gainMeters
    }

    nonisolated var effectiveElevationLossMeters: Double {
        elevationLossMeters > 0 ? elevationLossMeters : gpsRoute.elevationMetrics.lossMeters
    }

    nonisolated var sourceDeviceName: String {
        if let trimmedSourceName = sourceName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmedSourceName.isEmpty {
            return trimmedSourceName
        }
        return source.label
    }

    nonisolated var heartRateSourceSummaryText: String? {
        WorkoutHeartRateSourceSummaryFormatter.summaryText(for: heartRateSourceHistory)
    }

    nonisolated init(
        id: UUID,
        pulsarWorkoutSessionId: UUID? = nil,
        workoutUUID: UUID?,
        workoutKind: PulsarOutdoorWorkoutKind = .other,
        startedAt: Date,
        endedAt: Date,
        source: PulsarRunRecordingSource,
        sourceName: String? = nil,
        heartRateSourceHistory: [WorkoutHeartRateSourceSegment] = [],
        heartRateSourceStatusMessage: String? = nil,
        distanceMeters: Double,
        elapsedTime: TimeInterval,
        movingTime: TimeInterval,
        activeEnergyKilocalories: Double?,
        elevationGainMeters: Double,
        elevationLossMeters: Double = 0,
        minimumElevationMeters: Double? = nil,
        maximumElevationMeters: Double? = nil,
        weatherSummary: String? = nil,
        averageHeartRate: Double?,
        maxHeartRate: Double?,
        steps: Int?,
        averageCadenceStepsPerMinute: Double?,
        route: [PulsarRunCoordinate],
        splits: [PulsarRunSplit]
    ) {
        self.id = id
        self.pulsarWorkoutSessionId = pulsarWorkoutSessionId
        self.workoutUUID = workoutUUID
        self.workoutKind = workoutKind
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.source = source
        self.sourceName = sourceName
        self.heartRateSourceHistory = heartRateSourceHistory
        self.heartRateSourceStatusMessage = heartRateSourceStatusMessage
        self.distanceMeters = distanceMeters
        self.elapsedTime = elapsedTime
        self.movingTime = movingTime
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.elevationGainMeters = elevationGainMeters
        self.elevationLossMeters = elevationLossMeters
        self.minimumElevationMeters = minimumElevationMeters
        self.maximumElevationMeters = maximumElevationMeters
        self.weatherSummary = weatherSummary
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.steps = steps
        self.averageCadenceStepsPerMinute = averageCadenceStepsPerMinute
        self.route = route
        self.splits = splits
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case pulsarWorkoutSessionId
        case workoutUUID
        case workoutKind
        case startedAt
        case endedAt
        case source
        case sourceName
        case heartRateSourceHistory
        case heartRateSourceStatusMessage
        case distanceMeters
        case elapsedTime
        case movingTime
        case activeEnergyKilocalories
        case elevationGainMeters
        case elevationLossMeters
        case minimumElevationMeters
        case maximumElevationMeters
        case weatherSummary
        case averageHeartRate
        case maxHeartRate
        case steps
        case averageCadenceStepsPerMinute
        case route
        case splits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        pulsarWorkoutSessionId = try container.decodeIfPresent(UUID.self, forKey: .pulsarWorkoutSessionId)
        workoutUUID = try container.decodeIfPresent(UUID.self, forKey: .workoutUUID)
        workoutKind = try container.decodeIfPresent(PulsarOutdoorWorkoutKind.self, forKey: .workoutKind) ?? .other
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decode(Date.self, forKey: .endedAt)
        source = try container.decode(PulsarRunRecordingSource.self, forKey: .source)
        sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName)
        heartRateSourceHistory = try container.decodeIfPresent([WorkoutHeartRateSourceSegment].self, forKey: .heartRateSourceHistory) ?? []
        heartRateSourceStatusMessage = try container.decodeIfPresent(String.self, forKey: .heartRateSourceStatusMessage)
        distanceMeters = try container.decode(Double.self, forKey: .distanceMeters)
        elapsedTime = try container.decode(TimeInterval.self, forKey: .elapsedTime)
        movingTime = try container.decode(TimeInterval.self, forKey: .movingTime)
        activeEnergyKilocalories = try container.decodeIfPresent(Double.self, forKey: .activeEnergyKilocalories)
        elevationGainMeters = try container.decodeIfPresent(Double.self, forKey: .elevationGainMeters) ?? 0
        elevationLossMeters = try container.decodeIfPresent(Double.self, forKey: .elevationLossMeters) ?? 0
        minimumElevationMeters = try container.decodeIfPresent(Double.self, forKey: .minimumElevationMeters)
        maximumElevationMeters = try container.decodeIfPresent(Double.self, forKey: .maximumElevationMeters)
        weatherSummary = try container.decodeIfPresent(String.self, forKey: .weatherSummary)
        averageHeartRate = try container.decodeIfPresent(Double.self, forKey: .averageHeartRate)
        maxHeartRate = try container.decodeIfPresent(Double.self, forKey: .maxHeartRate)
        steps = try container.decodeIfPresent(Int.self, forKey: .steps)
        averageCadenceStepsPerMinute = try container.decodeIfPresent(Double.self, forKey: .averageCadenceStepsPerMinute)
        route = try container.decode([PulsarRunCoordinate].self, forKey: .route)
        splits = try container.decode([PulsarRunSplit].self, forKey: .splits)
    }
}

struct PulsarRunSessionIdentity: Codable, Equatable {
    var sessionId: UUID
    var workoutKind: PulsarOutdoorWorkoutKind
    var startedFrom: PulsarWorkoutStartedFrom
    var sentAt: Date
}

struct PulsarRunRouteDelta: Codable, Equatable {
    var sessionId: UUID
    var workoutKind: PulsarOutdoorWorkoutKind
    var points: [PulsarRunCoordinate]
    var sentAt: Date
}

enum PulsarRunControlCommand: String, Codable, Hashable {
    case pause
    case resume
    case finish
}

struct PulsarRunSessionCommand: Codable, Equatable {
    var sessionId: UUID?
    var command: PulsarRunControlCommand
    var commandId: UUID
    var sentAt: Date
    var retryAttempt: Int
}

struct PulsarRunCommandAcknowledgement: Codable, Equatable {
    var commandId: UUID
    var sessionId: UUID?
    var command: PulsarRunControlCommand
    var accepted: Bool
    var phase: PulsarRunPhase
    var message: String?
    var acknowledgedAt: Date
}

enum PulsarRunTransportEnvelope: Codable, Equatable {
    case identity(PulsarRunSessionIdentity)
    case options(PulsarRunOptions)
    case metrics(PulsarRunMetricSnapshot)
    case routeDelta(PulsarRunRouteDelta)
    case command(PulsarRunControlCommand)
    case sessionCommand(PulsarRunSessionCommand)
    case commandAcknowledgement(PulsarRunCommandAcknowledgement)
    case summary(PulsarRunSummary)

    private enum CodingKeys: String, CodingKey {
        case kind
        case identity
        case options
        case metrics
        case routeDelta
        case command
        case sessionCommand
        case commandAcknowledgement
        case summary
    }

    private enum Kind: String, Codable {
        case identity
        case options
        case metrics
        case routeDelta
        case command
        case sessionCommand
        case commandAcknowledgement
        case summary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .identity:
            self = .identity(try container.decode(PulsarRunSessionIdentity.self, forKey: .identity))
        case .options:
            self = .options(try container.decode(PulsarRunOptions.self, forKey: .options))
        case .metrics:
            self = .metrics(try container.decode(PulsarRunMetricSnapshot.self, forKey: .metrics))
        case .routeDelta:
            self = .routeDelta(try container.decode(PulsarRunRouteDelta.self, forKey: .routeDelta))
        case .command:
            self = .command(try container.decode(PulsarRunControlCommand.self, forKey: .command))
        case .sessionCommand:
            self = .sessionCommand(try container.decode(PulsarRunSessionCommand.self, forKey: .sessionCommand))
        case .commandAcknowledgement:
            self = .commandAcknowledgement(try container.decode(PulsarRunCommandAcknowledgement.self, forKey: .commandAcknowledgement))
        case .summary:
            self = .summary(try container.decode(PulsarRunSummary.self, forKey: .summary))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .identity(let identity):
            try container.encode(Kind.identity, forKey: .kind)
            try container.encode(identity, forKey: .identity)
        case .options(let options):
            try container.encode(Kind.options, forKey: .kind)
            try container.encode(options, forKey: .options)
        case .metrics(let metrics):
            try container.encode(Kind.metrics, forKey: .kind)
            try container.encode(metrics, forKey: .metrics)
        case .routeDelta(let routeDelta):
            try container.encode(Kind.routeDelta, forKey: .kind)
            try container.encode(routeDelta, forKey: .routeDelta)
        case .command(let command):
            try container.encode(Kind.command, forKey: .kind)
            try container.encode(command, forKey: .command)
        case .sessionCommand(let command):
            try container.encode(Kind.sessionCommand, forKey: .kind)
            try container.encode(command, forKey: .sessionCommand)
        case .commandAcknowledgement(let acknowledgement):
            try container.encode(Kind.commandAcknowledgement, forKey: .kind)
            try container.encode(acknowledgement, forKey: .commandAcknowledgement)
        case .summary(let summary):
            try container.encode(Kind.summary, forKey: .kind)
            try container.encode(summary, forKey: .summary)
        }
    }
}

enum PulsarRunTransportCodec {
    static func encode(_ envelope: PulsarRunTransportEnvelope) -> Data? {
        try? JSONEncoder.pulsarRun.encode(envelope)
    }

    static func decode(_ data: Data) -> PulsarRunTransportEnvelope? {
        try? JSONDecoder.pulsarRun.decode(PulsarRunTransportEnvelope.self, from: data)
    }
}

nonisolated enum PulsarRunFormatters {
    static func distance(_ meters: Double) -> String {
        let kilometers = max(0, meters) / 1_000
        if kilometers < 10 {
            return String(format: "%.2f km", kilometers)
        }
        return String(format: "%.1f km", kilometers)
    }

    static func compactDistance(_ meters: Double) -> String {
        String(format: "%.2f", max(0, meters) / 1_000)
    }

    static func duration(_ interval: TimeInterval) -> String {
        let value = max(0, Int(interval.rounded()))
        let hours = value / 3_600
        let minutes = (value % 3_600) / 60
        let seconds = value % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func pace(_ secondsPerKilometer: Double?) -> String {
        guard let secondsPerKilometer, secondsPerKilometer.isFinite, secondsPerKilometer > 0 else {
            return "--"
        }
        let minutes = Int(secondsPerKilometer) / 60
        let seconds = Int(secondsPerKilometer.rounded()) % 60
        return String(format: "%d:%02d /km", minutes, seconds)
    }

    static func speed(_ metersPerSecond: Double?) -> String {
        guard let metersPerSecond, metersPerSecond.isFinite, metersPerSecond > 0 else {
            return "--"
        }
        return String(format: "%.1f km/h", metersPerSecond * 3.6)
    }

    static func paceOrSpeed(
        workoutKind: PulsarOutdoorWorkoutKind,
        paceSecondsPerKilometer: Double?,
        speedMetersPerSecond: Double?
    ) -> String {
        if workoutKind == .cycling {
            let derivedSpeed = paceSecondsPerKilometer.flatMap { pace -> Double? in
                guard pace.isFinite, pace > 0 else { return nil }
                return 1_000 / pace
            }
            return speed(speedMetersPerSecond ?? derivedSpeed)
        }
        return pace(paceSecondsPerKilometer)
    }

    static func paceOrSpeedTitle(for workoutKind: PulsarOutdoorWorkoutKind, average: Bool = false) -> String {
        if workoutKind == .cycling {
            return average ? "Avg Speed" : "Speed"
        }
        return average ? "Avg Pace" : "Pace"
    }

    static func heartRate(_ bpm: Double?) -> String {
        guard let bpm, bpm > 0 else { return "--" }
        return "\(Int(bpm.rounded()))"
    }

    static func calories(_ kilocalories: Double?) -> String {
        guard let kilocalories, kilocalories > 0 else { return "--" }
        return "\(Int(kilocalories.rounded()))"
    }

    static func elevation(_ meters: Double?) -> String {
        guard let meters else { return "--" }
        return "\(Int(meters.rounded())) m"
    }

    static func cadence(_ stepsPerMinute: Double?) -> String {
        guard let stepsPerMinute, stepsPerMinute > 0 else { return "--" }
        return "\(Int(stepsPerMinute.rounded())) spm"
    }
}

nonisolated struct PulsarRunDerivedMetrics {
    enum LocationRejectionReason: String {
        case beforeWorkoutStart
        case cachedSample
        case futureSample
        case invalidHorizontalAccuracy
        case poorHorizontalAccuracy
    }

    static func averagePace(distanceMeters: Double, movingTime: TimeInterval) -> Double? {
        guard distanceMeters >= 10, movingTime > 0 else { return nil }
        return movingTime / (distanceMeters / 1_000)
    }

    static func splitIndex(distanceMeters: Double) -> Int {
        max(1, Int(distanceMeters / 1_000) + 1)
    }

    static func shouldAutoPause(
        speedMetersPerSecond: Double?,
        horizontalAccuracy: Double?,
        workoutKind: PulsarOutdoorWorkoutKind = .running
    ) -> Bool {
        guard let speedMetersPerSecond else { return false }
        if let horizontalAccuracy, horizontalAccuracy > 35 { return false }
        return speedMetersPerSecond >= 0 && speedMetersPerSecond < autoPauseSpeedThresholdMetersPerSecond(for: workoutKind)
    }

    static func autoPauseSpeedThresholdMetersPerSecond(for workoutKind: PulsarOutdoorWorkoutKind) -> Double {
        switch workoutKind {
        case .walking:
            0.35
        case .hiking:
            0.30
        case .cycling:
            1.2
        case .running:
            0.55
        default:
            0.55
        }
    }

    static func isUsableLocationSample(
        timestamp: Date,
        startDate: Date,
        receivedAt: Date = Date(),
        horizontalAccuracy: Double?
    ) -> Bool {
        guard let horizontalAccuracy,
              horizontalAccuracy >= 0,
              horizontalAccuracy <= 35 else {
            return false
        }
        guard timestamp >= startDate else { return false }
        guard timestamp <= receivedAt.addingTimeInterval(3) else { return false }
        return receivedAt.timeIntervalSince(timestamp) <= 45
    }

    static func watchLocationSampleRejectionReason(
        timestamp: Date,
        startDate: Date,
        receivedAt: Date = Date(),
        horizontalAccuracy: Double?,
        workoutKind: PulsarOutdoorWorkoutKind
    ) -> LocationRejectionReason? {
        guard timestamp >= startDate else { return .beforeWorkoutStart }
        guard receivedAt.timeIntervalSince(timestamp) <= 3 else { return .cachedSample }
        guard timestamp <= receivedAt.addingTimeInterval(3) else { return .futureSample }
        guard let horizontalAccuracy, horizontalAccuracy > 0 else {
            return .invalidHorizontalAccuracy
        }
        guard horizontalAccuracy <= maximumWatchHorizontalAccuracyMeters(for: workoutKind) else {
            return .poorHorizontalAccuracy
        }
        return nil
    }

    static func maximumWatchHorizontalAccuracyMeters(for workoutKind: PulsarOutdoorWorkoutKind) -> Double {
        switch workoutKind {
        case .running, .walking:
            20
        case .hiking:
            35
        default:
            35
        }
    }

    static func shouldDeferHikingDistanceUntilAccuracyStabilizes(
        horizontalAccuracy: Double,
        workoutKind: PulsarOutdoorWorkoutKind
    ) -> Bool {
        workoutKind == .hiking && horizontalAccuracy > 20
    }

    static func maximumPlausibleSpeedMetersPerSecond(for workoutKind: PulsarOutdoorWorkoutKind) -> Double {
        switch workoutKind {
        case .running:
            8.0
        case .walking:
            3.0
        case .hiking:
            4.0
        case .cycling:
            18.0
        default:
            8.0
        }
    }

    static func isPlausibleLocationDelta(
        distanceMeters: Double,
        elapsedSeconds: TimeInterval,
        workoutKind: PulsarOutdoorWorkoutKind
    ) -> Bool {
        guard distanceMeters.isFinite,
              elapsedSeconds.isFinite,
              distanceMeters >= 0,
              elapsedSeconds > 0 else {
            return false
        }
        let maxSpeed = maximumPlausibleSpeedMetersPerSecond(for: workoutKind)
        return distanceMeters / elapsedSeconds <= maxSpeed
    }

    static func minimumMovingSpeedMetersPerSecond(for workoutKind: PulsarOutdoorWorkoutKind) -> Double {
        switch workoutKind {
        case .hiking:
            0.4
        case .walking:
            0.35
        case .running:
            0.5
        case .cycling:
            1.5
        default:
            0.4
        }
    }

    static func gpsJitterDistanceThreshold(previousAccuracy: Double?, currentAccuracy: Double?) -> Double {
        max(8, previousAccuracy ?? 0, currentAccuracy ?? 0)
    }

    static func elevationGain(previousAltitude: Double?, nextAltitude: Double, verticalAccuracy: Double?) -> Double {
        elevationChange(
            previousAltitude: previousAltitude,
            nextAltitude: nextAltitude,
            verticalAccuracy: verticalAccuracy
        ).gain
    }

    static func elevationChange(
        previousAltitude: Double?,
        nextAltitude: Double,
        verticalAccuracy: Double?
    ) -> (gain: Double, loss: Double) {
        guard let previousAltitude else { return (0, 0) }
        if let verticalAccuracy, verticalAccuracy > 18 { return (0, 0) }
        let delta = nextAltitude - previousAltitude
        if delta >= 1.5 {
            return (delta, 0)
        }
        if delta <= -1.5 {
            return (0, abs(delta))
        }
        return (0, 0)
    }
}

struct PulsarRunGPSDistanceFilter {
    struct Decision {
        var timestamp: Date
        var horizontalAccuracy: Double?
        var rawDistanceDelta: Double
        var acceptedDistanceDelta: Double
        var totalAcceptedDistance: Double
        var movingTimeDelta: TimeInterval
        var totalMovingTime: TimeInterval
        var speedMetersPerSecond: Double?
        var stationaryLock: Bool
        var movementConfidence: Int
        var rejectedReason: String?
        var routeLocationsToAppend: [CLLocation]
    }

    private(set) var totalAcceptedDistanceMeters: Double = 0
    private(set) var totalMovingTime: TimeInterval = 0
    private(set) var stationaryLockActive = true
    private(set) var movementConfidence = 0

    private var stationaryBaselineLocation: CLLocation?
    private var lastRawLocation: CLLocation?
    private var movementStartLocation: CLLocation?
    private var movementStartDate: Date?
    private var movementBearingDegrees: Double?
    private var lastAcceptedDistanceLocation: CLLocation?
    private var lastAcceptedRouteLocation: CLLocation?
    private var pendingMovingTime: TimeInterval = 0

    private static let gpsWarmupDuration: TimeInterval = 10
    private static let stationaryUnlockDistanceMeters: Double = 14
    private static let requiredMovementConfidenceSamples = 3
    private static let routeSimplificationDistanceMeters: Double = 6
    private static let directionReversalDegrees: Double = 110
    private static let movementDirectionToleranceDegrees: Double = 70

    mutating func reset() {
        totalAcceptedDistanceMeters = 0
        totalMovingTime = 0
        stationaryLockActive = true
        movementConfidence = 0
        stationaryBaselineLocation = nil
        lastRawLocation = nil
        movementStartLocation = nil
        movementStartDate = nil
        movementBearingDegrees = nil
        lastAcceptedDistanceLocation = nil
        lastAcceptedRouteLocation = nil
        pendingMovingTime = 0
    }

    mutating func resetBaselineKeepingTotals() {
        stationaryLockActive = true
        movementConfidence = 0
        stationaryBaselineLocation = nil
        lastRawLocation = nil
        movementStartLocation = nil
        movementStartDate = nil
        movementBearingDegrees = nil
        lastAcceptedDistanceLocation = nil
        pendingMovingTime = 0
    }

    mutating func process(
        location: CLLocation,
        startDate: Date,
        receivedAt: Date,
        workoutKind: PulsarOutdoorWorkoutKind,
        isRunning: Bool
    ) -> Decision {
        let rawDistanceDelta = lastRawLocation.map { location.distance(from: $0) } ?? 0
        let rawElapsedSeconds = lastRawLocation.map { location.timestamp.timeIntervalSince($0.timestamp) } ?? 0
        let effectiveSpeed = Self.effectiveSpeed(
            reportedSpeed: location.speed,
            distanceMeters: rawDistanceDelta,
            elapsedSeconds: rawElapsedSeconds
        )

        if let rejectionReason = sampleRejectionReason(
            location: location,
            startDate: startDate,
            receivedAt: receivedAt,
            workoutKind: workoutKind
        ) {
            resetMovementCandidate()
            return makeDecision(
                location: location,
                rawDistanceDelta: rawDistanceDelta,
                acceptedDistanceDelta: 0,
                movingTimeDelta: 0,
                speed: effectiveSpeed,
                rejectedReason: rejectionReason,
                routeLocationsToAppend: []
            )
        }

        guard isRunning else {
            resetBaselineKeepingTotals()
            return makeDecision(
                location: location,
                rawDistanceDelta: 0,
                acceptedDistanceDelta: 0,
                movingTimeDelta: 0,
                speed: effectiveSpeed,
                rejectedReason: "notRunning",
                routeLocationsToAppend: []
            )
        }

        if location.timestamp.timeIntervalSince(startDate) < Self.gpsWarmupDuration {
            resetMovementCandidate()
            lastRawLocation = nil
            stationaryBaselineLocation = nil
            return makeDecision(
                location: location,
                rawDistanceDelta: 0,
                acceptedDistanceDelta: 0,
                movingTimeDelta: 0,
                speed: location.speed >= 0 ? location.speed : nil,
                rejectedReason: "gpsWarmup",
                routeLocationsToAppend: []
            )
        }

        if let lastRawLocation, location.timestamp <= lastRawLocation.timestamp {
            return makeDecision(
                location: location,
                rawDistanceDelta: 0,
                acceptedDistanceDelta: 0,
                movingTimeDelta: 0,
                speed: effectiveSpeed,
                rejectedReason: "outOfOrder",
                routeLocationsToAppend: []
            )
        }

        if stationaryBaselineLocation == nil {
            stationaryBaselineLocation = location
            lastRawLocation = location
            resetMovementCandidate()
            return makeDecision(
                location: location,
                rawDistanceDelta: 0,
                acceptedDistanceDelta: 0,
                movingTimeDelta: 0,
                speed: location.speed >= 0 ? location.speed : nil,
                rejectedReason: "stationaryLock",
                routeLocationsToAppend: []
            )
        }

        if stationaryLockActive {
            return processStationaryLockedLocation(
                location,
                rawDistanceDelta: rawDistanceDelta,
                rawElapsedSeconds: rawElapsedSeconds,
                speed: effectiveSpeed,
                workoutKind: workoutKind
            )
        }

        return processUnlockedLocation(
            location,
            rawDistanceDelta: rawDistanceDelta,
            rawElapsedSeconds: rawElapsedSeconds,
            speed: effectiveSpeed,
            workoutKind: workoutKind
        )
    }

    private mutating func processStationaryLockedLocation(
        _ location: CLLocation,
        rawDistanceDelta: Double,
        rawElapsedSeconds: TimeInterval,
        speed: Double?,
        workoutKind: PulsarOutdoorWorkoutKind
    ) -> Decision {
        guard let baseline = stationaryBaselineLocation else {
            stationaryBaselineLocation = location
            lastRawLocation = location
            return makeDecision(
                location: location,
                rawDistanceDelta: 0,
                acceptedDistanceDelta: 0,
                movingTimeDelta: 0,
                speed: speed,
                rejectedReason: "stationaryLock",
                routeLocationsToAppend: []
            )
        }

        let distanceFromBaseline = location.distance(from: baseline)
        let unlockDistance = max(
            Self.stationaryUnlockDistanceMeters,
            Self.validAccuracy(baseline.horizontalAccuracy) ?? 0,
            Self.validAccuracy(location.horizontalAccuracy) ?? 0
        )

        guard let speed, speed > PulsarRunDerivedMetrics.minimumMovingSpeedMetersPerSecond(for: workoutKind) else {
            resetMovementCandidate()
            lastRawLocation = location
            return makeDecision(
                location: location,
                rawDistanceDelta: rawDistanceDelta,
                acceptedDistanceDelta: 0,
                movingTimeDelta: 0,
                speed: speed,
                rejectedReason: "tooSlow",
                routeLocationsToAppend: []
            )
        }

        guard PulsarRunDerivedMetrics.isPlausibleLocationDelta(
            distanceMeters: rawDistanceDelta,
            elapsedSeconds: rawElapsedSeconds,
            workoutKind: workoutKind
        ) else {
            resetMovementCandidate()
            lastRawLocation = location
            return makeDecision(
                location: location,
                rawDistanceDelta: rawDistanceDelta,
                acceptedDistanceDelta: 0,
                movingTimeDelta: 0,
                speed: speed,
                rejectedReason: "impossibleSpeed",
                routeLocationsToAppend: []
            )
        }

        guard distanceFromBaseline >= unlockDistance else {
            let reason = detectsDirectionReversal(from: baseline, to: location) ? "directionReversal" : "gpsJitter"
            resetMovementCandidate()
            lastRawLocation = location
            return makeDecision(
                location: location,
                rawDistanceDelta: rawDistanceDelta,
                acceptedDistanceDelta: 0,
                movingTimeDelta: 0,
                speed: speed,
                rejectedReason: reason,
                routeLocationsToAppend: []
            )
        }

        let bearing = Self.bearingDegrees(from: baseline, to: location)
        if let movementBearingDegrees,
           Self.directionDifferenceDegrees(movementBearingDegrees, bearing) > Self.movementDirectionToleranceDegrees {
            movementConfidence = 1
            movementStartLocation = location
            movementStartDate = location.timestamp
            self.movementBearingDegrees = bearing
            lastRawLocation = location
            return makeDecision(
                location: location,
                rawDistanceDelta: rawDistanceDelta,
                acceptedDistanceDelta: 0,
                movingTimeDelta: 0,
                speed: speed,
                rejectedReason: "directionReversal",
                routeLocationsToAppend: []
            )
        }

        if movementStartLocation == nil {
            movementStartLocation = location
            movementStartDate = location.timestamp
        }
        movementBearingDegrees = bearing
        movementConfidence += 1
        lastRawLocation = location

        guard movementConfidence >= Self.requiredMovementConfidenceSamples else {
            return makeDecision(
                location: location,
                rawDistanceDelta: rawDistanceDelta,
                acceptedDistanceDelta: 0,
                movingTimeDelta: 0,
                speed: speed,
                rejectedReason: "stationaryLock",
                routeLocationsToAppend: []
            )
        }

        stationaryLockActive = false
        let movementStart = movementStartLocation ?? location
        lastAcceptedDistanceLocation = movementStart
        let pendingDistance = location.distance(from: movementStart)
        let threshold = PulsarRunDerivedMetrics.gpsJitterDistanceThreshold(
            previousAccuracy: Self.validAccuracy(movementStart.horizontalAccuracy),
            currentAccuracy: Self.validAccuracy(location.horizontalAccuracy)
        )

        guard pendingDistance >= threshold else {
            pendingMovingTime = max(0, location.timestamp.timeIntervalSince(movementStart.timestamp))
            return makeDecision(
                location: location,
                rawDistanceDelta: rawDistanceDelta,
                acceptedDistanceDelta: 0,
                movingTimeDelta: 0,
                speed: speed,
                rejectedReason: "belowThreshold",
                routeLocationsToAppend: []
            )
        }

        let movingTimeDelta = max(0, location.timestamp.timeIntervalSince(movementStart.timestamp))
        return accept(
            distance: pendingDistance,
            movingTimeDelta: movingTimeDelta,
            location: location,
            priorRouteLocation: movementStart,
            rawDistanceDelta: rawDistanceDelta,
            speed: speed
        )
    }

    private mutating func processUnlockedLocation(
        _ location: CLLocation,
        rawDistanceDelta: Double,
        rawElapsedSeconds: TimeInterval,
        speed: Double?,
        workoutKind: PulsarOutdoorWorkoutKind
    ) -> Decision {
        guard let previousDistanceLocation = lastAcceptedDistanceLocation else {
            lastAcceptedDistanceLocation = location
            lastRawLocation = location
            return makeDecision(
                location: location,
                rawDistanceDelta: 0,
                acceptedDistanceDelta: 0,
                movingTimeDelta: 0,
                speed: speed,
                rejectedReason: "baselineAfterMovement",
                routeLocationsToAppend: []
            )
        }

        let candidateDistance = location.distance(from: previousDistanceLocation)
        let threshold = PulsarRunDerivedMetrics.gpsJitterDistanceThreshold(
            previousAccuracy: Self.validAccuracy(previousDistanceLocation.horizontalAccuracy),
            currentAccuracy: Self.validAccuracy(location.horizontalAccuracy)
        )

        guard let speed, speed > PulsarRunDerivedMetrics.minimumMovingSpeedMetersPerSecond(for: workoutKind) else {
            pendingMovingTime = 0
            lastRawLocation = location
            return makeDecision(
                location: location,
                rawDistanceDelta: rawDistanceDelta,
                acceptedDistanceDelta: 0,
                movingTimeDelta: 0,
                speed: speed,
                rejectedReason: "tooSlow",
                routeLocationsToAppend: []
            )
        }

        guard PulsarRunDerivedMetrics.isPlausibleLocationDelta(
            distanceMeters: rawDistanceDelta,
            elapsedSeconds: rawElapsedSeconds,
            workoutKind: workoutKind
        ) else {
            pendingMovingTime = 0
            lastRawLocation = location
            return makeDecision(
                location: location,
                rawDistanceDelta: rawDistanceDelta,
                acceptedDistanceDelta: 0,
                movingTimeDelta: 0,
                speed: speed,
                rejectedReason: "impossibleSpeed",
                routeLocationsToAppend: []
            )
        }

        if detectsDirectionReversal(from: previousDistanceLocation, to: location),
           candidateDistance < max(Self.stationaryUnlockDistanceMeters, threshold) {
            pendingMovingTime = 0
            lastRawLocation = location
            return makeDecision(
                location: location,
                rawDistanceDelta: rawDistanceDelta,
                acceptedDistanceDelta: 0,
                movingTimeDelta: 0,
                speed: speed,
                rejectedReason: "directionReversal",
                routeLocationsToAppend: []
            )
        }

        guard candidateDistance >= threshold else {
            if rawElapsedSeconds > 0 {
                pendingMovingTime += rawElapsedSeconds
            }
            lastRawLocation = location
            return makeDecision(
                location: location,
                rawDistanceDelta: rawDistanceDelta,
                acceptedDistanceDelta: 0,
                movingTimeDelta: 0,
                speed: speed,
                rejectedReason: "belowThreshold",
                routeLocationsToAppend: []
            )
        }

        let movingTimeDelta = max(0, rawElapsedSeconds + pendingMovingTime)
        pendingMovingTime = 0
        return accept(
            distance: candidateDistance,
            movingTimeDelta: movingTimeDelta,
            location: location,
            priorRouteLocation: previousDistanceLocation,
            rawDistanceDelta: rawDistanceDelta,
            speed: speed
        )
    }

    private mutating func accept(
        distance: Double,
        movingTimeDelta: TimeInterval,
        location: CLLocation,
        priorRouteLocation: CLLocation,
        rawDistanceDelta: Double,
        speed: Double?
    ) -> Decision {
        totalAcceptedDistanceMeters += distance
        totalMovingTime += movingTimeDelta
        lastAcceptedDistanceLocation = location
        lastRawLocation = location
        movementConfidence = max(movementConfidence, Self.requiredMovementConfidenceSamples)

        var routeLocations: [CLLocation] = []
        if lastAcceptedRouteLocation == nil {
            routeLocations.append(priorRouteLocation)
            lastAcceptedRouteLocation = priorRouteLocation
        }

        if let lastAcceptedRouteLocation {
            let routeDelta = location.distance(from: lastAcceptedRouteLocation)
            if routeDelta >= Self.routeSimplificationDistanceMeters {
                routeLocations.append(location)
                self.lastAcceptedRouteLocation = location
            }
        }

        return makeDecision(
            location: location,
            rawDistanceDelta: rawDistanceDelta,
            acceptedDistanceDelta: distance,
            movingTimeDelta: movingTimeDelta,
            speed: speed,
            rejectedReason: nil,
            routeLocationsToAppend: routeLocations
        )
    }

    private mutating func resetMovementCandidate() {
        movementConfidence = 0
        movementStartLocation = nil
        movementStartDate = nil
        movementBearingDegrees = nil
        pendingMovingTime = 0
    }

    private func detectsDirectionReversal(from start: CLLocation, to end: CLLocation) -> Bool {
        guard let movementBearingDegrees else { return false }
        let nextBearing = Self.bearingDegrees(from: start, to: end)
        return Self.directionDifferenceDegrees(movementBearingDegrees, nextBearing) > Self.directionReversalDegrees
    }

    private func sampleRejectionReason(
        location: CLLocation,
        startDate: Date,
        receivedAt: Date,
        workoutKind: PulsarOutdoorWorkoutKind
    ) -> String? {
        guard location.timestamp >= startDate else { return "staleSample" }
        guard receivedAt.timeIntervalSince(location.timestamp) <= 3 else { return "staleSample" }
        guard location.timestamp <= receivedAt.addingTimeInterval(3) else { return "staleSample" }
        guard let horizontalAccuracy = Self.validAccuracy(location.horizontalAccuracy) else {
            return "poorAccuracy"
        }
        guard horizontalAccuracy <= PulsarRunDerivedMetrics.maximumWatchHorizontalAccuracyMeters(for: workoutKind) else {
            return "poorAccuracy"
        }
        return nil
    }

    private func makeDecision(
        location: CLLocation,
        rawDistanceDelta: Double,
        acceptedDistanceDelta: Double,
        movingTimeDelta: TimeInterval,
        speed: Double?,
        rejectedReason: String?,
        routeLocationsToAppend: [CLLocation]
    ) -> Decision {
        Decision(
            timestamp: location.timestamp,
            horizontalAccuracy: Self.validAccuracy(location.horizontalAccuracy),
            rawDistanceDelta: rawDistanceDelta.isFinite ? rawDistanceDelta : 0,
            acceptedDistanceDelta: acceptedDistanceDelta,
            totalAcceptedDistance: totalAcceptedDistanceMeters,
            movingTimeDelta: movingTimeDelta,
            totalMovingTime: totalMovingTime,
            speedMetersPerSecond: speed,
            stationaryLock: stationaryLockActive,
            movementConfidence: movementConfidence,
            rejectedReason: rejectedReason,
            routeLocationsToAppend: routeLocationsToAppend
        )
    }

    private static func effectiveSpeed(
        reportedSpeed: Double,
        distanceMeters: Double,
        elapsedSeconds: TimeInterval
    ) -> Double? {
        let reported = reportedSpeed.isFinite && reportedSpeed >= 0 ? reportedSpeed : nil
        let derived: Double?
        if distanceMeters.isFinite,
           elapsedSeconds.isFinite,
           elapsedSeconds > 0 {
            derived = distanceMeters / elapsedSeconds
        } else {
            derived = nil
        }

        switch (reported, derived) {
        case let (reported?, derived?):
            return max(reported, derived)
        case let (reported?, nil):
            return reported
        case let (nil, derived?):
            return derived
        case (nil, nil):
            return nil
        }
    }

    private static func validAccuracy(_ value: Double) -> Double? {
        value.isFinite && value > 0 ? value : nil
    }

    private static func bearingDegrees(from start: CLLocation, to end: CLLocation) -> Double {
        let startLatitude = start.coordinate.latitude * .pi / 180
        let startLongitude = start.coordinate.longitude * .pi / 180
        let endLatitude = end.coordinate.latitude * .pi / 180
        let endLongitude = end.coordinate.longitude * .pi / 180
        let longitudeDelta = endLongitude - startLongitude
        let y = sin(longitudeDelta) * cos(endLatitude)
        let x = cos(startLatitude) * sin(endLatitude) - sin(startLatitude) * cos(endLatitude) * cos(longitudeDelta)
        let bearing = atan2(y, x) * 180 / .pi
        return bearing >= 0 ? bearing : bearing + 360
    }

    private static func directionDifferenceDegrees(_ first: Double, _ second: Double) -> Double {
        let difference = abs(first - second).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }
}

private extension JSONEncoder {
    static var pulsarRun: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSince1970)
        }
        return encoder
    }
}

private extension JSONDecoder {
    static var pulsarRun: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: seconds)
            }
            let string = try container.decode(String.self)
            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractionalFormatter.date(from: string) {
                return date
            }
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid Pulsar run transport date")
        }
        return decoder
    }
}
