//
//  PulsarWatchSynchronizedGymReconciliationTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

struct PulsarWatchSynchronizedGymReconciliationTests {
    @Test func staleActiveGymStateAfterWatchLaunchDoesNotCreate() {
        #expect(
            !PulsarWatchSynchronizedGymReconciliation.shouldCreatePrimaryFromSynchronizedState(
                source: .activeGymStateSink,
                hasPrimarySession: false
            )
        )
        #expect(
            !PulsarWatchSynchronizedGymReconciliation.shouldRestoreCachedActiveGym(
                makeLiveCompanionGym(),
                platform: .watch,
                isTombstoned: false
            )
        )
    }

    @Test func restoredActiveStateWithoutPrimaryDoesNotCreate() {
        let incoming = makeLiveCompanionGym()
        #expect(
            !PulsarWatchSynchronizedGymReconciliation.shouldAdoptIncomingGymState(
                incoming: incoming,
                current: nil,
                platform: .watch,
                isIncomingFromCounterpart: true
            )
        )
        #expect(
            !PulsarWatchSynchronizedGymReconciliation.shouldCreatePrimaryFromSynchronizedState(
                source: .restore,
                hasPrimarySession: false
            )
        )
    }

    @Test func watchGymViewAppearAndRoutineSnapshotDoNotCreate() {
        #expect(
            !PulsarWatchSynchronizedGymReconciliation.shouldCreatePrimaryFromSynchronizedState(
                source: .watchGymViewAppear,
                hasPrimarySession: false
            )
        )
        #expect(
            !PulsarWatchSynchronizedGymReconciliation.shouldCreatePrimaryFromSynchronizedState(
                source: .routineSnapshotReceived,
                hasPrimarySession: false
            )
        )
        #expect(
            !PulsarWatchSynchronizedGymReconciliation.shouldCreatePrimaryFromSynchronizedState(
                source: .prelaunchHint,
                hasPrimarySession: false
            )
        )
    }

    @Test func freshCorrelatedPrelaunchDefinitionMayHydrateWatchStateButCannotCreatePrimary() {
        var prelaunch = makeLiveCompanionGym()
        prelaunch.isLaunchPlaceholder = true
        #expect(PulsarWatchSynchronizedGymReconciliation.shouldAdoptIncomingGymState(
            incoming: prelaunch,
            current: nil,
            platform: .watch,
            isIncomingFromCounterpart: true
        ))
        #expect(!PulsarWatchSynchronizedGymReconciliation.shouldCreatePrimaryFromSynchronizedState(
            source: .activeGymStateSink,
            hasPrimarySession: false
        ))
    }

    @Test func duplicateActiveGymStateNeverCreatesASecondPrimary() {
        #expect(
            !PulsarWatchSynchronizedGymReconciliation.shouldCreatePrimaryFromSynchronizedState(
                source: .activeGymStateSink,
                hasPrimarySession: true
            )
        )
        #expect(
            !PulsarWatchSynchronizedGymReconciliation.shouldCreatePrimaryFromSynchronizedState(
                source: .startWatchAppConfiguration,
                hasPrimarySession: true
            )
        )
    }

    @Test func terminalWorkoutCannotResurrectAfterRelaunch() {
        let finished = makeLiveCompanionGym(isFinished: true, generation: 2)
        #expect(
            !PulsarWatchSynchronizedGymReconciliation.shouldRestoreCachedActiveGym(
                finished,
                platform: .watch,
                isTombstoned: false
            )
        )
        #expect(
            !PulsarWatchSynchronizedGymReconciliation.shouldRestoreCachedActiveGym(
                makeLiveCompanionGym(),
                platform: .watch,
                isTombstoned: true
            )
        )

        var resurrected = finished
        resurrected.isFinished = false
        resurrected.lifecycleGeneration = 1
        #expect(
            !PulsarWatchSynchronizedGymReconciliation.shouldAdoptIncomingGymState(
                incoming: resurrected,
                current: finished,
                platform: .watch,
                isIncomingFromCounterpart: true
            )
        )
    }

    @Test func neitherPlatformPublishesPersistedGymAsLive() {
        let live = makeLiveCompanionGym()
        #expect(
            !PulsarWatchSynchronizedGymReconciliation.shouldRestoreCachedActiveGym(
                live,
                platform: .iPhone,
                isTombstoned: false
            )
        )
        #expect(
            !PulsarWatchSynchronizedGymReconciliation.shouldRestoreCachedActiveGym(
                live,
                platform: .watch,
                isTombstoned: false
            )
        )
    }

    @Test func onlyFreshRuntimeDeliveryCanAuthorizeUnownedGym() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var live = makeLiveCompanionGym()
        live.updatedAt = now.addingTimeInterval(-20)

        #expect(!PulsarWatchConnectivitySyncStore.shouldAcceptFreshCounterpartGym(
            live,
            reason: "activationHydration.workoutPriority",
            now: now
        ))
        #expect(PulsarWatchConnectivitySyncStore.shouldAcceptFreshCounterpartGym(
            live,
            reason: "receivedApplicationContext.workoutPriority",
            now: now
        ))

        live.updatedAt = now.addingTimeInterval(-91)
        #expect(!PulsarWatchConnectivitySyncStore.shouldAcceptFreshCounterpartGym(
            live,
            reason: "receivedApplicationContext",
            now: now
        ))
    }

    @Test func unavailableWatchCounterpartCannotBeUsedForTransfers() {
        #expect(!PulsarWatchConnectivitySyncStore.canUseiPhoneWatchCounterpart(
            isActivated: true,
            isPaired: true,
            isWatchAppInstalled: false
        ))
        #expect(!PulsarWatchConnectivitySyncStore.canUseiPhoneWatchCounterpart(
            isActivated: false,
            isPaired: true,
            isWatchAppInstalled: true
        ))
        #expect(PulsarWatchConnectivitySyncStore.canUseiPhoneWatchCounterpart(
            isActivated: true,
            isPaired: true,
            isWatchAppInstalled: true
        ))
    }

    @Test func watchMayUpdateAnAlreadyAdoptedSession() {
        let current = makeLiveCompanionGym(generation: 1)
        var incoming = current
        incoming.elapsedSeconds = 40
        incoming.lifecycleGeneration = 1
        incoming.updatedAt = current.updatedAt.addingTimeInterval(8)
        #expect(
            PulsarWatchSynchronizedGymReconciliation.shouldAdoptIncomingGymState(
                incoming: incoming,
                current: current,
                platform: .watch,
                isIncomingFromCounterpart: true
            )
        )
    }

    @Test func provisionalWatchIdentityCannotOverrideExplicitIPhoneStart() {
        let canonicalSessionID = UUID()
        let canonicalRequestID = UUID()
        var provisional = makeLiveCompanionGym()
        provisional.sessionId = UUID()
        provisional.requestID = nil
        provisional.startedFrom = .iPhoneRequestedWatchStart

        #expect(
            PulsarWatchSynchronizedGymReconciliation.incomingAuthorityDecision(
                incoming: provisional,
                canonicalSessionID: canonicalSessionID,
                canonicalRequestID: canonicalRequestID,
                hasAuthoritativeMirror: true
            ) == .rejectAdvisory(reason: "uncorrelated Watch launch placeholder")
        )
    }

    @Test func matchingCanonicalGymStateIsAdopted() {
        let canonicalSessionID = UUID()
        let canonicalRequestID = UUID()
        var matching = makeLiveCompanionGym()
        matching.sessionId = canonicalSessionID
        matching.requestID = canonicalRequestID

        #expect(
            PulsarWatchSynchronizedGymReconciliation.incomingAuthorityDecision(
                incoming: matching,
                canonicalSessionID: canonicalSessionID,
                canonicalRequestID: canonicalRequestID,
                hasAuthoritativeMirror: true
            ) == .adopt
        )
    }

    @Test func independentWatchWorkoutRequiresNoExistingAuthoritativeMirror() {
        let canonicalSessionID = UUID()
        let canonicalRequestID = UUID()
        var independent = makeLiveCompanionGym()
        independent.sessionId = UUID()
        independent.requestID = nil
        independent.startedFrom = .appleWatch

        #expect(
            PulsarWatchSynchronizedGymReconciliation.incomingAuthorityDecision(
                incoming: independent,
                canonicalSessionID: canonicalSessionID,
                canonicalRequestID: canonicalRequestID,
                hasAuthoritativeMirror: false
            ) == .competingWorkout(reason: "independent Apple Watch workout")
        )
        #expect(
            PulsarWatchSynchronizedGymReconciliation.incomingAuthorityDecision(
                incoming: independent,
                canonicalSessionID: canonicalSessionID,
                canonicalRequestID: canonicalRequestID,
                hasAuthoritativeMirror: true
            ) == .rejectAdvisory(reason: "authoritative HealthKit mirror already attached")
        )
    }

    @Test func launchPlaceholderIsStoredMetadataButNotRoutablePresentation() {
        var placeholder = makeLiveCompanionGym()
        placeholder.isLaunchPlaceholder = true

        #expect(!placeholder.isValidActiveWorkoutPresentationCandidate())
        #expect(placeholder.activeWorkoutPresentationRejectionReason() == "launch placeholder")
        #expect(PulsarActiveWorkoutSyncState(gymState: placeholder).phase == .starting)
    }

    @Test func cachedStateCanOnlyReattachToMatchingRecoveredHealthKitSession() {
        let state = makeLiveCompanionGym()
        #expect(
            PulsarWatchSynchronizedGymReconciliation.isHealthKitRecoveryCandidate(
                state,
                sessionStartDate: state.startedAt.addingTimeInterval(10),
                platform: .watch,
                isTombstoned: false
            )
        )
        #expect(
            !PulsarWatchSynchronizedGymReconciliation.isHealthKitRecoveryCandidate(
                state,
                sessionStartDate: state.startedAt.addingTimeInterval(60),
                platform: .watch,
                isTombstoned: false
            )
        )
        #expect(
            !PulsarWatchSynchronizedGymReconciliation.isHealthKitRecoveryCandidate(
                state,
                sessionStartDate: state.startedAt,
                platform: .watch,
                isTombstoned: true
            )
        )
    }

    private func makeLiveCompanionGym(
        isFinished: Bool = false,
        generation: Int = 1
    ) -> ActiveGymWorkoutState {
        let now = Date()
        return ActiveGymWorkoutState(
            sessionId: UUID(uuidString: "4CCE3875-BA19-41ED-B9DD-14EFB2924B0D")!,
            routineId: UUID(),
            routineName: "Push",
            routineEmoji: "🏋️",
            workoutKind: .routine,
            startedFrom: .iPhoneRequestedWatchStart,
            startedAt: now.addingTimeInterval(-30),
            elapsedSeconds: 30,
            currentExerciseIndex: 0,
            currentSetIndex: 0,
            totalExercises: 1,
            totalSets: 1,
            completedSets: 0,
            currentHeartRate: 128,
            averageHeartRate: 120,
            maxHeartRate: 132,
            activeEnergyKilocalories: 12,
            restRemainingSeconds: nil,
            restTotalSeconds: nil,
            isHealthKitEnabled: true,
            healthKitStatusMessage: nil,
            isFinished: isFinished,
            updatedAt: now,
            exercises: [],
            requestID: isFinished ? UUID() : nil,
            lifecycleGeneration: generation
        )
    }
}
