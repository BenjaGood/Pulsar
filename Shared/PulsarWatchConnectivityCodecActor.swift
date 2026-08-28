//
//  PulsarWatchConnectivityCodecActor.swift
//  Pulsar
//

import Foundation

struct ActiveGymSyncCadencePolicy: Sendable {
    static let reachableLiveInterval: TimeInterval = 2
    static let reachableRestInterval: TimeInterval = 5
    static let applicationContextLiveInterval: TimeInterval = 5
    static let queuedLiveInterval: TimeInterval = 15
    static let persistenceDebounceInterval: Duration = .seconds(5)

    static func isVolatile(reason: String, isFinished: Bool) -> Bool {
        guard !isFinished else { return false }
        return reason.localizedCaseInsensitiveContains("tick") ||
            reason.localizedCaseInsensitiveContains("metrics")
    }

    static func reachableInterval(restIsActive: Bool) -> TimeInterval {
        restIsActive ? reachableRestInterval : reachableLiveInterval
    }

    static func shouldSendReachable(
        lastSentAt: Date,
        now: Date,
        restIsActive: Bool
    ) -> Bool {
        now.timeIntervalSince(lastSentAt) >= reachableInterval(restIsActive: restIsActive)
    }
}

/// A Sendable copy of the property-list values accepted at the WCSession boundary.
/// `[String: Any]` never crosses into the codec actor.
struct PulsarWatchConnectivityIncomingSnapshot: Sendable {
    var messageID: String?
    var category: String?
    var sessionID: String?
    var phase: String?
    var messageType: String?

    var heartbeatData: Data?
    var dailyMetricsData: Data?
    var sleepPreferencesData: Data?
    var appleWatchBatteryData: Data?
    var activeWorkoutData: Data?
    var activeGymData: Data?
    var activeGymDeltaData: Data?
    var savedGymRoutinesData: Data?
    var runTransportEnvelopeData: Data?
    var gymStartAcknowledgementData: Data?
    var gymRoutineSnapshotData: Data?
    var activeGymActionData: Data?

    var batteryMessageType: String?
    var batteryPercentage: Int?
    var batteryTimestamp: TimeInterval?

    var prelaunchRequestID: String?
    var prelaunchCandidateSessionID: String?
    var prelaunchIdempotencyKey: String?
    var prelaunchRoutineID: String?
    var prelaunchRoutineRevision: Int?
    var prelaunchWorkoutKind: String?
    var prelaunchRequestedAt: TimeInterval?

    var containsActiveWorkout: Bool
    var containsActiveGym: Bool
    var containsActiveGymDelta: Bool
    var containsSavedGymRoutines: Bool
    var containsRunTransportEnvelope: Bool
    var containsGymAction: Bool

    nonisolated init(dictionary: [String: Any]) {
        messageID = dictionary["pulsar.workoutSync.messageId.v1"] as? String
        category = dictionary["pulsar.workoutSync.category.v1"] as? String
        sessionID = dictionary["pulsar.workoutSync.sessionId.v1"] as? String
        phase = dictionary["pulsar.workoutSync.phase.v1"] as? String
        messageType = dictionary["pulsar.gymCrossDevice.messageType.v1"] as? String

        heartbeatData = dictionary["pulsar.watchHeartbeat.payload.v1"] as? Data
        dailyMetricsData = dictionary["pulsar.dailyMetricsPayload"] as? Data
        sleepPreferencesData = dictionary["pulsar.sleepPreferences.payload.v1"] as? Data
        appleWatchBatteryData = dictionary["pulsar.appleWatchBattery.payload.v1"] as? Data
        activeWorkoutData = dictionary["pulsar.activeWorkout.state.v1"] as? Data
        activeGymData = dictionary["pulsar.activeGymWorkout.state.v1"] as? Data
        activeGymDeltaData = dictionary["pulsar.activeGymWorkout.liveDelta.v2"] as? Data
        savedGymRoutinesData = dictionary["pulsar.savedGymRoutines.payload.v1"] as? Data
        runTransportEnvelopeData = dictionary["pulsar.run.transportEnvelope.v1"] as? Data
        gymStartAcknowledgementData = dictionary["gymWorkoutStartAcknowledgement"] as? Data
        gymRoutineSnapshotData = dictionary["gymRoutineSnapshotEnvelope"] as? Data
        activeGymActionData = dictionary["pulsar.activeGymWorkout.action.v1"] as? Data

        batteryMessageType = dictionary["type"] as? String
        batteryPercentage = dictionary["batteryPercentage"] as? Int
        batteryTimestamp = dictionary["timestamp"] as? TimeInterval

        prelaunchRequestID = dictionary["requestID"] as? String
        prelaunchCandidateSessionID = dictionary["candidateSessionID"] as? String
        prelaunchIdempotencyKey = dictionary["idempotencyKey"] as? String
        prelaunchRoutineID = dictionary["routineID"] as? String
        prelaunchRoutineRevision = dictionary["routineRevision"] as? Int
        prelaunchWorkoutKind = dictionary["workoutKind"] as? String
        prelaunchRequestedAt = dictionary["requestedAt"] as? TimeInterval

        containsActiveWorkout = dictionary["pulsar.activeWorkout.state.v1"] != nil
        containsActiveGym = dictionary["pulsar.activeGymWorkout.state.v1"] != nil
        containsActiveGymDelta = dictionary["pulsar.activeGymWorkout.liveDelta.v2"] != nil
        containsSavedGymRoutines = dictionary["pulsar.savedGymRoutines.payload.v1"] != nil
        containsRunTransportEnvelope = dictionary["pulsar.run.transportEnvelope.v1"] != nil
        containsGymAction = dictionary["pulsar.activeGymWorkout.action.v1"] != nil
    }

