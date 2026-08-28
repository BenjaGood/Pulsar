//
//  WorkoutOwnershipPhase5Tests.swift
//  PulsarTests
//

import Combine
import Foundation
import Testing
@testable import Pulsar

@MainActor
struct WorkoutOwnershipPhase5Tests {
    private func makeCoordinator() -> PulsarWorkoutStartCoordinator {
        let coordinator = PulsarWorkoutStartCoordinator()
        coordinator.resetForTesting()
        return coordinator
    }

    private func finalizePendingRootDismissal(
        _ manager: PulsarActiveWorkoutManager,
        reason: String = "testRootSheetOnDismiss"
    ) {
        guard let dismissal = manager.consumePendingDismissedCurrentWorkout() else {
            Issue.record("Expected a pending dismissal for the current workout")
            return
        }
        #expect(manager.finalizeWorkoutPresentationDismissal(dismissal, reason: reason))
    }

    // MARK: - Acceptance: Done only after reached-active + completed

    @Test func timeoutIsFailedNotCompletedOrSummaryEligible() {
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

        guard case .reconcilingRemote = coordinator.phase else {
            Issue.record("Timeout after Watch launch must keep remote state unknown, not fail")
            return
        }
        #expect(coordinator.presentationPolicy == .loading)
        #expect(!coordinator.canPresentSummary(sessionID: request.candidateSessionID))
        #expect(coordinator.presentationPolicy != .summaryEligible)
        #expect(coordinator.phase.blocksNewWatchPrimaryIdentity)
    }

    @Test func summaryRequiresDidReachActiveEvenAfterSessionEnds() {
        let coordinator = makeCoordinator()
        let sessionID = UUID()

        _ = coordinator.requestStart(sessionID: sessionID, kind: .gym, source: "test", workoutType: "gym")
        // End before activation — preparing path collapses to idle, not summary-eligible.
        coordinator.markSessionEnded(sessionID: sessionID, reason: "cancelledBeforeActive")
        #expect(coordinator.phase == .idle)
        #expect(!coordinator.canPresentSummary(sessionID: sessionID))
    }

    // MARK: - Acceptance: double Start → one attempt

    @Test func rapidDoubleStartIsDeduped() {
        let coordinator = makeCoordinator()
        let sessionID = UUID()

        guard case .granted = coordinator.requestStart(
            sessionID: sessionID,
            kind: .watchGym,
            source: "test",
            workoutType: "routine"
        ) else {
            Issue.record("Expected first start granted")
            return
        }

        let second = coordinator.requestStart(
            sessionID: sessionID,
            kind: .watchGym,
            source: "test",
            workoutType: "routine"
        )
        guard case .duplicateStart = second else {
            Issue.record("Expected duplicate for same in-flight session")
            return
        }

        let conflicting = coordinator.requestStart(
            sessionID: UUID(),
            kind: .run(.running),
            source: "test",
            workoutType: "running"
        )
        guard case .rejectedConflict = conflicting else {
            Issue.record("Expected conflict while first start in progress")
            return
        }
        #expect(coordinator.phase.isInProgress)
    }

    // MARK: - Acceptance: stale finished cannot complete a new session

