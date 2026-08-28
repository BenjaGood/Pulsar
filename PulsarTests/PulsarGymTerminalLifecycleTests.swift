//
//  PulsarGymTerminalLifecycleTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

@MainActor
struct PulsarGymTerminalLifecycleTests {
    private var store: PulsarWatchConnectivitySyncStore {
        PulsarWatchConnectivitySyncStore.shared
    }

    private var coordinator: PulsarWorkoutStartCoordinator {
        PulsarWorkoutStartCoordinator.shared
    }

    private func resetTerminalFixtures(sessionID: UUID) {
        coordinator.resetForTesting()
        PulsarActiveWorkoutManager.shared.resetForTesting()
        store.prepareForNewGymStart(sessionID: sessionID, reason: "terminalTestReset")
        store.clearActiveGymState(reason: "terminalTestReset", broadcastEndedState: false)
    }

    private func gymState(
        sessionID: UUID,
        finished: Bool,
        updatedAt: Date = Date()
    ) -> ActiveGymWorkoutState {
        ActiveGymWorkoutState(
            sessionId: sessionID,
            routineId: sessionID,
            routineName: "Friday",
            routineEmoji: "🏋️",
            workoutKind: .routine,
            startedFrom: .iPhoneRequestedWatchStart,
            startedAt: updatedAt.addingTimeInterval(-600),
            elapsedSeconds: 600,
            currentExerciseIndex: 0,
            currentSetIndex: 0,
            totalExercises: 1,
            totalSets: 1,
            completedSets: finished ? 1 : 0,
            currentHeartRate: nil,
            averageHeartRate: nil,
            maxHeartRate: nil,
            activeEnergyKilocalories: nil,
            restRemainingSeconds: nil,
            restTotalSeconds: nil,
            isHealthKitEnabled: true,
            healthKitStatusMessage: nil,
            isFinished: finished,
            updatedAt: updatedAt,
            exercises: []
        )
    }

    private func seedLiveGym(_ sessionID: UUID) {
        _ = coordinator.requestStart(
            sessionID: sessionID,
            kind: .watchGym,
            source: "terminalTest",
            workoutType: "routine"
        )
        coordinator.markActivated(sessionID: sessionID, workoutType: "routine", source: "terminalTest")
        coordinator.markSessionReachedActive(sessionID: sessionID, source: "terminalTest")
        #expect(store.storeActiveGymState(gymState(sessionID: sessionID, finished: false), broadcast: false, reason: "terminalTestLive"))
    }

    @Test func iPhoneStartAndIPhoneEndCommitsTerminalOnce() {
        let sessionID = UUID()
        resetTerminalFixtures(sessionID: sessionID)
        seedLiveGym(sessionID)
        let acceptedBefore = store.acceptedGymTerminalCount

        #expect(coordinator.markSessionEnding(sessionID: sessionID, reason: "iPhoneUI") == .applied)
        #expect(coordinator.phase.name == "ending")
        #expect(coordinator.markSessionEnding(sessionID: sessionID, reason: "iPhoneUI") == .duplicate)

        #expect(store.storeActiveGymState(gymState(sessionID: sessionID, finished: true), broadcast: false, reason: "iPhoneEnd"))
        #expect(store.acceptedGymTerminalCount == acceptedBefore + 1)
        #expect(store.lastGymTerminalCommit?.accepted == true)
        #expect(store.activeGymState == nil)
        #expect(store.lastFinishedGymState?.sessionId == sessionID)
        #expect(coordinator.phase.name == "completed")

        #expect(store.storeActiveGymState(gymState(sessionID: sessionID, finished: true), broadcast: false, reason: "iPhoneEndDuplicate") == false)
        #expect(store.acceptedGymTerminalCount == acceptedBefore + 1)
        #expect(coordinator.phase.name == "completed")
    }

