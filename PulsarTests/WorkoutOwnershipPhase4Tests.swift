//
//  WorkoutOwnershipPhase4Tests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

@MainActor
struct WorkoutOwnershipPhase4Tests {
    private func makeCoordinator() -> PulsarWorkoutStartCoordinator {
        let coordinator = PulsarWorkoutStartCoordinator()
        coordinator.resetForTesting()
        return coordinator
    }

    @Test func markActivatedFromIllegalPhaseDoesNotInventTransaction() {
        let coordinator = makeCoordinator()
        let sessionID = UUID()

        coordinator.markActivated(
            sessionID: sessionID,
            workoutType: "gym",
            source: "test"
        )

        #expect(coordinator.phase == .idle)
        #expect(!coordinator.didReachActive(sessionID: sessionID))
        #expect(coordinator.presentationPolicy == .hidden)
    }

    @Test func didReachActiveOnlyAfterSuccessfulActivation() {
        let coordinator = makeCoordinator()
        let sessionID = UUID()

        _ = coordinator.requestStart(
            sessionID: sessionID,
            kind: .gym,
            source: "test",
            workoutType: "gym"
        )
        #expect(coordinator.presentationPolicy == .loading)
        #expect(!coordinator.canPresentSummary(sessionID: sessionID))

        coordinator.markActivated(
            sessionID: sessionID,
            workoutType: "gym",
            source: "test"
        )

        #expect(coordinator.didReachActive(sessionID: sessionID))
        #expect(coordinator.canPresentSummary(sessionID: sessionID))
        #expect(coordinator.presentationPolicy == .live)
    }

    @Test func summaryBlockedWhenSessionNeverReachedActive() {
        let coordinator = makeCoordinator()
        let sessionID = UUID()

        _ = coordinator.requestStart(
            sessionID: sessionID,
            kind: .run(.running),
            source: "test",
            workoutType: "running"
        )
        coordinator.markStartFailed(
            sessionID: sessionID,
            workoutType: "running",
            source: "test",
            error: "watchLaunchFailed"
        )

        #expect(!coordinator.canPresentSummary(sessionID: sessionID))
        guard case .failed = coordinator.phase else {
            Issue.record("Expected retained failed phase")
            return
        }
        #expect(coordinator.presentationPolicy == .failed("watchLaunchFailed"))
    }

    @Test func externalWatchSessionCanBecomeSummaryEligible() {
        let coordinator = makeCoordinator()
        let sessionID = UUID()

        coordinator.markSessionReachedActive(sessionID: sessionID, source: "watchOriginated")

        #expect(coordinator.didReachActive(sessionID: sessionID))
        #expect(coordinator.canPresentSummary(sessionID: sessionID))
    }

    @Test func completedPhaseRetainedUntilAcknowledged() {
        let coordinator = makeCoordinator()
        let sessionID = UUID()

        _ = coordinator.requestStart(
            sessionID: sessionID,
            kind: .gym,
            source: "test",
            workoutType: "gym"
        )
        coordinator.markActivated(
            sessionID: sessionID,
            workoutType: "gym",
            source: "test"
        )
        coordinator.markSessionEnded(sessionID: sessionID, reason: "testFinished")

        guard case .completed = coordinator.phase else {
            Issue.record("Expected retained completed phase")
            return
        }
        #expect(coordinator.presentationPolicy == .summaryEligible)
        #expect(coordinator.canPresentSummary(sessionID: sessionID))

        coordinator.acknowledgeTerminal(sessionID: sessionID, reason: "summaryConsumed")
        #expect(coordinator.phase == .idle)
        #expect(!coordinator.canPresentSummary(sessionID: sessionID))
        #expect(coordinator.presentationPolicy == .hidden)
    }

    @Test func presentationPolicyFollowsCrossDeviceAckPath() {
        let coordinator = makeCoordinator()
        let request = GymWorkoutStartRequest(
            routineID: UUID(),
            routineRevision: 1,
            workoutKind: .routine,
            activityTypeRawValue: 50,
            locationTypeRawValue: 1
        )

        _ = coordinator.beginCrossDeviceGymStart(request: request, source: "test")
        #expect(coordinator.presentationPolicy == .loading)

        _ = coordinator.markWatchLaunchSubmitted(requestID: request.requestID, source: "test")
        #expect(coordinator.presentationPolicy == .loading)
        #expect(
            coordinator.markWaitingForWatchAcknowledgement(requestID: request.requestID, source: "test") == .applied
        )

        let acknowledgement = GymWorkoutStartAcknowledgement(
            requestID: request.requestID,
            candidateSessionID: request.candidateSessionID,
            authoritativeSessionID: request.candidateSessionID,
            sessionState: .running,
            mirroringState: .active
        )
        guard case .accepted = coordinator.receiveWatchAcknowledgement(acknowledgement, source: "test") else {
            Issue.record("Expected accepted acknowledgement")
            return
        }

        coordinator.markActivated(
            sessionID: request.candidateSessionID,
            workoutType: request.workoutKind.rawValue,
            source: "test"
        )
        #expect(coordinator.presentationPolicy == .live)
        #expect(coordinator.didReachActive(sessionID: request.candidateSessionID))
    }

    @Test func newStartAllowedFromRetainedTerminalPhase() {
        let coordinator = makeCoordinator()
        let firstSessionID = UUID()
        let secondSessionID = UUID()

        _ = coordinator.requestStart(
            sessionID: firstSessionID,
            kind: .gym,
            source: "test",
            workoutType: "gym"
        )
        coordinator.markActivated(sessionID: firstSessionID, workoutType: "gym", source: "test")
        coordinator.markSessionEnded(sessionID: firstSessionID, reason: "testFinished")

        guard case .granted = coordinator.requestStart(
            sessionID: secondSessionID,
            kind: .run(.running),
            source: "test",
            workoutType: "running"
        ) else {
            Issue.record("Expected new start from retained completed phase")
            return
        }
        #expect(coordinator.presentationPolicy == .loading)
    }
}