    nonisolated func acknowledgement(reason: String) -> [String: Any] {
        var acknowledgement: [String: Any] = [
            "pulsar.workoutSync.ack.accepted.v1": true,
            "pulsar.workoutSync.ack.reason.v1": reason,
            "pulsar.workoutSync.sentAt.v1": Date().timeIntervalSince1970
        ]
        if let messageID {
            acknowledgement["pulsar.workoutSync.ack.messageId.v1"] = messageID
        }
        if let category {
            acknowledgement["pulsar.workoutSync.category.v1"] = category
        }
        if let sessionID {
            acknowledgement["pulsar.workoutSync.sessionId.v1"] = sessionID
        }
        if let phase {
            acknowledgement["pulsar.workoutSync.phase.v1"] = phase
        }
        return acknowledgement
    }
}

/// Codable values are immutable while they cross back to MainActor for application.
struct PulsarWatchConnectivityDecodedPayload: Sendable {
    var snapshot: PulsarWatchConnectivityIncomingSnapshot
    var heartbeat: AppleWatchHeartbeatSnapshot?
    var dailyMetrics: PulsarDailyMetricsSyncPayload?
    var sleepPreferences: PulsarSleepPreferencesSyncPayload?
    var appleWatchBattery: AppleWatchBatterySnapshot?
    var activeWorkout: PulsarActiveWorkoutSyncState?
    var activeGym: ActiveGymWorkoutState?
    var activeGymDelta: ActiveGymLiveStateDelta?
    var savedGymRoutines: SavedGymRoutinesSyncPayload?
    var runTransportEnvelope: PulsarRunTransportEnvelope?
    var gymStartAcknowledgement: GymWorkoutStartAcknowledgement?
    var gymRoutineSnapshot: GymRoutineSnapshotEnvelope?
    var activeGymAction: ActiveGymWorkoutAction?

    var hasWorkoutCriticalPayload: Bool {
        activeWorkout != nil || snapshot.containsActiveWorkout ||
            activeGym != nil || snapshot.containsActiveGym ||
            activeGymDelta != nil || snapshot.containsActiveGymDelta ||
            runTransportEnvelope != nil || snapshot.containsRunTransportEnvelope ||
            gymStartAcknowledgement != nil || gymRoutineSnapshot != nil ||
            activeGymAction != nil || snapshot.containsGymAction ||
            snapshot.messageType != nil
    }

    var hasNonWorkoutPayload: Bool {
        heartbeat != nil || snapshot.heartbeatData != nil ||
            dailyMetrics != nil || snapshot.dailyMetricsData != nil ||
            sleepPreferences != nil || snapshot.sleepPreferencesData != nil ||
            appleWatchBattery != nil || snapshot.appleWatchBatteryData != nil ||
            snapshot.batteryMessageType != nil ||
            savedGymRoutines != nil || snapshot.containsSavedGymRoutines
    }

