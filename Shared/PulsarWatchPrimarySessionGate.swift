//
//  PulsarWatchPrimarySessionGate.swift
//  Pulsar
//

import Foundation

enum PulsarWatchPrimarySessionDecision: Equatable, Sendable {
    case create
    case ignore(reason: String, existingWorkoutID: UUID?)
}

/// Watch-side ownership for one user workout. Creation must be decided
/// synchronously before any `await`, or two `HKWorkoutSession` objects can
/// be constructed for the same request.
struct PulsarWatchPrimarySessionGate: Equatable, Sendable {
    var workoutID: UUID?
    var requestID: UUID?
    var isCreating = false
    var hasPrimarySession = false

    mutating func adoptIdentity(workoutID: UUID?, requestID: UUID?) {
        if let workoutID {
            self.workoutID = workoutID
        }
        if let requestID {
            self.requestID = requestID
        }
    }

    func decision(
        requestedWorkoutID: UUID?,
        requestedRequestID: UUID?
    ) -> PulsarWatchPrimarySessionDecision {
        if hasPrimarySession {
            if identitiesMatch(requestedWorkoutID: requestedWorkoutID, requestedRequestID: requestedRequestID) {
                return .ignore(
                    reason: "existing primary for workout",
                    existingWorkoutID: workoutID
                )
            }
            return .ignore(
                reason: "primary already exists",
                existingWorkoutID: workoutID
            )
        }
        if isCreating {
            if identitiesMatch(requestedWorkoutID: requestedWorkoutID, requestedRequestID: requestedRequestID)
                || (requestedWorkoutID == nil && requestedRequestID == nil)
                || workoutID == nil {
                return .ignore(
                    reason: "creation already in flight",
                    existingWorkoutID: workoutID
                )
            }
            return .ignore(
                reason: "creation already in flight",
                existingWorkoutID: workoutID
            )
        }
        return .create
    }

    mutating func markCreating(workoutID: UUID?, requestID: UUID?) {
        isCreating = true
        adoptIdentity(workoutID: workoutID, requestID: requestID)
    }

    mutating func markCreated(workoutID: UUID?, requestID: UUID?) {
        isCreating = false
        hasPrimarySession = true
        adoptIdentity(workoutID: workoutID, requestID: requestID)
    }

    mutating func markCreationFailed() {
        isCreating = false
        if !hasPrimarySession {
            // Keep adopted identity so a retry can still correlate, but allow create.
        }
    }

    mutating func reset() {
        self = PulsarWatchPrimarySessionGate()
    }

    private func identitiesMatch(requestedWorkoutID: UUID?, requestedRequestID: UUID?) -> Bool {
        if let requestedWorkoutID, let workoutID, requestedWorkoutID == workoutID {
            return true
        }
        if let requestedRequestID, let requestID, requestedRequestID == requestID {
            return true
        }
        return false
    }
}
