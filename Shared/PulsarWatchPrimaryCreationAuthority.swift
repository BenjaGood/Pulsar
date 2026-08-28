//
//  PulsarWatchPrimaryCreationAuthority.swift
//  Pulsar
//

import Foundation

/// Legal origins of a Watch `HKWorkoutSession`. Synchronized gym/run state is
/// presentation data, not creation authority.
enum PulsarWatchPrimaryCreationSource: String, Sendable, CaseIterable {
    case startWatchAppConfiguration
    case watchUIStart
    case recovery
    case activeGymStateSink
    case activeWorkoutStateSink
    case watchGymViewAppear
    case prelaunchHint
    case routineSnapshotReceived
    case heartbeat
    case restore
    case requestState
    case unknown

    var canCreatePrimarySession: Bool {
        switch self {
        case .startWatchAppConfiguration, .watchUIStart:
            return true
        case .recovery:
            // Recovery reattaches an existing HealthKit session. It must not
            // construct a new `HKWorkoutSession`.
            return false
        case .activeGymStateSink, .activeWorkoutStateSink, .watchGymViewAppear,
             .prelaunchHint, .routineSnapshotReceived, .heartbeat, .restore,
             .requestState, .unknown:
            return false
        }
    }

    var isExplicitWatchLocalStart: Bool {
        self == .watchUIStart
    }

    var requiresCompanionRequestID: Bool {
        false
    }

    var authorityLabel: String {
        switch self {
        case .startWatchAppConfiguration:
            "companionStart"
        case .watchUIStart:
            "watchLocalStart"
        case .recovery:
            "healthKitRecovery"
        default:
            "none"
        }
    }
}

enum PulsarWatchPrimaryCreationDecision: Equatable, Sendable {
    case allow
    case reject(reason: String)
}

enum PulsarWatchPrimaryCreationAuthority {
    static func decision(
        source: PulsarWatchPrimaryCreationSource,
        workoutID: UUID?,
        requestID: UUID?
    ) -> PulsarWatchPrimaryCreationDecision {
        guard source.canCreatePrimarySession else {
            return .reject(reason: "source is not a primary creation authority")
        }
        return .allow
    }

    static func preventCreation(
        source: PulsarWatchPrimaryCreationSource,
        workoutID: UUID?,
        requestID: UUID?,
        reason: String
    ) {
        let message = "[PrimaryCreateRejected] workoutID=\(workoutID?.uuidString ?? "none") requestID=\(requestID?.uuidString ?? "none") source=\(source.rawValue) reason=\(reason) timestamp=\(Date())"
        PulsarWorkoutStartupTrace.watch(message)
        debugAssertUnauthorized(source: source, requestID: requestID)
    }

    static func debugAssertUnauthorized(
        source: PulsarWatchPrimaryCreationSource,
        requestID: UUID?
    ) {
        #if DEBUG
        if source == .activeGymStateSink || source == .activeWorkoutStateSink {
            assertionFailure("activeGymStateSink must never create a Watch HKWorkoutSession")
        }
        if !source.canCreatePrimarySession, source != .recovery {
            assertionFailure("unauthorized Watch primary creation source=\(source.rawValue)")
        }
        #endif
    }
}