    func workoutCriticalOnly() -> Self {
        var copy = self
        copy.heartbeat = nil
        copy.dailyMetrics = nil
        copy.sleepPreferences = nil
        copy.appleWatchBattery = nil
        copy.savedGymRoutines = nil
        copy.snapshot.heartbeatData = nil
        copy.snapshot.dailyMetricsData = nil
        copy.snapshot.sleepPreferencesData = nil
        copy.snapshot.appleWatchBatteryData = nil
        copy.snapshot.savedGymRoutinesData = nil
        copy.snapshot.batteryMessageType = nil
        copy.snapshot.batteryPercentage = nil
        copy.snapshot.batteryTimestamp = nil
        copy.snapshot.containsSavedGymRoutines = false
        return copy
    }

    func nonWorkoutOnly() -> Self {
        var copy = self
        copy.activeWorkout = nil
        copy.activeGym = nil
        copy.activeGymDelta = nil
        copy.runTransportEnvelope = nil
        copy.gymStartAcknowledgement = nil
        copy.gymRoutineSnapshot = nil
        copy.activeGymAction = nil
        copy.snapshot.messageID = nil
        copy.snapshot.category = nil
        copy.snapshot.sessionID = nil
        copy.snapshot.phase = nil
        copy.snapshot.messageType = nil
        copy.snapshot.activeWorkoutData = nil
        copy.snapshot.activeGymData = nil
        copy.snapshot.activeGymDeltaData = nil
        copy.snapshot.runTransportEnvelopeData = nil
        copy.snapshot.gymStartAcknowledgementData = nil
        copy.snapshot.gymRoutineSnapshotData = nil
        copy.snapshot.activeGymActionData = nil
        copy.snapshot.prelaunchRequestID = nil
        copy.snapshot.prelaunchCandidateSessionID = nil
        copy.snapshot.prelaunchIdempotencyKey = nil
        copy.snapshot.prelaunchRoutineID = nil
        copy.snapshot.prelaunchRoutineRevision = nil
        copy.snapshot.prelaunchWorkoutKind = nil
        copy.snapshot.prelaunchRequestedAt = nil
        copy.snapshot.containsActiveWorkout = false
        copy.snapshot.containsActiveGym = false
        copy.snapshot.containsActiveGymDelta = false
        copy.snapshot.containsRunTransportEnvelope = false
        copy.snapshot.containsGymAction = false
        return copy
    }

    /// Application context is an OS-retained snapshot, not proof that its
    /// workout recorder still exists. During WCSession activation we hydrate
    /// ordinary cached state and terminal workout events, but quarantine live
    /// workout state until a new delegate delivery or HealthKit recovery
    /// supplies runtime authority.
    func activationHydrationSafeOnly() -> Self {
        var copy = nonWorkoutOnly()
        if activeWorkout?.isEnded == true {
            copy.activeWorkout = activeWorkout
            copy.snapshot.activeWorkoutData = snapshot.activeWorkoutData
            copy.snapshot.containsActiveWorkout = snapshot.containsActiveWorkout
        }
        if activeGym?.isFinished == true {
            copy.activeGym = activeGym
            copy.snapshot.activeGymData = snapshot.activeGymData
            copy.snapshot.containsActiveGym = snapshot.containsActiveGym
        }
        return copy
    }
}

struct PulsarWatchConnectivityApplicationContextSource: Sendable {
    var dailyMetrics: PulsarDailyMetricsSyncPayload?
    var sleepPreferences: PulsarSleepPreferencesSyncPayload?
    var appleWatchBattery: AppleWatchBatterySnapshot?
    var watchHeartbeat: AppleWatchHeartbeatSnapshot?
    var activeWorkout: PulsarActiveWorkoutSyncState?
    var activeGym: ActiveGymWorkoutState?
    var savedGymRoutines: SavedGymRoutinesSyncPayload
}

struct PulsarWatchConnectivityEncodedApplicationContext: Sendable {
    var dailyMetricsData: Data?
    var sleepPreferencesData: Data?
    var appleWatchBatteryData: Data?
    var watchHeartbeatData: Data?
    var activeWorkoutData: Data?
    var activeGymData: Data?
    var savedGymRoutinesData: Data?
}

struct PulsarWatchConnectivityGymTransmissionSource: Sendable {
    var state: ActiveGymWorkoutState
    var activeWorkout: PulsarActiveWorkoutSyncState
    var sendsDelta: Bool
    var applicationContext: PulsarWatchConnectivityApplicationContextSource?
}

struct PulsarWatchConnectivityEncodedGymTransmission: Sendable {
    var activeGymStateData: Data?
    var activeGymDeltaData: Data?
    var activeWorkoutData: Data?
    var applicationContext: PulsarWatchConnectivityEncodedApplicationContext?
}