    @Test func iPhoneStartAndWatchEndUsesTheSameCanonicalTerminalPath() {
        let sessionID = UUID()
        resetTerminalFixtures(sessionID: sessionID)
        seedLiveGym(sessionID)
        let acceptedBefore = store.acceptedGymTerminalCount

        store.confirmGymFinishFromMirroredHealthKit(
            sessionID: sessionID,
            healthKitSessionStateRawValue: 5,
            confirmedAt: Date(),
            source: "watchEnd"
        )

        #expect(store.acceptedGymTerminalCount == acceptedBefore + 1)
        #expect(store.hasCommittedTerminalGymSession(sessionID))
        #expect(store.lastFinishedGymState?.sessionId == sessionID)
        #expect(coordinator.phase.name == "completed")
    }

    @Test func duplicateTerminalCallbacksAreIdempotent() {
        let sessionID = UUID()
        resetTerminalFixtures(sessionID: sessionID)
        seedLiveGym(sessionID)
        let acceptedBefore = store.acceptedGymTerminalCount
        let rejectedBefore = store.rejectedGymTerminalCount

        store.confirmGymFinishFromMirroredHealthKit(
            sessionID: sessionID,
            healthKitSessionStateRawValue: 5,
            confirmedAt: Date(),
            source: "first"
        )
        store.confirmGymFinishFromMirroredHealthKit(
            sessionID: sessionID,
            healthKitSessionStateRawValue: 5,
            confirmedAt: Date().addingTimeInterval(1),
            source: "second"
        )
        store.confirmGymFinishFromMirroredHealthKit(
            sessionID: sessionID,
            healthKitSessionStateRawValue: 5,
            confirmedAt: Date().addingTimeInterval(2),
            source: "third"
        )

        #expect(store.acceptedGymTerminalCount == acceptedBefore + 1)
        #expect(store.hasCommittedTerminalGymSession(sessionID))
        #expect(store.rejectedGymTerminalCount >= rejectedBefore)
    }

    @Test func healthKitEndAndWatchConnectivityAckDoNotDoubleCommit() {
        let sessionID = UUID()
        resetTerminalFixtures(sessionID: sessionID)
        seedLiveGym(sessionID)
        let acceptedBefore = store.acceptedGymTerminalCount

        store.confirmGymFinishFromMirroredHealthKit(
            sessionID: sessionID,
            healthKitSessionStateRawValue: 5,
            confirmedAt: Date(),
            source: "healthKit"
        )
        #expect(
            store.storeActiveGymState(
                gymState(sessionID: sessionID, finished: true),
                broadcast: false,
                reason: "watchConnectivity"
            ) == false
        )

