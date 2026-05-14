//
//  PulsarRunSharedModels.swift
//  Pulsar
//

import Foundation
import HealthKit

enum PulsarWorkoutStartedFrom: String, Codable, Hashable {
    case iPhone
    case appleWatch = "AppleWatch"

    var displayName: String {
        switch self {
        case .iPhone: "iPhone"
        case .appleWatch: "Apple Watch"
        }
    }
}

enum PulsarWorkoutMetadata {
    static let brandName = "Pulsar"
    static let sessionIdKey = "pulsarWorkoutSessionId"
    static let workoutTypeKey = "pulsarWorkoutType"
    static let startedFromKey = "pulsarStartedFrom"
    static let legacySessionIdKey = "PulsarSessionID"

    static func base(
        sessionId: UUID,
        workoutType: String,
        startedFrom: PulsarWorkoutStartedFrom
    ) -> [String: Any] {
        [
            HKMetadataKeyWorkoutBrandName: brandName,
            sessionIdKey: sessionId.uuidString,
            workoutTypeKey: workoutType,
            startedFromKey: startedFrom.rawValue
        ]
    }

    static func sessionId(from metadata: [String: Any]?) -> UUID? {
        guard let metadata else { return nil }
        let rawValue = metadata[sessionIdKey] as? String ?? metadata[legacySessionIdKey] as? String
        return rawValue.flatMap(UUID.init(uuidString:))
    }

