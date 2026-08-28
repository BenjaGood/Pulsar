//
//  PulsarWorkoutStartCoordinatorTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

@MainActor
struct PulsarWorkoutStartCoordinatorTests {
    private func makeCoordinator() -> PulsarWorkoutStartCoordinator {
        let coordinator = PulsarWorkoutStartCoordinator()
        coordinator.resetForTesting()
        return coordinator
    }

    @Test func grantsFirstStartRequest() {
        let coordinator = makeCoordinator()
        let sessionID = UUID()

        let decision = coordinator.requestStart(
            sessionID: sessionID,
            kind: .gym,
            source: "test",
            workoutType: "gym"
        )

        guard case .granted(let transaction) = decision else {
            Issue.record("Expected granted start decision")
            return
        }
        #expect(transaction.sessionID == sessionID)
        #expect(coordinator.phase.name == "preparing")
    }

    @Test func rejectsDuplicateStartForSameSession() {
        let coordinator = makeCoordinator()
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

        guard case .duplicateStart(let transaction) = duplicate else {
            Issue.record("Expected duplicate start decision")
            return
        }
        #expect(transaction.sessionID == sessionID)
    }

    @Test func rejectsStartWhileAnotherSessionIsActive() {
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
        let coordinator = makeCoordinator()
        let sessionID = UUID()

        _ = coordinator.requestStart(
            sessionID: sessionID,
            kind: .gym,
            source: "test",
            workoutType: "gym"
        )
        coordinator.markActivated(sessionID: sessionID, workoutType: "gym", source: "test")
        coordinator.markSessionEnded(sessionID: sessionID, reason: "testFinished")
        #expect(coordinator.phase.name == "completed")

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

    @Test func finishRequestAndTerminalConfirmationAreDistinctLifecycleStates() {
        let coordinator = makeCoordinator()
        let sessionID = UUID()
        _ = coordinator.requestStart(
            sessionID: sessionID,
            kind: .watchGym,
            source: "test",
            workoutType: "routine"
        )
        coordinator.markActivated(sessionID: sessionID, workoutType: "routine", source: "test")

        #expect(coordinator.markSessionEnding(sessionID: sessionID, reason: "test") == .applied)
        #expect(coordinator.phase.name == "ending")
        #expect(coordinator.markSessionEnding(sessionID: sessionID, reason: "duplicate") == .duplicate)

        coordinator.markSessionEnded(sessionID: sessionID, reason: "confirmedTerminal")
        #expect(coordinator.phase.name == "completed")
        #expect(coordinator.presentationPolicy == .summaryEligible)
    }

    @Test func marksStartFailureFromStartingState() {
        let coordinator = makeCoordinator()
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

    @Test func crossDeviceGymStartAdvancesThroughWatchAcknowledgement() {
        let coordinator = makeCoordinator()
        let request = GymWorkoutStartRequest(
            routineID: UUID(),
            routineRevision: 1,
            workoutKind: .routine,
            activityTypeRawValue: 50,
            locationTypeRawValue: 1
        )

        guard case .granted = coordinator.beginCrossDeviceGymStart(request: request, source: "test") else {
            Issue.record("Expected granted cross-device start")
            return
        }

        #expect(coordinator.markWatchLaunchSubmitted(requestID: request.requestID, source: "test") == .applied)
        #expect(coordinator.markWaitingForWatchAcknowledgement(requestID: request.requestID, source: "test") == .applied)

        let acknowledgement = GymWorkoutStartAcknowledgement(
            requestID: request.requestID,
            candidateSessionID: request.candidateSessionID,
            authoritativeSessionID: request.candidateSessionID,
            sessionState: .running,
            mirroringState: .active
        )

        guard case .accepted = coordinator.receiveWatchAcknowledgement(acknowledgement, source: "test") else {
            Issue.record("Expected watch acknowledgement to be accepted")
            return
        }
        #expect(coordinator.isCrossDeviceGymStartVerified)
    }

    @Test func rejectsStaleWatchAcknowledgement() {
        let coordinator = makeCoordinator()
        let request = GymWorkoutStartRequest(
            routineID: UUID(),
            routineRevision: 1,
            workoutKind: .routine,
            activityTypeRawValue: 50,
            locationTypeRawValue: 1
        )
        _ = coordinator.beginCrossDeviceGymStart(request: request, source: "test")

        let staleAck = GymWorkoutStartAcknowledgement(
            requestID: UUID(),
            candidateSessionID: UUID(),
            authoritativeSessionID: UUID(),
            sessionState: .preparing,
            mirroringState: .pending
        )

        guard case .stale = coordinator.receiveWatchAcknowledgement(staleAck, source: "test") else {
            Issue.record("Expected stale acknowledgement rejection")
            return
        }
    }

    @Test func rejectsLateAcknowledgementAfterIPhoneFallback() {
        let coordinator = makeCoordinator()
        let request = GymWorkoutStartRequest(
            routineID: UUID(),
            routineRevision: 1,
            workoutKind: .routine,
            activityTypeRawValue: 50,
            locationTypeRawValue: 1
        )
        _ = coordinator.beginCrossDeviceGymStart(request: request, source: "test")
        coordinator.markIPhoneFallbackChosen(requestID: request.requestID, source: "test")

        let acknowledgement = GymWorkoutStartAcknowledgement(
            requestID: request.requestID,
            candidateSessionID: request.candidateSessionID,
            authoritativeSessionID: request.candidateSessionID,
            sessionState: .running,
            mirroringState: .active
        )

        guard case .lateAfterFallback = coordinator.receiveWatchAcknowledgement(acknowledgement, source: "test") else {
            Issue.record("Expected late-after-fallback rejection")
            return
        }
    }

    @Test func rejectsLateAcknowledgementAfterPendingStartCancel() {
        let coordinator = makeCoordinator()
        let request = GymWorkoutStartRequest(
            routineID: UUID(),
            routineRevision: 1,
            workoutKind: .routine,
            activityTypeRawValue: 50,
            locationTypeRawValue: 1
        )
        _ = coordinator.beginCrossDeviceGymStart(request: request, source: "test")
        coordinator.cancelCurrentStart(requestID: request.requestID, source: "test")

        let acknowledgement = GymWorkoutStartAcknowledgement(
            requestID: request.requestID,
            candidateSessionID: request.candidateSessionID,
            authoritativeSessionID: request.candidateSessionID,
            sessionState: .running,
            mirroringState: .active
        )

        guard case .duplicate = coordinator.receiveWatchAcknowledgement(acknowledgement, source: "test") else {
            Issue.record("Expected terminal noop after cancelling the pending start")
            return
        }
        #expect(coordinator.phase.name == "cancelled")
        #expect(!coordinator.isCrossDeviceGymStartVerified)
        #expect(!GymLaunchWatchSessionPresentation.shouldRevealWatchSession(phase: .cancelled))

        let retry = GymWorkoutStartRequest(
            routineID: UUID(),
            routineRevision: 1,
            workoutKind: .freeWorkout,
            activityTypeRawValue: 50,
            locationTypeRawValue: 1
        )
        guard case .granted = coordinator.beginCrossDeviceGymStart(request: retry, source: "test") else {
            Issue.record("Expected a new start after cancelling the pending Watch attempt")
            return
        }
    }

    @Test func marksWatchAcknowledgementTimeout() {
        let coordinator = makeCoordinator()
        let request = GymWorkoutStartRequest(
            routineID: UUID(),
            routineRevision: 1,
            workoutKind: .routine,
            activityTypeRawValue: 50,
            locationTypeRawValue: 1
        )
        _ = coordinator.beginCrossDeviceGymStart(request: request, source: "test")
        _ = coordinator.markWatchLaunchSubmitted(requestID: request.requestID, source: "test")
        _ = coordinator.markWaitingForWatchAcknowledgement(requestID: request.requestID, source: "test")

        #expect(coordinator.markWatchAcknowledgementTimedOut(requestID: request.requestID, source: "test") == .applied)
        #expect(coordinator.phase.name == "reconcilingRemote")
        #expect(coordinator.presentationPolicy != .hidden)
    }

    @Test func duplicateIdempotencyKeyReturnsDuplicateStart() {
        let coordinator = makeCoordinator()
        let requestID = UUID()
        let request = GymWorkoutStartRequest(
            requestID: requestID,
            candidateSessionID: UUID(),
            idempotencyKey: "same-key",
            routineID: UUID(),
            routineRevision: 1,
            workoutKind: .routine,
            activityTypeRawValue: 50,
            locationTypeRawValue: 1
        )

        guard case .granted = coordinator.beginCrossDeviceGymStart(request: request, source: "test") else {
            Issue.record("Expected first cross-device start to be granted")
            return
        }

        guard case .duplicateStart = coordinator.beginCrossDeviceGymStart(request: request, source: "test") else {
            Issue.record("Expected duplicate idempotent start")
            return
        }
    }

    @Test func mirroredSessionMovesToMirroringPhase() {
        let coordinator = makeCoordinator()
        let request = GymWorkoutStartRequest(
            routineID: UUID(),
            routineRevision: 1,
            workoutKind: .routine,
            activityTypeRawValue: 50,
            locationTypeRawValue: 1
        )
        _ = coordinator.beginCrossDeviceGymStart(request: request, source: "test")
        _ = coordinator.markWatchLaunchSubmitted(requestID: request.requestID, source: "test")
        _ = coordinator.markWaitingForWatchAcknowledgement(requestID: request.requestID, source: "test")

        let acknowledgement = GymWorkoutStartAcknowledgement(
            requestID: request.requestID,
            candidateSessionID: request.candidateSessionID,
            authoritativeSessionID: request.candidateSessionID,
            sessionState: .running,
            mirroringState: .unavailableWatchRecording
        )
        _ = coordinator.receiveWatchAcknowledgement(acknowledgement, source: "test")
        #expect(coordinator.phase.name == "watchSessionRunning")

        #expect(
            coordinator.markMirroredSessionReceived(
                sessionID: request.candidateSessionID,
                requestID: request.requestID,
                source: "test"
            ) == .applied
        )
        #expect(coordinator.phase.name == "mirroring")
    }

    @Test func matchingGymMirrorBeforeAcknowledgementVerifiesStart() {
        let coordinator = makeCoordinator()
        let request = GymWorkoutStartRequest(
            routineID: UUID(),
            routineRevision: 1,
            workoutKind: .routine,
            activityTypeRawValue: 50,
            locationTypeRawValue: 1
        )
        _ = coordinator.beginCrossDeviceGymStart(request: request, source: "test")
        _ = coordinator.markWatchLaunchSubmitted(requestID: request.requestID, source: "test")
        _ = coordinator.markWaitingForWatchAcknowledgement(requestID: request.requestID, source: "test")

        #expect(
            coordinator.markMirroredSessionReceived(
                sessionID: request.candidateSessionID,
                requestID: request.requestID,
                source: "test"
            ) == .applied
        )
        #expect(coordinator.phase.name == "mirroring")
        #expect(coordinator.isCrossDeviceGymStartVerified)
    }

