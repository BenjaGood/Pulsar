//
//  PulsarWorkoutStartCoordinatorTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

@MainActor
struct PulsarWorkoutStartCoordinatorTests {
    @Test func grantsFirstStartRequest() {
        let coordinator = PulsarWorkoutStartCoordinator()
        coordinator.resetForTesting()
        let sessionID = UUID()

        let decision = coordinator.requestStart(
            sessionID: sessionID,
            kind: .gym,
            source: "test",
            workoutType: "gym"
        )

        guard case .granted(let request) = decision else {
            Issue.record("Expected granted start decision")
            return
        }
        #expect(request.sessionID == sessionID)
        #expect(request.workoutType == "gym")
    }

    @Test func rejectsDuplicateStartForSameSession() {
        let coordinator = PulsarWorkoutStartCoordinator()
        coordinator.resetForTesting()
        let sessionID = UUID()

        _ = coordinator.requestStart(
            sessionID: sessionID,
            kind: .gym,
            source: "test",
            workoutType: "gym"
        )
        let duplicate = coordinator.requestStart(
            sessionID: sessionID,
            kind: .gym,
            source: "test",
            workoutType: "gym"
        )

        guard case .duplicateStart(let request) = duplicate else {
            Issue.record("Expected duplicate start decision")
            return
        }
        #expect(request.sessionID == sessionID)
    }

    @Test func rejectsStartWhileAnotherSessionIsActive() {
        let coordinator = PulsarWorkoutStartCoordinator()
        coordinator.resetForTesting()
        let firstSessionID = UUID()
        let secondSessionID = UUID()

        _ = coordinator.requestStart(
            sessionID: firstSessionID,
            kind: .gym,
            source: "test",
            workoutType: "gym"
        )
        coordinator.markActivated(sessionID: firstSessionID, workoutType: "gym", source: "test")

        let conflict = coordinator.requestStart(
            sessionID: secondSessionID,
            kind: .run(.running),
            source: "test",
            workoutType: "running"
        )

        guard case .rejectedConflict(let existingSessionID, _) = conflict else {
            Issue.record("Expected conflict decision")
            return
        }
        #expect(existingSessionID == firstSessionID)
    }

    @Test func returnsToIdleAfterSessionEnds() {
        let coordinator = PulsarWorkoutStartCoordinator()
        coordinator.resetForTesting()
        let sessionID = UUID()

        _ = coordinator.requestStart(
            sessionID: sessionID,
            kind: .gym,
            source: "test",
            workoutType: "gym"
        )
        coordinator.markActivated(sessionID: sessionID, workoutType: "gym", source: "test")
        coordinator.markSessionEnded(sessionID: sessionID, reason: "testFinished")

        let nextDecision = coordinator.requestStart(
            sessionID: UUID(),
            kind: .gym,
            source: "test",
            workoutType: "gym"
        )

        guard case .granted = nextDecision else {
            Issue.record("Expected a new start to be granted after cleanup")
            return
        }
    }

    @Test func marksStartFailureFromStartingState() {
        let coordinator = PulsarWorkoutStartCoordinator()
        coordinator.resetForTesting()
        let sessionID = UUID()

        _ = coordinator.requestStart(
            sessionID: sessionID,
            kind: .gym,
            source: "test",
            workoutType: "gym"
        )
        coordinator.markStartFailed(
            sessionID: sessionID,
            workoutType: "gym",
            source: "test",
            error: "HealthKitDenied"
        )

        guard case .granted = coordinator.requestStart(
            sessionID: UUID(),
            kind: .gym,
            source: "test",
            workoutType: "gym"
        ) else {
            Issue.record("Expected start gate to reopen after failure")
            return
        }
    }
}