    static func workoutType(from metadata: [String: Any]?) -> String? {
        (metadata?[workoutTypeKey] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func startedFrom(from metadata: [String: Any]?) -> PulsarWorkoutStartedFrom? {
        guard let rawValue = (metadata?[startedFromKey] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return PulsarWorkoutStartedFrom(rawValue: rawValue)
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

    var id: String { rawValue }

    var displayName: String {
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

    var shortName: String {
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

    var actionName: String {
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

    var outdoorTitle: String {
        isOutdoorDistanceWorkout ? "Outdoor \(shortName)" : displayName
    }

    var startTitle: String {
        "Start \(shortName)"
    }

    var savedTitle: String {
        "\(shortName) Saved"
    }

    var systemImageName: String {
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

    var healthKitActivityType: HKWorkoutActivityType {
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
        case .dance: .dance
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

    var defaultLocationType: HKWorkoutSessionLocationType {
        switch self {
        case .running, .walking, .hiking, .cycling:
            .outdoor
        case .swimming:
            .unknown
        case .hiit, .strength, .yoga, .pilates, .rowing, .dance, .boxing, .stretching, .core, .mobility, .elliptical, .stairClimber, .cooldown, .other:
            .indoor
        }
    }

    var isOutdoorDistanceWorkout: Bool {
        switch self {
        case .running, .walking, .hiking, .cycling:
            true
        case .hiit, .strength, .yoga, .pilates, .swimming, .rowing, .dance, .boxing, .stretching, .core, .mobility, .elliptical, .stairClimber, .cooldown, .other:
            false
        }
    }

    init(activityType: HKWorkoutActivityType) {
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
        case .dance, .socialDance:
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

    init(metadata: [String: Any]?, fallbackActivityType: HKWorkoutActivityType) {
        if let rawType = PulsarWorkoutMetadata.workoutType(from: metadata),
           let workoutKind = PulsarOutdoorWorkoutKind(rawValue: rawType) {
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

    var isLive: Bool {
        switch self {
        case .starting, .active, .paused, .resumed, .ending:
            true
        case .ended, .failed:
            false
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

    var displayName: String {
        switch self {
        case .outdoor(let kind):
            kind.displayName
        case .gym(let kind):
            kind.displayName
        }
    }

    var workoutTypeRawValue: String {
        switch self {
        case .outdoor(let kind):
            kind.rawValue
        case .gym(let kind):
            kind.rawValue
        }
    }

    var outdoorWorkoutKind: PulsarOutdoorWorkoutKind? {
        if case .outdoor(let kind) = self { return kind }
        return nil
    }

    var gymWorkoutKind: PulsarGymWorkoutKind? {
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
    var id: UUID { sessionId }

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

    var isEnded: Bool {
        phase == .ended || phase == .failed
    }

    init(
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
        updatedAt: Date = Date()
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
    }
}

extension PulsarActiveWorkoutSyncState {
    init(runSnapshot snapshot: PulsarRunMetricSnapshot, startedFrom: PulsarWorkoutStartedFrom, lastUpdatedFrom: PulsarWorkoutStartedFrom) {
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
            healthKitWorkoutUUID: nil
        )
    }

    init(gymState state: ActiveGymWorkoutState, lastUpdatedFrom: PulsarWorkoutStartedFrom? = nil) {
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
    init(runPhase: PulsarRunPhase) {
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

    var runPhase: PulsarRunPhase {
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
        }
    }
}

enum PulsarRunRecordingSource: String, Codable, Hashable {
    case appleWatch
    case iPhone

    var label: String {
        switch self {
        case .appleWatch: "Apple Watch"
        case .iPhone: "iPhone"
        }
    }
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

    static let `default` = PulsarRunOptions(
        prefersWatchRecorder: true,
        autoPauseEnabled: true,
        audioCuesEnabled: false
    )
}

struct PulsarRunCoordinate: Codable, Hashable, Identifiable {
    var id: String { "\(timestamp.timeIntervalSince1970)-\(latitude)-\(longitude)" }
    var latitude: Double
    var longitude: Double
    var altitude: Double?
    var horizontalAccuracy: Double?
    var verticalAccuracy: Double?
    var timestamp: Date

    init(
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

    static let empty = PulsarRunMetricSnapshot(
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
        statusMessage: nil
    )
}

struct PulsarRunSplit: Codable, Equatable, Identifiable {
    var id: Int { index }
    var index: Int
    var distanceMeters: Double
    var movingTime: TimeInterval
    var elevationGainMeters: Double
    var averageHeartRate: Double?

    var paceSecondsPerKilometer: Double? {
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
    var distanceMeters: Double
    var elapsedTime: TimeInterval
    var movingTime: TimeInterval
    var activeEnergyKilocalories: Double?
    var elevationGainMeters: Double
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var steps: Int?
    var averageCadenceStepsPerMinute: Double?
    var route: [PulsarRunCoordinate]
    var splits: [PulsarRunSplit]

    var averagePaceSecondsPerKilometer: Double? {
        guard distanceMeters > 0 else { return nil }
        return movingTime / (distanceMeters / 1_000)
    }

    init(
        id: UUID,
        pulsarWorkoutSessionId: UUID? = nil,
        workoutUUID: UUID?,
        workoutKind: PulsarOutdoorWorkoutKind = .other,
        startedAt: Date,
        endedAt: Date,
        source: PulsarRunRecordingSource,
        distanceMeters: Double,
        elapsedTime: TimeInterval,
        movingTime: TimeInterval,
        activeEnergyKilocalories: Double?,
        elevationGainMeters: Double,
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
        self.distanceMeters = distanceMeters
        self.elapsedTime = elapsedTime
        self.movingTime = movingTime
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.elevationGainMeters = elevationGainMeters
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
        case distanceMeters
        case elapsedTime
        case movingTime
        case activeEnergyKilocalories
        case elevationGainMeters
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
        distanceMeters = try container.decode(Double.self, forKey: .distanceMeters)
        elapsedTime = try container.decode(TimeInterval.self, forKey: .elapsedTime)
        movingTime = try container.decode(TimeInterval.self, forKey: .movingTime)
        activeEnergyKilocalories = try container.decodeIfPresent(Double.self, forKey: .activeEnergyKilocalories)
        elevationGainMeters = try container.decode(Double.self, forKey: .elevationGainMeters)
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

enum PulsarRunControlCommand: String, Codable, Hashable {
    case pause
    case resume
    case finish
}

enum PulsarRunTransportEnvelope: Codable, Equatable {
    case identity(PulsarRunSessionIdentity)
    case options(PulsarRunOptions)
    case metrics(PulsarRunMetricSnapshot)
    case command(PulsarRunControlCommand)
    case summary(PulsarRunSummary)

    private enum CodingKeys: String, CodingKey {
        case kind
        case identity
        case options
        case metrics
        case command
        case summary
    }

    private enum Kind: String, Codable {
        case identity
        case options
        case metrics
        case command
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
        case .command:
            self = .command(try container.decode(PulsarRunControlCommand.self, forKey: .command))
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
        case .command(let command):
            try container.encode(Kind.command, forKey: .kind)
            try container.encode(command, forKey: .command)
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

enum PulsarRunFormatters {
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

struct PulsarRunDerivedMetrics {
    static func averagePace(distanceMeters: Double, movingTime: TimeInterval) -> Double? {
        guard distanceMeters >= 10, movingTime > 0 else { return nil }
        return movingTime / (distanceMeters / 1_000)
    }

    static func splitIndex(distanceMeters: Double) -> Int {
        max(1, Int(distanceMeters / 1_000) + 1)
    }

    static func shouldAutoPause(speedMetersPerSecond: Double?, horizontalAccuracy: Double?) -> Bool {
        guard let speedMetersPerSecond else { return false }
        if let horizontalAccuracy, horizontalAccuracy > 35 { return false }
        return speedMetersPerSecond >= 0 && speedMetersPerSecond < 0.55
    }

    static func elevationGain(previousAltitude: Double?, nextAltitude: Double, verticalAccuracy: Double?) -> Double {
        guard let previousAltitude else { return 0 }
        if let verticalAccuracy, verticalAccuracy > 18 { return 0 }
        let delta = nextAltitude - previousAltitude
        return delta >= 1.5 ? delta : 0
    }
}

private extension JSONEncoder {
    static var pulsarRun: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var pulsarRun: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