    @Test func gymMirrorRequiresMatchingCandidateSession() {
        let coordinator = makeCoordinator()
        let request = GymWorkoutStartRequest(
            routineID: UUID(),
            routineRevision: 1,
            workoutKind: .routine,
            activityTypeRawValue: 50,
            locationTypeRawValue: 1
        )
        _ = coordinator.beginCrossDeviceGymStart(request: request, source: "test")
        _ = coordinator.markWatchLaunchSubmitted(requestID: request.requestID, source: "test")

        #expect(
            coordinator.markMirroredSessionReceived(
                sessionID: UUID(),
                requestID: request.requestID,
                source: "test"
            ) == .rejectedStale(requestID: request.requestID)
        )
        #expect(!coordinator.isCrossDeviceGymStartVerified)
    }

    @Test func matchingWatchVerificationRequiresBothRequestAndSession() {
        let coordinator = makeCoordinator()
        let request = GymWorkoutStartRequest(
            routineID: UUID(),
            routineRevision: 1,
            workoutKind: .routine,
            activityTypeRawValue: 50,
            locationTypeRawValue: 1
        )
        _ = coordinator.beginCrossDeviceGymStart(request: request, source: "test")
        _ = coordinator.markWatchLaunchSubmitted(requestID: request.requestID, source: "test")
        _ = coordinator.markWaitingForWatchAcknowledgement(requestID: request.requestID, source: "test")

        #expect(!coordinator.isWatchStartVerified(requestID: UUID(), candidateSessionID: request.candidateSessionID))
        #expect(!coordinator.isWatchStartVerified(requestID: request.requestID, candidateSessionID: UUID()))

        let acknowledgement = GymWorkoutStartAcknowledgement(
            requestID: request.requestID,
            candidateSessionID: request.candidateSessionID,
            authoritativeSessionID: request.candidateSessionID,
            sessionState: .running,
            mirroringState: .active
        )
        _ = coordinator.receiveWatchAcknowledgement(acknowledgement, source: "test")
        #expect(coordinator.isWatchStartVerified(requestID: request.requestID, candidateSessionID: request.candidateSessionID))
    }

    @Test func watchStartCanEnterOneRecoveryCycleBeforeTimingOut() {
        let coordinator = makeCoordinator()
        let request = GymWorkoutStartRequest(
            routineID: UUID(),
            routineRevision: 1,
            workoutKind: .routine,
            activityTypeRawValue: 50,
            locationTypeRawValue: 1
        )
        _ = coordinator.beginCrossDeviceGymStart(request: request, source: "test")
        _ = coordinator.markWatchLaunchSubmitted(requestID: request.requestID, source: "test")
        _ = coordinator.markWaitingForWatchAcknowledgement(requestID: request.requestID, source: "test")

        #expect(coordinator.markWatchStartRecovering(requestID: request.requestID, source: "test") == .applied)
        #expect(coordinator.phase.name == "recovering")
        #expect(coordinator.markWatchAcknowledgementTimedOut(requestID: request.requestID, source: "test") == .applied)
        #expect(coordinator.phase.name == "reconcilingRemote")
    }

    @Test func gymAcknowledgementRequiresMatchingCandidateSession() {
        let coordinator = makeCoordinator()
        let request = GymWorkoutStartRequest(
            routineID: UUID(),
            routineRevision: 1,
            workoutKind: .routine,
            activityTypeRawValue: 50,
            locationTypeRawValue: 1
        )
        _ = coordinator.beginCrossDeviceGymStart(request: request, source: "test")
        let acknowledgement = GymWorkoutStartAcknowledgement(
            requestID: request.requestID,
            candidateSessionID: UUID(),
            authoritativeSessionID: UUID(),
            sessionState: .running,
            mirroringState: .active
        )

        guard case .stale = coordinator.receiveWatchAcknowledgement(acknowledgement, source: "test") else {
            Issue.record("Expected candidate-session mismatch to be rejected")
            return
        }
        #expect(!coordinator.isCrossDeviceGymStartVerified)
    }

    @Test func gymAcknowledgementArrivingDuringWatchLaunchRemainsVerified() {
        let coordinator = makeCoordinator()
        let request = GymWorkoutStartRequest(
            routineID: UUID(),
            routineRevision: 1,
            workoutKind: .routine,
            activityTypeRawValue: 50,
            locationTypeRawValue: 1
        )
        _ = coordinator.beginCrossDeviceGymStart(request: request, source: "test")
        _ = coordinator.markWatchLaunchSubmitted(requestID: request.requestID, source: "test")
        let acknowledgement = GymWorkoutStartAcknowledgement(
            requestID: request.requestID,
            candidateSessionID: request.candidateSessionID,
            authoritativeSessionID: request.candidateSessionID,
            sessionState: .running,
            mirroringState: .unavailableWatchRecording
        )

        guard case .accepted = coordinator.receiveWatchAcknowledgement(acknowledgement, source: "test") else {
            Issue.record("Expected acknowledgement during launch to be accepted")
            return
        }
        #expect(coordinator.isCrossDeviceGymStartVerified)
        #expect(
            coordinator.markWaitingForWatchAcknowledgement(requestID: request.requestID, source: "test")
                == .rejectedIllegalTransition(from: "watchSessionRunning", to: "waitingForWatchAcknowledgement")
        )
        #expect(coordinator.isCrossDeviceGymStartVerified)
    }

    @Test func runStartRequiresMatchingRunningAcknowledgement() {
        let coordinator = makeCoordinator()
        let sessionID = UUID()
        let requestID = UUID()
        _ = coordinator.requestStart(
            sessionID: sessionID,
            kind: .run(.running),
            source: "test",
            workoutType: PulsarOutdoorWorkoutKind.running.rawValue
        )
        _ = coordinator.markWatchLaunchSubmitted(requestID: requestID, source: "test")
        _ = coordinator.markWaitingForWatchAcknowledgement(requestID: requestID, source: "test")

        let stale = PulsarRunStartAcknowledgement(
            requestID: requestID,
            candidateSessionID: UUID(),
            authoritativeSessionID: UUID(),
            workoutKind: .running,
            isHealthKitRunning: true,
            isMirroringAvailable: true,
            acknowledgedAt: Date()
        )
        guard case .stale = coordinator.receiveRunWatchAcknowledgement(stale, source: "test") else {
            Issue.record("Expected stale run acknowledgement rejection")
            return
        }

        let accepted = PulsarRunStartAcknowledgement(
            requestID: requestID,
            candidateSessionID: sessionID,
            authoritativeSessionID: sessionID,
            workoutKind: .running,
            isHealthKitRunning: true,
            isMirroringAvailable: false,
            acknowledgedAt: Date()
        )
        guard case .accepted = coordinator.receiveRunWatchAcknowledgement(accepted, source: "test") else {
            Issue.record("Expected matching run acknowledgement")
            return
        }
        #expect(coordinator.phase.name == "watchSessionRunning")
    }

    @Test func runMirroredSessionMovesToMirroringPhase() {
        let coordinator = makeCoordinator()
        let sessionID = UUID()
        let requestID = UUID()
        _ = coordinator.requestStart(
            sessionID: sessionID,
            kind: .run(.running),
            source: "test",
            workoutType: PulsarOutdoorWorkoutKind.running.rawValue
        )
        _ = coordinator.markWatchLaunchSubmitted(requestID: requestID, source: "test")
        _ = coordinator.markWaitingForWatchAcknowledgement(requestID: requestID, source: "test")

        let acknowledgement = PulsarRunStartAcknowledgement(
            requestID: requestID,
            candidateSessionID: sessionID,
            authoritativeSessionID: sessionID,
            workoutKind: .running,
            isHealthKitRunning: true,
            isMirroringAvailable: true,
            acknowledgedAt: Date()
        )
        _ = coordinator.receiveRunWatchAcknowledgement(acknowledgement, source: "test")
        #expect(coordinator.phase.name == "watchSessionRunning")
        #expect(coordinator.presentationPolicy == .loading)
        #expect(coordinator.isWatchStartVerified(requestID: requestID, candidateSessionID: sessionID))

        #expect(
            coordinator.markMirroredSessionReceived(
                sessionID: sessionID,
                requestID: requestID,
                source: "test"
            ) == .applied
        )
        #expect(coordinator.phase.name == "mirroring")
        #expect(coordinator.presentationPolicy == .loading)

        coordinator.markActivated(
            sessionID: sessionID,
            workoutType: PulsarOutdoorWorkoutKind.running.rawValue,
            source: "test"
        )
        #expect(coordinator.presentationPolicy == .live)
    }

    @Test func defersForegroundHealthRefreshDuringWatchHandshakeOnly() {
        let coordinator = makeCoordinator()
        #expect(coordinator.shouldDeferForegroundHealthRefresh == false)

        let request = GymWorkoutStartRequest(
            routineID: UUID(),
            routineRevision: 1,
            workoutKind: .routine,
            activityTypeRawValue: 50,
            locationTypeRawValue: 1
        )
        guard case .granted = coordinator.beginCrossDeviceGymStart(request: request, source: "test") else {
            Issue.record("Expected granted cross-device start")
            return
        }
        #expect(coordinator.shouldDeferForegroundHealthRefresh)

        _ = coordinator.markWatchLaunchSubmitted(requestID: request.requestID, source: "test")
        _ = coordinator.markWaitingForWatchAcknowledgement(requestID: request.requestID, source: "test")
        #expect(coordinator.shouldDeferForegroundHealthRefresh)

        let acknowledgement = GymWorkoutStartAcknowledgement(
            requestID: request.requestID,
            candidateSessionID: request.candidateSessionID,
            authoritativeSessionID: request.candidateSessionID,
            sessionState: .running,
            mirroringState: .active
        )
        _ = coordinator.receiveWatchAcknowledgement(acknowledgement, source: "test")
        #expect(coordinator.shouldDeferForegroundHealthRefresh)

        coordinator.markActivated(
            sessionID: request.candidateSessionID,
            workoutType: "gym",
            source: "test"
        )
        #expect(coordinator.phase.name == "active")
        #expect(coordinator.shouldDeferForegroundHealthRefresh == false)
    }

    @Test func lateGymAcknowledgementDoesNotDowngradeActiveToMirroring() {
        let coordinator = makeCoordinator()
        let request = GymWorkoutStartRequest(
            routineID: UUID(),
            routineRevision: 7,
            workoutKind: .routine,
            activityTypeRawValue: 50,
            locationTypeRawValue: 1
        )
        _ = coordinator.beginCrossDeviceGymStart(request: request, source: "test")
        _ = coordinator.markWatchLaunchSubmitted(requestID: request.requestID, source: "test")
        #expect(coordinator.markMirroredSessionReceived(
            sessionID: request.candidateSessionID,
            requestID: request.requestID,
            source: "test"
        ) == .applied)
        coordinator.markActivated(
            sessionID: request.candidateSessionID,
            workoutType: "gym",
            source: "test"
        )

        let acknowledgement = GymWorkoutStartAcknowledgement(
            requestID: request.requestID,
            candidateSessionID: request.candidateSessionID,
            authoritativeSessionID: request.candidateSessionID,
            sessionState: .running,
            mirroringState: .active
        )
        guard case .accepted = coordinator.receiveWatchAcknowledgement(acknowledgement, source: "lateTest") else {
            Issue.record("Expected correlated late acknowledgement to enrich the transaction")
            return
        }

        #expect(coordinator.phase.name == "active")
        #expect(coordinator.presentationPolicy == .live)
        #expect(coordinator.currentTransaction?.authoritativeSessionID == request.candidateSessionID)
    }

    @Test func acknowledgementCannotResurrectFailedGymStart() {
        let coordinator = makeCoordinator()
        let request = GymWorkoutStartRequest(
            routineID: UUID(),
            routineRevision: 1,
            workoutKind: .routine,
            activityTypeRawValue: 50,
            locationTypeRawValue: 1
        )
        _ = coordinator.beginCrossDeviceGymStart(request: request, source: "test")
        _ = coordinator.markWatchLaunchSubmitted(requestID: request.requestID, source: "test")
        coordinator.markStartFailed(
            sessionID: request.candidateSessionID,
            workoutType: "gym",
            source: "test",
            error: "existingWorkoutConflict"
        )
        let acknowledgement = GymWorkoutStartAcknowledgement(
            requestID: request.requestID,
            candidateSessionID: request.candidateSessionID,
            authoritativeSessionID: request.candidateSessionID,
            sessionState: .running,
            mirroringState: .active
        )

        #expect(coordinator.receiveWatchAcknowledgement(acknowledgement, source: "lateTest") == .duplicate)
        #expect(coordinator.phase.name == "failed")
        #expect(coordinator.presentationPolicy == .failed("existingWorkoutConflict"))
    }

    @Test func timeoutAfterWatchLaunchKeepsDeferringForegroundHealthRefresh() {
        let coordinator = makeCoordinator()
        let request = GymWorkoutStartRequest(
            routineID: UUID(),
            routineRevision: 1,
            workoutKind: .routine,
            activityTypeRawValue: 50,
            locationTypeRawValue: 1
        )
        _ = coordinator.beginCrossDeviceGymStart(request: request, source: "test")
        _ = coordinator.markWatchLaunchSubmitted(requestID: request.requestID, source: "test")
        _ = coordinator.markWaitingForWatchAcknowledgement(requestID: request.requestID, source: "test")
        #expect(coordinator.shouldDeferForegroundHealthRefresh)

        _ = coordinator.markWatchAcknowledgementTimedOut(requestID: request.requestID, source: "test")
        #expect(coordinator.phase.name == "reconcilingRemote")
        #expect(coordinator.shouldDeferForegroundHealthRefresh)
    }

    @Test func timeoutAfterWatchLaunchBlocksANewWorkoutIdentity() {
        let coordinator = makeCoordinator()
        let request = GymWorkoutStartRequest(
            routineID: UUID(),
            routineRevision: 1,
            workoutKind: .routine,
            activityTypeRawValue: 50,
            locationTypeRawValue: 1
        )
        _ = coordinator.beginCrossDeviceGymStart(request: request, source: "test")
        _ = coordinator.markWatchLaunchSubmitted(requestID: request.requestID, source: "test")
        _ = coordinator.markWaitingForWatchAcknowledgement(requestID: request.requestID, source: "test")
        _ = coordinator.markWatchAcknowledgementTimedOut(requestID: request.requestID, source: "test")

        let second = GymWorkoutStartRequest(
            routineID: request.routineID,
            routineRevision: 1,
            workoutKind: .routine,
            activityTypeRawValue: 50,
            locationTypeRawValue: 1
        )
        guard case .rejectedConflict(let existing, _) = coordinator.beginCrossDeviceGymStart(
            request: second,
            source: "test"
        ) else {
            Issue.record("A new workout ID must not be granted while Watch remote state is unknown")
            return
        }
        #expect(existing == request.candidateSessionID)
    }

    @Test func confirmedAbsentRemoteWorkoutAllowsANewIdentity() {
        let coordinator = makeCoordinator()
        let request = GymWorkoutStartRequest(
            routineID: UUID(),
            routineRevision: 1,
            workoutKind: .routine,
            activityTypeRawValue: 50,
            locationTypeRawValue: 1
        )
        _ = coordinator.beginCrossDeviceGymStart(request: request, source: "test")
        _ = coordinator.markWatchLaunchSubmitted(requestID: request.requestID, source: "test")
        _ = coordinator.markWaitingForWatchAcknowledgement(requestID: request.requestID, source: "test")
        _ = coordinator.markWatchAcknowledgementTimedOut(requestID: request.requestID, source: "test")
        #expect(coordinator.markRemoteWorkoutAbsent(requestID: request.requestID, source: "test") == .applied)
        #expect(coordinator.phase.name == "failed")

        let second = GymWorkoutStartRequest(
            routineID: request.routineID,
            routineRevision: 1,
            workoutKind: .routine,
            activityTypeRawValue: 50,
            locationTypeRawValue: 1
        )
        guard case .granted = coordinator.beginCrossDeviceGymStart(request: second, source: "test") else {
            Issue.record("A new identity is allowed only after Watch is known idle")
            return
        }
        #expect(second.candidateSessionID != request.candidateSessionID)
    }

    @Test func mismatchedWatchAckCannotReplaceThePendingWorkout() {
        let coordinator = makeCoordinator()
        let request = GymWorkoutStartRequest(
            routineID: UUID(),
            routineRevision: 1,
            workoutKind: .routine,
            activityTypeRawValue: 50,
            locationTypeRawValue: 1
        )
        _ = coordinator.beginCrossDeviceGymStart(request: request, source: "test")
        _ = coordinator.markWatchLaunchSubmitted(requestID: request.requestID, source: "test")
        _ = coordinator.markWaitingForWatchAcknowledgement(requestID: request.requestID, source: "test")

        let remoteSessionID = UUID()
        let remoteRequestID = UUID()
        let acknowledgement = GymWorkoutStartAcknowledgement(
            requestID: remoteRequestID,
            candidateSessionID: remoteSessionID,
            authoritativeSessionID: remoteSessionID,
            sessionState: .running,
            mirroringState: .unavailableWatchRecording
        )
        guard case .stale = coordinator.receiveWatchAcknowledgement(acknowledgement, source: "test") else {
            Issue.record("A running Watch ack for another identity must be rejected")
            return
        }
        #expect(coordinator.currentTransaction?.sessionID == request.candidateSessionID)
        #expect(coordinator.phase.name == "waitingForWatchAcknowledgement")
    }

    @Test func watchGeneratedAuthoritativeIDAckCannotReplaceCanonicalCandidate() {
        let coordinator = makeCoordinator()
        let request = GymWorkoutStartRequest(
            routineID: UUID(),
            routineRevision: 1,
            workoutKind: .routine,
            activityTypeRawValue: 50,
            locationTypeRawValue: 1
        )
        _ = coordinator.beginCrossDeviceGymStart(request: request, source: "test")
        _ = coordinator.markWatchLaunchSubmitted(requestID: request.requestID, source: "test")
        _ = coordinator.markWaitingForWatchAcknowledgement(requestID: request.requestID, source: "test")

        let provisionalWatchID = UUID()
        let acknowledgement = GymWorkoutStartAcknowledgement(
            requestID: request.requestID,
            candidateSessionID: request.candidateSessionID,
            authoritativeSessionID: provisionalWatchID,
            sessionState: .running,
            mirroringState: .unavailableWatchRecording,
            isWatchGeneratedSessionID: true
        )

        #expect(coordinator.receiveWatchAcknowledgement(acknowledgement, source: "test") == .stale(requestID: request.requestID))
        #expect(coordinator.currentTransaction?.sessionID == request.candidateSessionID)
        #expect(coordinator.currentTransaction?.authoritativeSessionID == request.candidateSessionID)
        #expect(coordinator.currentTransaction?.authoritativeSessionID != provisionalWatchID)
        #expect(coordinator.phase.name == "waitingForWatchAcknowledgement")
    }

    @Test func controllerWaitCancellationPolicyIgnoresStaleAndLateAcknowledgements() {
        let transaction = PulsarWorkoutStartTransaction(
            sessionID: UUID(),
            kind: .watchGym,
            source: "test",
            workoutType: "routine",
            requestedAt: Date()
        )
        let requestID = UUID()

        #expect(GymCrossDeviceStartController.shouldCancelAcknowledgementWait(
            for: .accepted(transaction),
            duplicateIsVerified: false
        ))
        #expect(GymCrossDeviceStartController.shouldCancelAcknowledgementWait(
            for: .duplicate,
            duplicateIsVerified: true
        ))
        #expect(!GymCrossDeviceStartController.shouldCancelAcknowledgementWait(
            for: .duplicate,
            duplicateIsVerified: false
        ))
        #expect(!GymCrossDeviceStartController.shouldCancelAcknowledgementWait(
            for: .stale(requestID: requestID),
            duplicateIsVerified: false
        ))
        #expect(!GymCrossDeviceStartController.shouldCancelAcknowledgementWait(
            for: .lateAfterFallback(requestID: requestID),
            duplicateIsVerified: false
        ))
        #expect(!GymCrossDeviceStartController.shouldCancelAcknowledgementWait(
            for: .rejectedNoMatchingRequest(requestID: requestID),
            duplicateIsVerified: false
        ))
    }

    @Test func idleCoordinatorDoesNotDeferForegroundHealthRefresh() {
        let coordinator = makeCoordinator()
        #expect(coordinator.shouldDeferForegroundHealthRefresh == false)
    }

    @Test func inFlightGymStartOwnsItsSessionBeforeMirrorArrival() {
        let coordinator = makeCoordinator()
        let request = GymWorkoutStartRequest(
            routineID: UUID(),
            routineRevision: 1,
            workoutKind: .routine,
            activityTypeRawValue: 50,
            locationTypeRawValue: 1
        )

        _ = coordinator.beginCrossDeviceGymStart(request: request, source: "test.startupRace")
        _ = coordinator.markWatchLaunchSubmitted(requestID: request.requestID, source: "test.startupRace")

        #expect(coordinator.matchesCurrentInFlightSession(request.candidateSessionID))
        #expect(!coordinator.matchesCurrentInFlightSession(UUID()))
        #expect(coordinator.shouldDeferForegroundHealthRefresh)
    }

    @Test func adoptsWatchOriginatedWorkoutWithoutAnIPhoneStartRequest() {
        let coordinator = makeCoordinator()
        let sessionID = UUID()

        #expect(coordinator.adoptRemoteActiveWorkout(
            sessionID: sessionID,
            kind: .watchGym,
            workoutType: "routine",
            authority: .freshWatchConnectivity,
            source: "test.watchState"
        ) == .applied)
        #expect(coordinator.phase.name == "active")
        #expect(coordinator.currentTransaction?.sessionID == sessionID)
        #expect(coordinator.currentTransaction?.authoritativeSessionID == sessionID)
        #expect(coordinator.didReachActive(sessionID: sessionID))
        #expect(coordinator.isCrossDeviceGymStartVerified)
    }

    @Test func unverifiedRemoteWorkoutCannotReplaceAnUnfinishedStart() {
        let coordinator = makeCoordinator()
        let staleSessionID = UUID()
        let watchSessionID = UUID()
        _ = coordinator.requestStart(
            sessionID: staleSessionID,
            kind: .gym,
            source: "test",
            workoutType: "gym"
        )

        #expect(coordinator.adoptRemoteActiveWorkout(
            sessionID: watchSessionID,
            kind: .watchGym,
            workoutType: "routine",
            authority: .freshWatchConnectivity,
            source: "test.watchState"
        ) == .rejectedConflict(existingSessionID: staleSessionID))
        #expect(coordinator.currentTransaction?.sessionID == staleSessionID)

        let otherWatchSessionID = UUID()
        #expect(coordinator.adoptRemoteActiveWorkout(
            sessionID: otherWatchSessionID,
            kind: .watchGym,
            workoutType: "routine",
            authority: .freshWatchConnectivity,
            source: "test.conflict"
        ) == .rejectedConflict(existingSessionID: staleSessionID))
        #expect(coordinator.currentTransaction?.sessionID == staleSessionID)
    }

    @Test func matchingRemoteWorkoutWaitsForWatchVerification() {
        let coordinator = makeCoordinator()
        let sessionID = UUID()
        _ = coordinator.requestStart(
            sessionID: sessionID,
            kind: .watchGym,
            source: "test",
            workoutType: "routine"
        )

        #expect(coordinator.adoptRemoteActiveWorkout(
            sessionID: sessionID,
            kind: .watchGym,
            workoutType: "routine",
            authority: .freshWatchConnectivity,
            source: "test.prelaunch"
        ) == .rejectedIllegalTransition(from: "preparing", to: "adoptRemoteActive"))
        #expect(coordinator.phase.name == "preparing")
    }

    @Test func prelaunchGymPlaceholderMapsToStartingAndCannotRestore() {
        let now = Date()
        let state = ActiveGymWorkoutState(
            sessionId: UUID(),
            routineId: UUID(),
            routineName: "Push",
            routineEmoji: "🏋️",
            workoutKind: .routine,
            startedFrom: .iPhoneRequestedWatchStart,
            startedAt: now,
            elapsedSeconds: 0,
            currentExerciseIndex: 0,
            currentSetIndex: 0,
            totalExercises: 0,
            totalSets: 0,
            completedSets: 0,
            currentHeartRate: nil,
            averageHeartRate: nil,
            maxHeartRate: nil,
            activeEnergyKilocalories: nil,
            restRemainingSeconds: nil,
            restTotalSeconds: nil,
            isHealthKitEnabled: true,
            healthKitStatusMessage: "Opening on Apple Watch...",
            isFinished: false,
            updatedAt: now,
            exercises: [],
            requestID: UUID(),
            lifecycleGeneration: 1,
            isLaunchPlaceholder: true
        )

        #expect(PulsarActiveWorkoutSyncState(gymState: state).phase == .starting)
        #expect(!PulsarWatchSynchronizedGymReconciliation.shouldRestoreCachedActiveGym(
            state,
            platform: .iPhone,
            isTombstoned: false
        ))
    }

    @Test func foregroundSyncAbortsWhenWorkoutTakesPriority() {
        #expect(!HomeViewModel.shouldAbortSync(
            startRevision: 4,
            currentRevision: 4,
            workoutStartupInProgress: false,
            taskIsCancelled: false
        ))
        #expect(HomeViewModel.shouldAbortSync(
            startRevision: 4,
            currentRevision: 5,
            workoutStartupInProgress: false,
            taskIsCancelled: false
        ))
        #expect(HomeViewModel.shouldAbortSync(
            startRevision: 5,
            currentRevision: 5,
            workoutStartupInProgress: true,
            taskIsCancelled: false
        ))
        #expect(HomeViewModel.shouldAbortSync(
            startRevision: 5,
            currentRevision: 5,
            workoutStartupInProgress: false,
            taskIsCancelled: true
        ))
    }
}