        let endedWorkout = PulsarActiveWorkoutSyncState(gymState: gymState(sessionID: sessionID, finished: true))
        let decision = store.storeActiveWorkoutState(endedWorkout, broadcast: false, reason: "watchConnectivity.endedWorkout")
        #expect(decision.didApplySyncState == false)
        #expect(store.acceptedGymTerminalCount == acceptedBefore + 1)
    }

    @Test func launchCoverEndRetainsLaunchOwnedWithoutRootSheet() {
        let sessionID = UUID()
        resetTerminalFixtures(sessionID: sessionID)
        coordinator.markSessionReachedActive(sessionID: sessionID, source: "launchCoverEnd")
        let manager = PulsarActiveWorkoutManager()
        manager.beginLaunchCoverOwnership(reason: "launchCoverEnd")
        #expect(!manager.reconcileActiveWorkoutPresentation(
            route: .watchGym,
            sessionID: sessionID,
            phase: "active",
            reason: "launchCoverEnd"
        ))
        #expect(manager.presentationState == .launchOwned(sessionID))
        let commitsBefore = manager.presentationCommitCount
        let chromeBefore = PulsarRootLiveChromeIdentity.resolve(
            presentationState: manager.presentationState
        )

        manager.presentWatchGymSummary(sessionID: sessionID)
        manager.presentWatchGymSummary(sessionID: sessionID)

        #expect(manager.presentationState == .launchOwned(sessionID))
        #expect(manager.presentedWorkoutItem == nil)
        #expect(manager.activeWorkout?.phase == "finished")
        #expect(manager.retainedFinishedWatchGymSessionID == sessionID)
        #expect(manager.presentationCommitCount == commitsBefore)
        #expect(
            PulsarRootLiveChromeIdentity.resolve(presentationState: manager.presentationState)
                == chromeBefore
        )
        #expect(chromeBefore.showsOrion)
        #expect(!chromeBefore.showsMiniWorkout)
    }

    @Test func miniPlayerEndRestoresOrionExactlyOnceAfterClear() {
        let sessionID = UUID()
        resetTerminalFixtures(sessionID: sessionID)
        coordinator.markSessionReachedActive(sessionID: sessionID, source: "miniEnd")
        let manager = PulsarActiveWorkoutManager()
        #expect(manager.reconcileActiveWorkoutPresentation(
            route: .watchGym,
            sessionID: sessionID,
            phase: "active",
            reason: "miniEnd"
        ))
        manager.minimizeWatchGymWorkout(sessionID: sessionID)
        guard let dismissal = manager.consumePendingDismissedCurrentWorkout() else {
            Issue.record("Expected a pending dismissal for the minimized workout")
            return
        }
        #expect(manager.finalizeWorkoutPresentationDismissal(dismissal, reason: "miniEnd"))
        #expect(manager.presentationState == .minimized(sessionID))
        let miniChrome = PulsarRootLiveChromeIdentity.resolve(
            presentationState: manager.presentationState
        )
        #expect(miniChrome.showsMiniWorkout)
        #expect(!miniChrome.showsOrion)

        manager.presentWatchGymSummary(sessionID: sessionID)
        let summaryChrome = PulsarRootLiveChromeIdentity.resolve(
            presentationState: manager.presentationState
        )
        #expect(manager.presentation == .expanded(sessionID))
        #expect(!summaryChrome.showsMiniWorkout)
        #expect(!summaryChrome.showsOrion)

        manager.clearWatchGymWorkout(
            sessionID: sessionID,
            phase: "finished",
            source: "miniEnd",
            reason: "summaryDismissed"
        )
        let hiddenChrome = PulsarRootLiveChromeIdentity.resolve(
            presentationState: manager.presentationState
        )
        #expect(manager.presentationState == .hidden)
        #expect(hiddenChrome.showsOrion)
        #expect(!hiddenChrome.showsMiniWorkout)
        #expect(hiddenChrome.accessoryIdentity == .orion)
    }

    @Test func historyPersistenceIsDeferredOffTheTerminalCommitTurn() async {
        let sessionID = UUID()
        resetTerminalFixtures(sessionID: sessionID)
        seedLiveGym(sessionID)
        let history = PulsarGymWorkoutHistoryStore.shared
        let existedBefore = history.sessions.contains { $0.id == sessionID }

        store.confirmGymFinishFromMirroredHealthKit(
            sessionID: sessionID,
            healthKitSessionStateRawValue: 5,
            confirmedAt: Date(),
            source: "deferredHistory"
        )
        #expect(store.hasCommittedTerminalGymSession(sessionID))
        if !existedBefore {
            #expect(!history.sessions.contains { $0.id == sessionID })
        }

        await store.flushTerminalGymPersistenceForTesting()
        #expect(history.sessions.contains { $0.id == sessionID })
    }

    @Test func endingDoesNotChangeNativeTabAccessoryWhileLaunchCoverOwnsPresentation() {
        let sessionID = UUID()
        let launchOwned = PulsarRootLiveChromeIdentity.resolve(
            presentationState: .launchOwned(sessionID)
        )
        let hidden = PulsarRootLiveChromeIdentity.resolve(presentationState: .hidden)
        #expect(launchOwned == hidden)
        #expect(launchOwned.accessoryIdentity == .orion)
        #expect(PulsarConfirmedGymFinishDisposition.resolve(
            isCurrentWatchGym: true,
            isSummaryEligible: false,
            isLaunchCoverOwning: true
        ) == .retainForSummary)
        #expect(PulsarConfirmedGymFinishDisposition.resolve(
            isCurrentWatchGym: true,
            isSummaryEligible: true,
            alreadyRetainedSession: true
        ) == .ignore)
    }
}
