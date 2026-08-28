//
//  PulsarWatchPrimarySessionGateTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

struct PulsarWatchPrimarySessionGateTests {
    @Test func firstRequestIsAllowedToCreate() {
        var gate = PulsarWatchPrimarySessionGate()
        let workoutID = UUID()
        let requestID = UUID()

        #expect(gate.decision(requestedWorkoutID: workoutID, requestedRequestID: requestID) == .create)
        gate.markCreating(workoutID: workoutID, requestID: requestID)
        #expect(gate.isCreating)
        #expect(!gate.hasPrimarySession)
    }

    @Test func secondRequestForSameIDsIsIgnoredWhileCreating() {
        var gate = PulsarWatchPrimarySessionGate()
        let workoutID = UUID()
        let requestID = UUID()
        gate.markCreating(workoutID: workoutID, requestID: requestID)

        let decision = gate.decision(requestedWorkoutID: workoutID, requestedRequestID: requestID)
        guard case .ignore(let reason, let existing) = decision else {
            Issue.record("Expected duplicate start to be ignored while creating")
            return
        }
        #expect(reason == "creation already in flight")
        #expect(existing == workoutID)
    }

    @Test func secondRequestWithoutIDsIsIgnoredWhileCreating() {
        var gate = PulsarWatchPrimarySessionGate()
        gate.markCreating(workoutID: UUID(), requestID: UUID())

        let decision = gate.decision(requestedWorkoutID: nil, requestedRequestID: nil)
        guard case .ignore(let reason, _) = decision else {
            Issue.record("Concurrent start without identity must not create a second primary")
            return
        }
        #expect(reason == "creation already in flight")
    }

    @Test func existingPrimaryBlocksSameAndDifferentIdentities() {
        var gate = PulsarWatchPrimarySessionGate()
        let workoutID = UUID()
        let requestID = UUID()
        gate.markCreated(workoutID: workoutID, requestID: requestID)

        let same = gate.decision(requestedWorkoutID: workoutID, requestedRequestID: requestID)
        guard case .ignore(let sameReason, let existing) = same else {
            Issue.record("Existing primary must ignore the same workout")
            return
        }
        #expect(sameReason == "existing primary for workout")
        #expect(existing == workoutID)

        let other = gate.decision(requestedWorkoutID: UUID(), requestedRequestID: UUID())
        guard case .ignore(let otherReason, _) = other else {
            Issue.record("Existing primary must ignore a second HealthKit session")
            return
        }
        #expect(otherReason == "primary already exists")
    }

    @Test func matchingRequestIDIsEnoughToIgnore() {
        var gate = PulsarWatchPrimarySessionGate()
        let requestID = UUID()
        gate.markCreated(workoutID: UUID(), requestID: requestID)

        let decision = gate.decision(requestedWorkoutID: UUID(), requestedRequestID: requestID)
        guard case .ignore(let reason, _) = decision else {
            Issue.record("Matching requestID must be treated as the same logical workout")
            return
        }
        #expect(reason == "existing primary for workout")
    }

    @Test func failedCreationAllowsRetry() {
        var gate = PulsarWatchPrimarySessionGate()
        let workoutID = UUID()
        gate.markCreating(workoutID: workoutID, requestID: UUID())
        gate.markCreationFailed()

        #expect(!gate.isCreating)
        #expect(gate.decision(requestedWorkoutID: workoutID, requestedRequestID: nil) == .create)
    }

    @Test func resetClearsOwnership() {
        var gate = PulsarWatchPrimarySessionGate()
        gate.markCreated(workoutID: UUID(), requestID: UUID())
        gate.reset()
        #expect(gate.decision(requestedWorkoutID: UUID(), requestedRequestID: UUID()) == .create)
    }
}
