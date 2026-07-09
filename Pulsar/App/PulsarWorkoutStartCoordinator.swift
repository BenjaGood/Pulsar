//
//  PulsarWorkoutStartCoordinator.swift
//  Pulsar
//

import Foundation

struct PulsarWorkoutStartRequest: Equatable {
    let sessionID: UUID
    let kind: PulsarActiveWorkoutKind
    let source: String
    let workoutType: String
    let requestedAt: Date
}

enum PulsarWorkoutStartDecision: Equatable {
    case granted(PulsarWorkoutStartRequest)
    case duplicateStart(PulsarWorkoutStartRequest)
    case alreadyActive(UUID)
    case rejectedConflict(existingSessionID: UUID, requestedKind: PulsarActiveWorkoutKind)
}

@MainActor
final class PulsarWorkoutStartCoordinator {
    static let shared = PulsarWorkoutStartCoordinator()

    enum Phase: Equatable {
        case idle
        case starting(PulsarWorkoutStartRequest)
        case active(UUID)
    }

    private(set) var phase: Phase = .idle

    func requestStart(
        sessionID: UUID,
        kind: PulsarActiveWorkoutKind,
        source: String,
        workoutType: String
    ) -> PulsarWorkoutStartDecision {
        PulsarWorkoutLifecycleLogger.log(
            .workoutStartRequested,
            sessionID: sessionID,
            workoutType: workoutType,
            source: source
        )

        switch phase {
        case .idle:
            let request = PulsarWorkoutStartRequest(
                sessionID: sessionID,
                kind: kind,
                source: source,
                workoutType: workoutType,
                requestedAt: Date()
            )
            phase = .starting(request)
            PulsarWorkoutLifecycleLogger.log(
                .workoutStartValidated,
                sessionID: sessionID,
                workoutType: workoutType,
                source: source
            )
            return .granted(request)

        case .starting(let existing):
            if existing.sessionID == sessionID {
                PulsarWorkoutLifecycleLogger.log(
                    .workoutStartRejectedDuplicate,
                    sessionID: sessionID,
                    workoutType: workoutType,
                    source: source,
                    detail: "phase=starting"
                )
                return .duplicateStart(existing)
            }
            PulsarWorkoutLifecycleLogger.log(
                .workoutStartRejectedDuplicate,
                sessionID: sessionID,
                workoutType: workoutType,
                source: source,
                detail: "conflictWithStarting=\(existing.sessionID.uuidString)"
            )
            return .rejectedConflict(existingSessionID: existing.sessionID, requestedKind: kind)

        case .active(let existingSessionID):
            if existingSessionID == sessionID {
                PulsarWorkoutLifecycleLogger.log(
                    .workoutStartRejectedDuplicate,
                    sessionID: sessionID,
                    workoutType: workoutType,
                    source: source,
                    detail: "phase=active"
                )
                return .alreadyActive(existingSessionID)
            }
            PulsarWorkoutLifecycleLogger.log(
                .workoutStartRejectedDuplicate,
                sessionID: sessionID,
                workoutType: workoutType,
                source: source,
                detail: "conflictWithActive=\(existingSessionID.uuidString)"
            )
            return .rejectedConflict(existingSessionID: existingSessionID, requestedKind: kind)
        }
    }

    func markActivated(sessionID: UUID, workoutType: String, source: String) {
        switch phase {
        case .starting(let request) where request.sessionID == sessionID:
            phase = .active(sessionID)
        case .active(sessionID):
            break
        default:
            phase = .active(sessionID)
        }
        PulsarWorkoutLifecycleLogger.log(
            .workoutActivated,
            sessionID: sessionID,
            workoutType: workoutType,
            source: source
        )
    }

    func markStartFailed(sessionID: UUID, workoutType: String, source: String, error: String) {
        if case .starting(let request) = phase, request.sessionID == sessionID {
            phase = .idle
        }
        PulsarWorkoutLifecycleLogger.log(
            .workoutStartFailed,
            sessionID: sessionID,
            workoutType: workoutType,
            source: source,
            detail: error
        )
    }

    func markSessionEnded(sessionID: UUID, reason: String) {
        switch phase {
        case .active(let activeSessionID) where activeSessionID == sessionID:
            phase = .idle
        case .starting(let request) where request.sessionID == sessionID:
            phase = .idle
        default:
            break
        }
        PulsarWorkoutLifecycleLogger.log(
            .workoutSessionCleanedUp,
            sessionID: sessionID,
            detail: reason
        )
    }

    func resetForTesting() {
        phase = .idle
    }
}