    @Test func mirrorPresentationNeverTreatsMissingLiveAsFinished() {
        #expect(
            GymWatchMirroredWorkoutView.presentationContent(
                hasMatchingLiveState: false,
                crossDevicePhase: .waitingForWatchAcknowledgement,
                hasFinishedSummary: true
            ) == .pending
        )
        #expect(
            GymWatchMirroredWorkoutView.presentationContent(
                hasMatchingLiveState: false,
                crossDevicePhase: .active,
                hasFinishedSummary: false
            ) == .connecting
        )
        #expect(
            GymWatchMirroredWorkoutView.presentationContent(
                hasMatchingLiveState: false,
                crossDevicePhase: .active,
                hasFinishedSummary: true
            ) == .finishedSummary
        )
        #expect(
            GymWatchMirroredWorkoutView.presentationContent(
                hasMatchingLiveState: false,
                crossDevicePhase: .active,
                hasFinishedSummary: false,
                hasAttachedLiveMirror: false,
                hasConfirmedTerminal: true
            ) == .terminal
        )
        #expect(
            !GymWatchMirroredWorkoutView.canPresentFinishedSummary(
                expectedSessionID: UUID(),
                finishedSessionID: UUID(),
                isSummaryEligible: true
            )
        )
    }

    @Test func prepareForNewGymStartClearsStaleFinishedState() {
        let store = PulsarWatchConnectivitySyncStore.shared
        let staleSessionID = UUID()
        let newSessionID = UUID()
        let now = Date()

        let finished = ActiveGymWorkoutState(
            sessionId: staleSessionID,
            routineId: staleSessionID,
            routineName: "Stale Pull",
            routineEmoji: "💪",
            workoutKind: .routine,
            startedFrom: .appleWatch,
            startedAt: now.addingTimeInterval(-600),
            elapsedSeconds: 600,
            currentExerciseIndex: 0,
            currentSetIndex: 0,
            totalExercises: 1,
            totalSets: 1,
            completedSets: 1,
            currentHeartRate: nil,
            averageHeartRate: nil,
            maxHeartRate: nil,
            activeEnergyKilocalories: nil,
            restRemainingSeconds: nil,
            restTotalSeconds: nil,
            isHealthKitEnabled: true,
            healthKitStatusMessage: nil,
            isFinished: true,
            updatedAt: now,
            exercises: []
        )
        _ = store.storeActiveGymState(finished, broadcast: false, reason: "phase5SeedFinished")
        store.clearActiveGymState(reason: "phase5MoveToFinishedCache", broadcastEndedState: false)
        // finished may live in lastFinishedGymState after clear; prepare must wipe it for a new session.
        store.prepareForNewGymStart(sessionID: newSessionID, reason: "phase5NewStart")

        #expect(store.lastFinishedGymState?.sessionId != staleSessionID || store.lastFinishedGymState == nil)
        #expect(
            !GymWatchMirroredWorkoutView.canPresentFinishedSummary(
                expectedSessionID: newSessionID,
                finishedSessionID: staleSessionID,
                isSummaryEligible: true
            )
        )
    }

    // MARK: - Acceptance: second workout after first

    @Test func newStartClearsPreviousSummaryEligibility() {
        let coordinator = makeCoordinator()
        let first = UUID()
        let second = UUID()

        _ = coordinator.requestStart(sessionID: first, kind: .gym, source: "test", workoutType: "gym")
        coordinator.markActivated(sessionID: first, workoutType: "gym", source: "test")
        coordinator.markSessionEnded(sessionID: first, reason: "finished")
        #expect(coordinator.canPresentSummary(sessionID: first))

        guard case .granted = coordinator.requestStart(
            sessionID: second,
            kind: .run(.running),
            source: "test",
            workoutType: "running"
        ) else {
            Issue.record("Expected second start granted")
            return
        }
        #expect(!coordinator.canPresentSummary(sessionID: first))
        #expect(!coordinator.canPresentSummary(sessionID: second))
        #expect(coordinator.presentationPolicy == .loading)
    }

    @Test func endThenSummaryConsumeThenSecondStart() {
        let coordinator = makeCoordinator()
        let first = UUID()
        let second = UUID()

        _ = coordinator.requestStart(sessionID: first, kind: .gym, source: "test", workoutType: "gym")
        coordinator.markActivated(sessionID: first, workoutType: "gym", source: "test")
        coordinator.markSessionEnded(sessionID: first, reason: "finished")
        #expect(coordinator.presentationPolicy == .summaryEligible)

        coordinator.acknowledgeTerminal(sessionID: first, reason: "summaryConsumed")
        #expect(coordinator.phase == .idle)
        #expect(!coordinator.canPresentSummary(sessionID: first))

        guard case .granted = coordinator.requestStart(
            sessionID: second,
            kind: .gym,
            source: "test",
            workoutType: "gym"
        ) else {
            Issue.record("Expected second start after acknowledge")
            return
        }
        coordinator.markActivated(sessionID: second, workoutType: "gym", source: "test")
        #expect(coordinator.canPresentSummary(sessionID: second))
        #expect(!coordinator.canPresentSummary(sessionID: first))
    }

    // MARK: - Integration: gym ack path

    @Test func gymStartAckActiveSummaryPath() {
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
        #expect(coordinator.presentationPolicy == .loading)
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
            Issue.record("Expected accepted acknowledgement")
            return
        }
        #expect(coordinator.isCrossDeviceGymStartVerified)

        coordinator.markActivated(
            sessionID: request.candidateSessionID,
            workoutType: request.workoutKind.rawValue,
            source: "test"
        )
        #expect(coordinator.presentationPolicy == .live)

        coordinator.markSessionEnded(sessionID: request.candidateSessionID, reason: "watchFinished")
        #expect(coordinator.presentationPolicy == .summaryEligible)
        #expect(coordinator.canPresentSummary(sessionID: request.candidateSessionID))
    }

    // MARK: - AWM presentation adapter gates

    @Test func activeWorkoutManagerRefusesLiveWithoutLifecycleAuthority() {
        PulsarActiveWorkoutManager.shared.resetForTesting()
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
        let manager = PulsarActiveWorkoutManager()
        let sessionID = UUID()

        let opened = manager.reconcileActiveWorkoutPresentation(
            route: .watchGym,
            sessionID: sessionID,
            phase: "active",
            reason: "phase5Unauthorized"
        )
        #expect(!opened)
        #expect(manager.activeWorkout == nil)
        #expect(manager.presentation == .hidden)

        PulsarWorkoutStartCoordinator.shared.markSessionReachedActive(
            sessionID: sessionID,
            source: "phase5Authorize"
        )
        let authorized = manager.reconcileActiveWorkoutPresentation(
            route: .watchGym,
            sessionID: sessionID,
            phase: "active",
            reason: "phase5Authorized"
        )
        #expect(authorized)
        #expect(manager.activeWorkout?.sessionID == sessionID)
        #expect(manager.presentation == .expanded(sessionID))

        PulsarActiveWorkoutManager.shared.resetForTesting()
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
    }

    @Test func activeWorkoutManagerBlocksSummaryWithoutDidReachActive() {
        PulsarActiveWorkoutManager.shared.resetForTesting()
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
        let manager = PulsarActiveWorkoutManager()
        let sessionID = UUID()

        manager.presentWatchGymSummary(sessionID: sessionID)
        #expect(manager.presentedWorkout == nil)
        #expect(manager.presentation == .hidden)

        PulsarWorkoutStartCoordinator.shared.markSessionReachedActive(
            sessionID: sessionID,
            source: "phase5SummaryEligible"
        )
        manager.presentWatchGymSummary(sessionID: sessionID)
        #expect(manager.presentedWorkout == .watchGym)
        #expect(manager.presentation == .expanded(sessionID))

        PulsarActiveWorkoutManager.shared.resetForTesting()
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
    }

    @Test func watchGymMinimizeReopenAndTerminalClearKeepOneSessionIdentity() {
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
        let manager = PulsarActiveWorkoutManager()
        let sessionID = UUID()
        PulsarWorkoutStartCoordinator.shared.markSessionReachedActive(
            sessionID: sessionID,
            source: "phase5WatchGymPresentation"
        )

        #expect(manager.reconcileActiveWorkoutPresentation(
            route: .watchGym,
            sessionID: sessionID,
            phase: "active",
            reason: "initialMirror"
        ))
        manager.minimizeWatchGymWorkout(sessionID: sessionID)
        #expect(manager.activeWorkout?.sessionID == sessionID)
        #expect(manager.presentationState == .minimizing(sessionID))
        #expect(manager.presentation == .expanded(sessionID))
        #expect(manager.presentedWorkout == nil)

        finalizePendingRootDismissal(manager)
        #expect(manager.presentation == .minimized(sessionID))
        #expect(manager.presentedWorkout == nil)

        manager.presentWatchGymWorkout(sessionID: sessionID)
        #expect(manager.activeWorkout?.sessionID == sessionID)
        #expect(manager.presentation == .expanded(sessionID))
        #expect(manager.presentedWorkout == .watchGym)

        manager.clearWatchGymWorkout(
            sessionID: sessionID,
            phase: "ended",
            source: "healthKit",
            reason: "terminalMirror"
        )
        #expect(manager.activeWorkout == nil)
        #expect(manager.presentation == .hidden)
        #expect(manager.presentedWorkout == nil)

        PulsarWorkoutStartCoordinator.shared.resetForTesting()
    }

    @Test func watchGymMinimizeRejectsMismatchedTransportIdentity() {
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
        let manager = PulsarActiveWorkoutManager()
        let canonicalSessionID = UUID()
        let advisorySessionID = UUID()
        PulsarWorkoutStartCoordinator.shared.markSessionReachedActive(
            sessionID: canonicalSessionID,
            source: "phase5CanonicalMinimize"
        )
        #expect(manager.reconcileActiveWorkoutPresentation(
            route: .watchGym,
            sessionID: canonicalSessionID,
            phase: "active",
            reason: "authoritativeMirror"
        ))

        manager.minimizeWatchGymWorkout(sessionID: advisorySessionID)

        #expect(manager.activeWorkout?.sessionID == canonicalSessionID)
        #expect(manager.presentation == .expanded(canonicalSessionID))
        #expect(manager.presentedWorkout == .watchGym)
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
    }

    @Test func delayedDismissalRemainsBoundToItsOriginalSession() {
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
        let manager = PulsarActiveWorkoutManager()
        let firstSessionID = UUID()
        let secondSessionID = UUID()

        PulsarWorkoutStartCoordinator.shared.markSessionReachedActive(
            sessionID: firstSessionID,
            source: "dismissalFirst"
        )
        #expect(manager.reconcileActiveWorkoutPresentation(
            route: .watchGym,
            sessionID: firstSessionID,
            phase: "active",
            reason: "dismissalFirst"
        ))
        manager.presentedWorkout = nil

        PulsarWorkoutStartCoordinator.shared.markSessionReachedActive(
            sessionID: secondSessionID,
            source: "dismissalSecond"
        )
        #expect(manager.reconcileActiveWorkoutPresentation(
            route: .watchGym,
            sessionID: secondSessionID,
            phase: "active",
            reason: "dismissalSecond"
        ))

        let dismissal = manager.consumePendingDismissedWorkout()
        #expect(dismissal?.sessionID == firstSessionID)
        #expect(dismissal?.workout == .watchGym)
        #expect(dismissal.map(manager.isCurrentWorkout) == false)
        #expect(manager.activeWorkout?.sessionID == secondSessionID)
        #expect(manager.presentation == .expanded(secondSessionID))

        PulsarWorkoutStartCoordinator.shared.resetForTesting()
    }

    @Test func currentDismissalIsNotMaskedByQueuedStaleSession() {
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
        let manager = PulsarActiveWorkoutManager()
        let firstSessionID = UUID()
        let secondSessionID = UUID()

        PulsarWorkoutStartCoordinator.shared.markSessionReachedActive(
            sessionID: firstSessionID,
            source: "queuedDismissalFirst"
        )
        #expect(manager.reconcileActiveWorkoutPresentation(
            route: .watchGym,
            sessionID: firstSessionID,
            phase: "active",
            reason: "queuedDismissalFirst"
        ))
        manager.presentedWorkout = nil

        PulsarWorkoutStartCoordinator.shared.markSessionReachedActive(
            sessionID: secondSessionID,
            source: "queuedDismissalSecond"
        )
        #expect(manager.reconcileActiveWorkoutPresentation(
            route: .watchGym,
            sessionID: secondSessionID,
            phase: "active",
            reason: "queuedDismissalSecond"
        ))
        manager.updatePresentedWorkoutItemFromSheet(nil)

        let currentDismissal = manager.consumePendingDismissedCurrentWorkout()
        #expect(currentDismissal?.sessionID == secondSessionID)
        #expect(currentDismissal?.workout == .watchGym)
        #expect(manager.consumePendingDismissedWorkout() == nil)
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
    }

    @Test func presentationRouteAndModePublishAsOneSessionScopedState() {
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
        let manager = PulsarActiveWorkoutManager()
        let sessionID = UUID()
        PulsarWorkoutStartCoordinator.shared.markSessionReachedActive(
            sessionID: sessionID,
            source: "atomicPresentation"
        )
        var states: [PulsarActiveWorkoutPresentationState] = []
        let observation = manager.$presentationState
            .dropFirst()
            .sink { states.append($0) }

        #expect(manager.reconcileActiveWorkoutPresentation(
            route: .watchGym,
            sessionID: sessionID,
            phase: "active",
            reason: "atomicPresentation"
        ))

        let item = manager.presentedWorkoutItem
        #expect(item?.id == sessionID)
        #expect(item?.sessionID == sessionID)
        #expect(item?.workout == .watchGym)
        #expect(manager.presentation == .expanded(sessionID))
        #expect(states == [.expanded(PulsarPresentedWorkoutItem(workout: .watchGym, sessionID: sessionID))])
        withExtendedLifetime(observation) {}
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
    }

    @Test func launchCoverHandoffAttachesCanonicalSessionBeforePublishingSheet() {
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
        let manager = PulsarActiveWorkoutManager()
        let sessionID = UUID()
        PulsarWorkoutStartCoordinator.shared.markSessionReachedActive(
            sessionID: sessionID,
            source: "deferredPresentation"
        )
        var states: [PulsarActiveWorkoutPresentationState] = []
        let observation = manager.$presentationState
            .dropFirst()
            .sink { states.append($0) }

        manager.beginRootPresentationHandoff(reason: "fitnessCoverPresented")
        let openedBeforeDismiss = manager.reconcileActiveWorkoutPresentation(
            route: .watchGym,
            sessionID: sessionID,
            phase: "active",
            reason: "mirrorAttached"
        )

        #expect(!openedBeforeDismiss)
        #expect(manager.activeWorkout?.sessionID == sessionID)
        #expect(manager.presentation == .expanded(sessionID))
        let pendingItem = PulsarPresentedWorkoutItem(workout: .watchGym, sessionID: sessionID)
        #expect(manager.presentationState == .handoffPending(pendingItem))
        #expect(manager.presentedWorkoutItem == nil)
        #expect(states == [.handoffPending(pendingItem)])

        let openedAfterDismiss = manager.completeRootPresentationHandoff(
            reason: "fitnessCoverDismissed"
        )
        #expect(openedAfterDismiss)
        #expect(manager.presentation == .expanded(sessionID))
        #expect(manager.presentedWorkoutItem?.id == sessionID)
        #expect(states == [
            .handoffPending(pendingItem),
            .expanded(PulsarPresentedWorkoutItem(workout: .watchGym, sessionID: sessionID))
        ])
        withExtendedLifetime(observation) {}
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
    }

    @Test func watchGymLaunchCoverKeepsLaunchOwnedWithoutRootSheet() {
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
        let manager = PulsarActiveWorkoutManager()
        let sessionID = UUID()
        PulsarWorkoutStartCoordinator.shared.markSessionReachedActive(
            sessionID: sessionID,
            source: "launchCoverOwnership"
        )

        manager.beginLaunchCoverOwnership(reason: "crossDeviceWatchGymLaunchCover")
        #expect(!manager.reconcileActiveWorkoutPresentation(
            route: .watchGym,
            sessionID: sessionID,
            phase: "active",
            reason: "GymCrossDeviceStartVerified"
        ))
        #expect(manager.activeWorkout?.sessionID == sessionID)
        #expect(manager.presentationState == .launchOwned(sessionID))
        #expect(manager.presentedWorkoutItem == nil)
        #expect(manager.presentation == .expanded(sessionID))
        #expect(!manager.completeRootPresentationHandoff(reason: "coverMustNotHandoff"))

        manager.minimizeWatchGymWorkout(sessionID: sessionID)
        #expect(manager.presentationState == .minimizing(sessionID))
        #expect(manager.reconcileLaunchOwnerDismissal(reason: "userMinimizedLaunchCover"))
        #expect(manager.presentation == .minimized(sessionID))
        #expect(manager.presentedWorkoutItem == nil)
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
    }

    @Test func runLaunchCoverHandoffDefersRootSheetUntilCoverDismissal() {
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
        let manager = PulsarActiveWorkoutManager()
        let sessionID = UUID()
        PulsarWorkoutStartCoordinator.shared.markSessionReachedActive(
            sessionID: sessionID,
            source: "deferredRunPresentation"
        )

        manager.beginRootPresentationHandoff(reason: "fitnessRunLaunchCover")
        #expect(!manager.reconcileActiveWorkoutPresentation(
            route: .run(.running),
            sessionID: sessionID,
            phase: "active",
            reason: "localRunAttached"
        ))

        let item = PulsarPresentedWorkoutItem(workout: .run(.running), sessionID: sessionID)
        #expect(manager.presentationState == .handoffPending(item))
        #expect(manager.presentedWorkoutItem == nil)
        #expect(manager.completeRootPresentationHandoff(reason: "runCoverDismissed"))
        #expect(manager.presentationState == .expanded(item))
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
    }

    @Test func cancelledLaunchCoverHandoffCannotExposeDeferredSheet() {
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
        let manager = PulsarActiveWorkoutManager()
        let sessionID = UUID()
        PulsarWorkoutStartCoordinator.shared.markSessionReachedActive(
            sessionID: sessionID,
            source: "cancelledDeferredPresentation"
        )

        manager.beginRootPresentationHandoff(reason: "fitnessCoverPresented")
        _ = manager.reconcileActiveWorkoutPresentation(
            route: .watchGym,
            sessionID: sessionID,
            phase: "active",
            reason: "mirrorAttached"
        )
        manager.cancelRootPresentationHandoff(reason: "userCancelled")

        #expect(!manager.completeRootPresentationHandoff(reason: "lateCoverDismiss"))
        #expect(manager.presentationState == .minimizing(sessionID))
        #expect(manager.reconcileLaunchOwnerDismissal(reason: "cancelledCoverDismissed"))
        #expect(manager.presentation == .minimized(sessionID))
        #expect(manager.presentedWorkoutItem == nil)

        #expect(!manager.reconcileActiveWorkoutPresentation(
            route: .watchGym,
            sessionID: sessionID,
            phase: "active",
            reason: "lateSameSessionPacket"
        ))
        manager.reconcilePresentationIntegrity(reason: "afterCancelledHandoff")
        #expect(manager.presentation == .minimized(sessionID))
        #expect(manager.presentedWorkoutItem == nil)
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
    }

    @Test func minimizingExpandedWatchGymWaitsForActualSheetDismissal() {
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
        let manager = PulsarActiveWorkoutManager()
        let sessionID = UUID()
        PulsarWorkoutStartCoordinator.shared.markSessionReachedActive(
            sessionID: sessionID,
            source: "atomicMinimize"
        )
        #expect(manager.reconcileActiveWorkoutPresentation(
            route: .watchGym,
            sessionID: sessionID,
            phase: "active",
            reason: "atomicMinimize"
        ))

        var states: [PulsarActiveWorkoutPresentationState] = []
        let observation = manager.$presentationState
            .dropFirst()
            .sink { states.append($0) }
        manager.minimizeWatchGymWorkout(sessionID: sessionID)

        #expect(states == [.minimizing(sessionID)])
        #expect(manager.presentationState == .minimizing(sessionID))
        #expect(manager.presentation == .expanded(sessionID))
        #expect(manager.presentedWorkoutItem == nil)

        finalizePendingRootDismissal(manager)
        #expect(states == [.minimizing(sessionID), .minimized(sessionID)])
        #expect(manager.presentation == .minimized(sessionID))
        withExtendedLifetime(observation) {}
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
    }

    @Test func duplicatePacketCannotReopenInteractivelyDismissingSheet() {
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
        let manager = PulsarActiveWorkoutManager()
        let sessionID = UUID()
        let item = PulsarPresentedWorkoutItem(workout: .watchGym, sessionID: sessionID)
        PulsarWorkoutStartCoordinator.shared.markSessionReachedActive(
            sessionID: sessionID,
            source: "interactiveDismissal"
        )
        #expect(manager.reconcileActiveWorkoutPresentation(
            route: .watchGym,
            sessionID: sessionID,
            phase: "active",
            reason: "interactiveDismissal"
        ))

        manager.updatePresentedWorkoutItemFromSheet(nil)
        #expect(manager.presentationState == .dismissing(item))
        #expect(manager.presentedWorkoutItem == nil)

        #expect(!manager.reconcileActiveWorkoutPresentation(
            route: .watchGym,
            sessionID: sessionID,
            phase: "active",
            reason: "duplicateDuringDismissal"
        ))
        #expect(manager.presentationState == .dismissing(item))
        finalizePendingRootDismissal(manager)
        #expect(manager.presentation == .minimized(sessionID))
        #expect(manager.presentedWorkoutItem == nil)
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
    }

    @Test func sameSessionConflictingRouteCannotMutateCanonicalWorkout() {
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
        let manager = PulsarActiveWorkoutManager()
        let sessionID = UUID()
        PulsarWorkoutStartCoordinator.shared.markSessionReachedActive(
            sessionID: sessionID,
            source: "conflictingRoute"
        )
        #expect(manager.reconcileActiveWorkoutPresentation(
            route: .watchGym,
            sessionID: sessionID,
            phase: "active",
            reason: "canonicalRoute"
        ))

        #expect(!manager.reconcileActiveWorkoutPresentation(
            route: .run(.running),
            sessionID: sessionID,
            phase: "active",
            reason: "conflictingRoute"
        ))
        #expect(manager.activeWorkout?.kind == .watchGym)
        #expect(manager.presentationState == .expanded(
            PulsarPresentedWorkoutItem(workout: .watchGym, sessionID: sessionID)
        ))
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
    }

    @Test func firstManagerAttachmentCannotContradictLifecycleKind() {
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
        defer { PulsarWorkoutStartCoordinator.shared.resetForTesting() }
        let manager = PulsarActiveWorkoutManager()
        let sessionID = UUID()
        guard case .granted = PulsarWorkoutStartCoordinator.shared.requestStart(
            sessionID: sessionID,
            kind: .watchGym,
            source: "lifecycleKindAuthority",
            workoutType: "gym"
        ) else {
            Issue.record("Expected lifecycle start authority")
            return
        }

        #expect(!manager.reconcileActiveWorkoutPresentation(
            route: .run(.running),
            sessionID: sessionID,
            phase: "active",
            reason: "contradictLifecycleKind"
        ))
        #expect(manager.activeWorkout == nil)
        #expect(manager.presentation == .hidden)
        #expect(manager.presentedWorkoutItem == nil)
    }

    @Test func staleRunMinimizeCannotReplaceCurrentCanonicalSession() {
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
        let manager = PulsarActiveWorkoutManager()
        let sessionID = UUID()
        PulsarWorkoutStartCoordinator.shared.markSessionReachedActive(
            sessionID: sessionID,
            source: "canonicalRunMinimize"
        )
        #expect(manager.reconcileActiveWorkoutPresentation(
            route: .run(.running),
            sessionID: sessionID,
            phase: "active",
            reason: "canonicalRunMinimize"
        ))

        manager.minimizeRunWorkout(.running, sessionID: UUID())

        #expect(manager.activeWorkout?.sessionID == sessionID)
        #expect(manager.activeWorkout?.kind == .run(.running))
        #expect(manager.presentation == .expanded(sessionID))
        #expect(manager.presentedWorkout == .run(.running))
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
    }

    @Test func localGymLaunchOwnerDismissalFallsBackToMiniPlayer() {
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
        let manager = PulsarActiveWorkoutManager()
        manager.startGymWorkout(
            routine: PulsarRoutine(name: "Launch-owned test", exercises: []),
            workoutWeightUnit: nil
        )

        guard let sessionID = manager.activeWorkout?.sessionID else {
            Issue.record("Expected a canonical local Gym session")
            return
        }
        #expect(manager.presentationState == .launchOwned(sessionID))
        #expect(manager.presentedWorkoutItem == nil)

        #expect(manager.reconcileLaunchOwnerDismissal(reason: "testOwnerDismissed"))
        #expect(manager.presentation == .minimized(sessionID))
        #expect(manager.presentedWorkoutItem == nil)
        #expect(manager.isGymWorkoutMinimized)
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
    }

    @Test func localGymExplicitMinimizeWaitsForLaunchCoverDismissal() {
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
        let manager = PulsarActiveWorkoutManager()
        manager.startGymWorkout(
            routine: PulsarRoutine(name: "Launch-owned minimize test", exercises: []),
            workoutWeightUnit: nil
        )

        guard let sessionID = manager.activeWorkout?.sessionID else {
            Issue.record("Expected a canonical local Gym session")
            return
        }
        manager.minimizeGymWorkout(sessionID: sessionID)

        #expect(manager.presentationState == .minimizing(sessionID))
        #expect(manager.presentation == .expanded(sessionID))
        #expect(manager.userMinimizedActiveWorkoutSessionID == nil)
        #expect(!manager.isGymWorkoutMinimized)

        #expect(manager.reconcileLaunchOwnerDismissal(reason: "testCoverOnDismiss"))
        #expect(manager.presentation == .minimized(sessionID))
        #expect(manager.userMinimizedActiveWorkoutSessionID == sessionID)
        #expect(manager.isGymWorkoutMinimized)
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
    }

    @Test func cancelledEmptyHandoffCannotDeferALaterWatchPresentation() {
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
        let manager = PulsarActiveWorkoutManager()
        let sessionID = UUID()

        manager.beginRootPresentationHandoff(reason: "legacyCoverBeforePublication")
        manager.cancelRootPresentationHandoff(reason: "legacyLaunchFailed")
        #expect(!manager.isRootPresentationHandoffDeferred)

        PulsarWorkoutStartCoordinator.shared.markSessionReachedActive(
            sessionID: sessionID,
            source: "postCancellationPresentation"
        )
        #expect(manager.reconcileActiveWorkoutPresentation(
            route: .watchGym,
            sessionID: sessionID,
            phase: "active",
            reason: "postCancellationPresentation"
        ))
        #expect(manager.presentationState == .expanded(
            PulsarPresentedWorkoutItem(workout: .watchGym, sessionID: sessionID)
        ))
        PulsarWorkoutStartCoordinator.shared.resetForTesting()
    }

    // MARK: - Mirror reject policy (consumer nil must not blind-end)

    @Test func unmatchedMirrorRejectStillRequiresIdentity() {
        #expect(
            GymMirroredSessionBridge.shouldEndMirroredSession(
                reason: "noConsumer",
                requestID: nil,
                sessionID: nil
            ) == false
        )
        #expect(
            GymMirroredSessionBridge.shouldEndMirroredSession(
                reason: "timeout",
                requestID: UUID(),
                sessionID: nil
            )
        )
    }

    @Test func gymMirrorPresentationGoesActiveWithoutWatchConnectivityState() {
        #expect(
            GymWatchMirroredWorkoutView.presentationContent(
                hasMatchingLiveState: false,
                crossDevicePhase: .mirroring,
                hasFinishedSummary: false,
                hasAttachedLiveMirror: true
            ) == .active
        )
        #expect(
            GymWatchMirroredWorkoutView.presentationContent(
                hasMatchingLiveState: false,
                crossDevicePhase: .watchSessionRunning,
                hasFinishedSummary: true,
                hasAttachedLiveMirror: false
            ) == .pending
        )
        #expect(
            GymWatchMirroredWorkoutView.presentationContent(
                hasMatchingLiveState: false,
                crossDevicePhase: .failed(.watchNotReachable, canRetry: true),
                hasFinishedSummary: true,
                hasAttachedLiveMirror: true,
                hasConfirmedTerminal: true
            ) == .finishedSummary
        )
    }

    @Test func gymMirrorMetricsOverlayHealthKitValuesOntoWatchConnectivityState() {
        let startedAt = Date().addingTimeInterval(-90)
        let base = ActiveGymWorkoutState(
            sessionId: UUID(),
            routineId: UUID(),
            routineName: "Push",
            routineEmoji: "🏋️",
            workoutKind: .routine,
            startedFrom: .iPhoneRequestedWatchStart,
            startedAt: startedAt,
            elapsedSeconds: 12,
            currentExerciseIndex: 0,
            currentSetIndex: 0,
            totalExercises: 1,
            totalSets: 1,
            completedSets: 0,
            currentHeartRate: nil,
            averageHeartRate: nil,
            maxHeartRate: nil,
            activeEnergyKilocalories: nil,
            restRemainingSeconds: nil,
            restTotalSeconds: nil,
            isHealthKitEnabled: true,
            healthKitStatusMessage: nil,
            isFinished: false,
            updatedAt: Date(),
            exercises: []
        )
        let snapshot = GymMirroredSessionSnapshot(
            isAttached: true,
            isLive: true,
            sessionID: base.sessionId,
            startedAt: startedAt,
            currentHeartRate: 148,
            averageHeartRate: 132,
            maxHeartRate: 160,
            activeEnergyKilocalories: 44
        )
        let overlaid = GymWatchMirroredWorkoutView.overlayMirroredMetrics(base, from: snapshot)
        #expect(overlaid.currentHeartRate == 148)
        #expect(overlaid.averageHeartRate == 132)
        #expect(overlaid.maxHeartRate == 160)
        #expect(overlaid.activeEnergyKilocalories == 44)
        #expect(overlaid.elapsedSeconds >= 12)
        #expect(overlaid.routineName == "Push")

        let fallback = GymWatchMirroredWorkoutView.fallbackLiveState(
            sessionID: base.sessionId,
            snapshot: snapshot
        )
        #expect(fallback.sessionId == base.sessionId)
        #expect(fallback.exercises.isEmpty)
        #expect(fallback.currentHeartRate == 148)
        #expect(!fallback.isFinished)
        #expect(GymWatchMirroredWorkoutView.routineDisplayMode(
            for: fallback,
            expectedSessionID: fallback.sessionId
        ) == .routinePending)
        #expect(GymWatchMirroredWorkoutView.currentExerciseTitle(for: fallback) == "Loading Routine…")
        #expect(fallback.exerciseProgressText == "Loading routine…")
        #expect(GymWatchMirroredWorkoutView.progressFraction(for: fallback) == 0)

        var freeWorkout = fallback
        freeWorkout.workoutKind = .freeWorkout
        #expect(GymWatchMirroredWorkoutView.routineDisplayMode(
            for: freeWorkout,
            expectedSessionID: freeWorkout.sessionId
        ) == .openGym)
        #expect(GymWatchMirroredWorkoutView.currentExerciseTitle(for: freeWorkout) == "Open Gym")
        #expect(freeWorkout.exerciseProgressText == "Open workout")
        #expect(GymWatchMirroredWorkoutView.progressFraction(for: freeWorkout) == 1)
    }

    @Test func confirmedFinishRetainsEligibleSummaryUntilDismissal() {
        #expect(PulsarConfirmedGymFinishDisposition.resolve(
            isCurrentWatchGym: true,
            isSummaryEligible: true
        ) == .retainForSummary)
        #expect(PulsarConfirmedGymFinishDisposition.resolve(
            isCurrentWatchGym: true,
            isSummaryEligible: false
        ) == .clearNeverActive)
        #expect(PulsarConfirmedGymFinishDisposition.resolve(
            isCurrentWatchGym: false,
            isSummaryEligible: true
        ) == .ignore)
        #expect(PulsarConfirmedGymFinishDisposition.resolve(
            isCurrentWatchGym: false,
            isSummaryEligible: false
        ) == .ignore)
    }
}