actor PulsarWatchConnectivityCodecActor {
    static let shared = PulsarWatchConnectivityCodecActor()

    private var cachedSavedGymRoutinesRevision: Int?
    private var cachedSavedGymRoutinesData: Data?

    func decode(_ snapshot: PulsarWatchConnectivityIncomingSnapshot) -> PulsarWatchConnectivityDecodedPayload {
        PulsarPerformanceSignposts.measure(
            PulsarPerformanceSignposts.watchConnectivity,
            name: "decode"
        ) {
            let defaultDecoder = JSONDecoder()
            let isoDecoder = JSONDecoder()
            isoDecoder.dateDecodingStrategy = .iso8601

            let appleWatchBattery: AppleWatchBatterySnapshot?
            if let data = snapshot.appleWatchBatteryData {
                appleWatchBattery = try? defaultDecoder.decode(AppleWatchBatterySnapshot.self, from: data)
            } else if snapshot.batteryMessageType == "appleWatchBattery",
                      let percentage = snapshot.batteryPercentage,
                      let timestamp = snapshot.batteryTimestamp {
                appleWatchBattery = AppleWatchBatterySnapshot(
                    batteryPercentage: percentage,
                    timestamp: Date(timeIntervalSince1970: timestamp)
                )
            } else {
                appleWatchBattery = nil
            }

            let savedGymRoutines: SavedGymRoutinesSyncPayload?
            if let data = snapshot.savedGymRoutinesData {
                if let payload = try? isoDecoder.decode(SavedGymRoutinesSyncPayload.self, from: data) {
                    savedGymRoutines = payload
                } else if let routines = try? isoDecoder.decode([WatchGymRoutinePlan].self, from: data) {
                    savedGymRoutines = SavedGymRoutinesSyncPayload(revision: 0, routines: routines)
                } else if let routines = try? defaultDecoder.decode([WatchGymRoutinePlan].self, from: data) {
                    savedGymRoutines = SavedGymRoutinesSyncPayload(revision: 0, routines: routines)
                } else {
                    savedGymRoutines = nil
                }
            } else {
                savedGymRoutines = nil
            }

            return PulsarWatchConnectivityDecodedPayload(
                snapshot: snapshot,
                heartbeat: snapshot.heartbeatData.flatMap {
                    try? defaultDecoder.decode(AppleWatchHeartbeatSnapshot.self, from: $0)
                },
                dailyMetrics: snapshot.dailyMetricsData.flatMap {
                    try? defaultDecoder.decode(PulsarDailyMetricsSyncPayload.self, from: $0)
                },
                sleepPreferences: snapshot.sleepPreferencesData.flatMap {
                    try? defaultDecoder.decode(PulsarSleepPreferencesSyncPayload.self, from: $0)
                },
                appleWatchBattery: appleWatchBattery,
                activeWorkout: snapshot.activeWorkoutData.flatMap {
                    try? isoDecoder.decode(PulsarActiveWorkoutSyncState.self, from: $0)
                },
                activeGym: snapshot.activeGymData.flatMap {
                    try? isoDecoder.decode(ActiveGymWorkoutState.self, from: $0)
                },
                activeGymDelta: snapshot.activeGymDeltaData.flatMap {
                    try? isoDecoder.decode(ActiveGymLiveStateDelta.self, from: $0)
                },
                savedGymRoutines: savedGymRoutines,
                runTransportEnvelope: snapshot.runTransportEnvelopeData.flatMap {
                    try? Self.runDecoder.decode(PulsarRunTransportEnvelope.self, from: $0)
                },
                gymStartAcknowledgement: snapshot.gymStartAcknowledgementData.flatMap {
                    try? isoDecoder.decode(GymWorkoutStartAcknowledgement.self, from: $0)
                },
                gymRoutineSnapshot: snapshot.gymRoutineSnapshotData.flatMap {
                    try? isoDecoder.decode(GymRoutineSnapshotEnvelope.self, from: $0)
                },
                activeGymAction: snapshot.activeGymActionData.flatMap {
                    try? isoDecoder.decode(ActiveGymWorkoutAction.self, from: $0)
                }
            )
        }
    }

    func encodeApplicationContext(
        _ source: PulsarWatchConnectivityApplicationContextSource
    ) -> PulsarWatchConnectivityEncodedApplicationContext {
        measureEncode {
            encodeApplicationContextWithoutMeasurement(source)
        }
    }

    func encodeGymTransmission(
        _ source: PulsarWatchConnectivityGymTransmissionSource
    ) -> PulsarWatchConnectivityEncodedGymTransmission {
        let startedAt = Date()
        let encoded = measureEncode {
            PulsarWatchConnectivityEncodedGymTransmission(
                activeGymStateData: source.sendsDelta ? nil : try? Self.isoEncoder.encode(source.state),
                activeGymDeltaData: source.sendsDelta ? try? Self.isoEncoder.encode(ActiveGymLiveStateDelta(state: source.state)) : nil,
                activeWorkoutData: try? Self.isoEncoder.encode(source.activeWorkout),
                applicationContext: source.applicationContext.map { encodeApplicationContextWithoutMeasurement($0) }
            )
        }
        let bytes = (encoded.activeGymStateData?.count ?? 0)
            + (encoded.activeGymDeltaData?.count ?? 0)
            + (encoded.activeWorkoutData?.count ?? 0)
            + (encoded.applicationContext?.savedGymRoutinesData?.count ?? 0)
        PulsarWorkoutStartupTrace.recordEncode(
            kind: "gymTransmission.encode",
            bytes: bytes,
            elapsedMs: PulsarWorkoutStartupTrace.elapsedMs(since: startedAt)
        )
        return encoded
    }

    func encodeActiveGymState(_ state: ActiveGymWorkoutState) -> Data? {
        let startedAt = Date()
        let data = measureEncode {
            try? Self.isoEncoder.encode(state)
        }
        if let data {
            PulsarWorkoutStartupTrace.recordEncode(
                kind: "activeGymPersistence.encode",
                bytes: data.count,
                elapsedMs: PulsarWorkoutStartupTrace.elapsedMs(since: startedAt)
            )
        }
        return data
    }

    func encodeActiveGymDelta(_ delta: ActiveGymLiveStateDelta) -> Data? {
        measureEncode {
            try? Self.isoEncoder.encode(delta)
        }
    }

    func encodeActiveWorkoutState(_ state: PulsarActiveWorkoutSyncState) -> Data? {
        measureEncode {
            try? Self.isoEncoder.encode(state)
        }
    }

    func encodeActiveGymAction(_ action: ActiveGymWorkoutAction) -> Data? {
        measureEncode {
            try? Self.isoEncoder.encode(action)
        }
    }

    func encodeRunTransportEnvelope(_ envelope: PulsarRunTransportEnvelope) -> Data? {
        measureEncode {
            try? Self.runEncoder.encode(envelope)
        }
    }

    private func measureEncode<T>(_ work: () -> T) -> T {
        PulsarPerformanceSignposts.measure(
            PulsarPerformanceSignposts.watchConnectivity,
            name: "encode",
            operation: work
        )
    }

    private func encodeApplicationContextWithoutMeasurement(
        _ source: PulsarWatchConnectivityApplicationContextSource
    ) -> PulsarWatchConnectivityEncodedApplicationContext {
        let defaultEncoder = JSONEncoder()
        return PulsarWatchConnectivityEncodedApplicationContext(
            dailyMetricsData: source.dailyMetrics.flatMap { try? defaultEncoder.encode($0) },
            sleepPreferencesData: source.sleepPreferences.flatMap { try? defaultEncoder.encode($0) },
            appleWatchBatteryData: source.appleWatchBattery.flatMap { try? defaultEncoder.encode($0) },
            watchHeartbeatData: source.watchHeartbeat.flatMap { try? defaultEncoder.encode($0) },
            activeWorkoutData: source.activeWorkout.flatMap { try? Self.isoEncoder.encode($0) },
            activeGymData: source.activeGym.flatMap { try? Self.isoEncoder.encode($0) },
            savedGymRoutinesData: encodedSavedGymRoutines(source.savedGymRoutines)
        )
    }

    private func encodedSavedGymRoutines(_ payload: SavedGymRoutinesSyncPayload) -> Data? {
        if payload.revision == cachedSavedGymRoutinesRevision, let cachedSavedGymRoutinesData {
            return cachedSavedGymRoutinesData
        }
        let data = try? Self.isoEncoder.encode(payload)
        cachedSavedGymRoutinesRevision = payload.revision
        cachedSavedGymRoutinesData = data
        return data
    }

    private static var isoEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var runDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: seconds)
            }
            let value = try container.decode(String.self)
            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractionalFormatter.date(from: value) {
                return date
            }
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid Pulsar run transport date"
            )
        }
        return decoder
    }


    private static var runEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSince1970)
        }
        return encoder
    }
}
