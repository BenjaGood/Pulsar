//
//  PulsarWatchSynchronizedGymReconciliation.swift
//  Pulsar
//

import Foundation

enum PulsarSynchronizedGymPlatform: String, Sendable {
    case iPhone
    case watch
}

enum PulsarIncomingGymAuthorityDecision: Equatable, Sendable {
    case adopt
    case rejectAdvisory(reason: String)
    case competingWorkout(reason: String)
}

/// `activeGymState` is synchronized presentation/domain state.
/// It is not authorization to create `HKWorkoutSession`.
enum PulsarWatchSynchronizedGymReconciliation {
    /// Reconciles synchronized Gym metadata against an explicit iPhone start.
    /// WatchConnectivity state is advisory; only the matching canonical
    /// identity (or a separately correlated acknowledgement) may replace the
    /// active transaction identity.
    static func incomingAuthorityDecision(
        incoming: ActiveGymWorkoutState,
        canonicalSessionID: UUID,
        canonicalRequestID: UUID?,
        hasAuthoritativeMirror: Bool
    ) -> PulsarIncomingGymAuthorityDecision {
        if incoming.sessionId == canonicalSessionID {
            return .adopt
        }

        guard let canonicalRequestID else {
            return hasAuthoritativeMirror
                ? .rejectAdvisory(reason: "live HealthKit mirror owns another session")
                : .adopt
        }

        if incoming.startedFrom == .iPhoneRequestedWatchStart,
           incoming.requestID == nil {
            return .rejectAdvisory(reason: "uncorrelated Watch launch placeholder")
        }

        if incoming.requestID == canonicalRequestID {
            return .rejectAdvisory(reason: "identity mapping requires correlated acknowledgement")
        }

        if hasAuthoritativeMirror {
            return .rejectAdvisory(reason: "authoritative HealthKit mirror already attached")
        }

        if incoming.startedFrom == .appleWatch {
            return .competingWorkout(reason: "independent Apple Watch workout")
        }

        return .rejectAdvisory(reason: "state does not correlate to current request")
    }

    static func shouldCreatePrimaryFromSynchronizedState(
        source: PulsarWatchPrimaryCreationSource,
        hasPrimarySession: Bool
    ) -> Bool {
        guard !hasPrimarySession else { return false }
        return source.canCreatePrimarySession
    }

    static func shouldRestoreCachedActiveGym(
        _ state: ActiveGymWorkoutState,
        platform: PulsarSynchronizedGymPlatform,
        isTombstoned: Bool
    ) -> Bool {
        if isTombstoned { return false }
        if state.isFinished { return false }
        if state.isPrelaunchPlaceholder { return false }
        // A process launch must never resurrect synchronized presentation
        // metadata as a live session on either platform. The Watch may retain
        // it as a candidate for a matching HealthKit recovery; the iPhone must
        // wait for a fresh WC delivery or mirrored HealthKit authority.
        return false
    }

    static func isHealthKitRecoveryCandidate(
        _ state: ActiveGymWorkoutState,
        sessionStartDate: Date?,
        platform: PulsarSynchronizedGymPlatform,
        isTombstoned: Bool
    ) -> Bool {
        guard platform == .watch,
              !isTombstoned,
              !state.isFinished,
              state.isValidActiveWorkoutPresentationCandidate(),
              let sessionStartDate else {
            return false
        }
        return abs(state.startedAt.timeIntervalSince(sessionStartDate)) <= 30
    }

    static func shouldAdoptIncomingGymState(
        incoming: ActiveGymWorkoutState,
        current: ActiveGymWorkoutState?,
        platform: PulsarSynchronizedGymPlatform,
        isIncomingFromCounterpart: Bool
    ) -> Bool {
        if incoming.isFinished {
            return true
        }

        let incomingGeneration = incoming.lifecycleGeneration ?? 0
        if let current, current.sessionId == incoming.sessionId {
            let currentGeneration = current.lifecycleGeneration ?? 0
            if incomingGeneration < currentGeneration {
                return false
            }
            if current.isFinished, !incoming.isFinished {
                return false
            }
        }

        if platform == .watch, isIncomingFromCounterpart {
            if incoming.startedFrom == .iPhone ||
                (incoming.startedFrom == .iPhoneRequestedWatchStart && incoming.isPrelaunchPlaceholder) {
                return true
            }
            if current?.sessionId == incoming.sessionId {
                return true
            }
            return false
        }

        return true
    }

    static func isTerminal(_ state: ActiveGymWorkoutState) -> Bool {
        state.isFinished
    }
}
