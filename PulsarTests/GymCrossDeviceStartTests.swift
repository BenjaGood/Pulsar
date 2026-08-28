//
//  GymCrossDeviceStartTests.swift
//  PulsarTests
//

import Foundation
import HealthKit
import Testing
@testable import Pulsar

struct GymCrossDeviceStartTests {
    @Test func prelaunchAdmissionRejectsStaleFutureAndTombstonedRequests() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)

        #expect(GymWorkoutStartRequestAdmission.accepts(
            requestedAt: now.addingTimeInterval(-30),
            now: now,
            isTombstoned: false
        ))
        #expect(!GymWorkoutStartRequestAdmission.accepts(
            requestedAt: now.addingTimeInterval(-91),
            now: now,
            isTombstoned: false
        ))
        #expect(!GymWorkoutStartRequestAdmission.accepts(
            requestedAt: now.addingTimeInterval(31),
            now: now,
            isTombstoned: false
        ))
        #expect(!GymWorkoutStartRequestAdmission.accepts(
            requestedAt: now,
            now: now,
            isTombstoned: true
        ))
    }

    @Test func embeddedRoutineSnapshotRequiresFreshMatchingStartAuthority() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let routineID = UUID()
        let request = GymWorkoutStartRequest(
            routineID: routineID,
            routineRevision: 3,
            workoutKind: .routine,
            activityTypeRawValue: HKWorkoutActivityType.traditionalStrengthTraining.rawValue,
            locationTypeRawValue: HKWorkoutSessionLocationType.indoor.rawValue,
            requestedAt: now.addingTimeInterval(-30)
        )
        let plan = WatchGymRoutinePlan(
            routineId: routineID,
            name: "Fresh Routine",
            emoji: "🏋️",
            exerciseCount: 0,
            mainMuscleGroups: [],
            estimatedDurationSeconds: 0,
            updatedAt: now,
            exercises: []
        )
        let envelope = GymRoutineSnapshotEnvelope(
            requestID: request.requestID,
            sessionID: request.candidateSessionID,
            routineID: routineID,
            revision: request.routineRevision,
            routinePlan: plan,
            startRequest: request,
            capturedAt: now
        )

        #expect(PulsarWatchConnectivitySyncStore.shouldAcceptEmbeddedGymRoutineSnapshot(
            envelope,
            now: now,
            isTombstoned: false
        ))
        #expect(!PulsarWatchConnectivitySyncStore.shouldAcceptEmbeddedGymRoutineSnapshot(
            envelope,
            now: now,
            isTombstoned: true
        ))

        var stale = envelope
        stale.startRequest?.requestedAt = now.addingTimeInterval(-91)
        #expect(!PulsarWatchConnectivitySyncStore.shouldAcceptEmbeddedGymRoutineSnapshot(
            stale,
            now: now,
            isTombstoned: false
        ))

        var refreshedRetry = stale
        refreshedRetry.startRequest?.requestedAt = now
        #expect(PulsarWatchConnectivitySyncStore.shouldAcceptEmbeddedGymRoutineSnapshot(
            refreshedRetry,
            now: now,
            isTombstoned: false
        ))
        #expect(refreshedRetry.requestID == stale.requestID)

        var mismatched = envelope
        mismatched.startRequest?.candidateSessionID = UUID()
        #expect(!PulsarWatchConnectivitySyncStore.shouldAcceptEmbeddedGymRoutineSnapshot(
            mismatched,
            now: now,
            isTombstoned: false
        ))
    }

    @Test func pendingRoutineSnapshotRevisionOnlyWinsWithinTheSameIdentity() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let staleRoutineID = UUID()
        let staleRequest = GymWorkoutStartRequest(
            routineID: staleRoutineID,
            routineRevision: 100,
            workoutKind: .routine,
            activityTypeRawValue: HKWorkoutActivityType.traditionalStrengthTraining.rawValue,
            locationTypeRawValue: HKWorkoutSessionLocationType.indoor.rawValue,
            requestedAt: now
        )
        let stale = GymRoutineSnapshotEnvelope(
            requestID: staleRequest.requestID,
            sessionID: staleRequest.candidateSessionID,
            routineID: staleRoutineID,
            revision: 100,
            routinePlan: WatchGymRoutinePlan(
                routineId: staleRoutineID,
                name: "Old Request",
                emoji: "🏋️",
                exerciseCount: 0,
                mainMuscleGroups: [],
                estimatedDurationSeconds: 0,
                updatedAt: now,
                exercises: []
            ),
            startRequest: staleRequest,
            capturedAt: now
        )

        let freshRoutineID = UUID()
        let freshRequest = GymWorkoutStartRequest(
            routineID: freshRoutineID,
            routineRevision: 3,
            workoutKind: .routine,
            activityTypeRawValue: HKWorkoutActivityType.traditionalStrengthTraining.rawValue,
            locationTypeRawValue: HKWorkoutSessionLocationType.indoor.rawValue,
            requestedAt: now
        )
        let fresh = GymRoutineSnapshotEnvelope(
            requestID: freshRequest.requestID,
            sessionID: freshRequest.candidateSessionID,
            routineID: freshRoutineID,
            revision: 3,
            routinePlan: WatchGymRoutinePlan(
                routineId: freshRoutineID,
                name: "Fresh Request",
                emoji: "🏋️",
                exerciseCount: 0,
                mainMuscleGroups: [],
                estimatedDurationSeconds: 0,
                updatedAt: now,
                exercises: []
            ),
            startRequest: freshRequest,
            capturedAt: now
        )

        #expect(PulsarWatchConnectivitySyncStore.shouldReplacePendingGymRoutineSnapshot(
            stale,
            with: fresh
        ))

        var olderSameIdentity = stale
        olderSameIdentity.revision = 99
        #expect(!PulsarWatchConnectivitySyncStore.shouldReplacePendingGymRoutineSnapshot(
            stale,
            with: olderSameIdentity
        ))
    }

    @Test func routineSnapshotChecksumValidatesRoundTrip() {
        let routineID = UUID()
        let plan = WatchGymRoutinePlan(
            routineId: routineID,
            name: "Push Day",
            emoji: "🏋️",
            exerciseCount: 1,
            mainMuscleGroups: ["Chest"],
            estimatedDurationSeconds: 3_600,
            updatedAt: Date(),
            exercises: []
        )
        let request = GymWorkoutStartRequest(
            routineID: routineID,
            routineRevision: 3,
            workoutKind: .routine,
            activityTypeRawValue: HKWorkoutActivityType.traditionalStrengthTraining.rawValue,
            locationTypeRawValue: HKWorkoutSessionLocationType.indoor.rawValue
        )
        let envelope = GymRoutineSnapshotEnvelope(
            requestID: request.requestID,
            sessionID: request.candidateSessionID,
            routineID: routineID,
            revision: 3,
            routinePlan: plan,
            startRequest: request
        )

        #expect(envelope.isChecksumValid)
        guard let data = GymCrossDeviceCodec.encodeRoutineSnapshot(envelope),
              let decoded = GymCrossDeviceCodec.decodeRoutineSnapshot(data) else {
            Issue.record("Expected routine snapshot codec round trip")
            return
        }
        #expect(decoded.isChecksumValid)
        #expect(decoded.revision == 3)
        #expect(decoded.startRequest?.requestID == request.requestID)
        #expect(decoded.startRequest?.candidateSessionID == request.candidateSessionID)
        #expect(decoded.startRequest?.routineID == request.routineID)
        #expect(decoded.startRequest?.routineRevision == request.routineRevision)
    }

    @Test func routineSnapshotChecksumRejectsTamperedPayload() {
        let routineID = UUID()
        let plan = WatchGymRoutinePlan(
            routineId: routineID,
            name: "Leg Day",
            emoji: "🦵",
            exerciseCount: 2,
            mainMuscleGroups: ["Quads"],
            estimatedDurationSeconds: 4_200,
            updatedAt: Date(),
            exercises: []
        )
        var envelope = GymRoutineSnapshotEnvelope(
            requestID: UUID(),
            sessionID: UUID(),
            routineID: routineID,
            revision: 2,
            routinePlan: plan
        )
        envelope.checksum = "invalid"
        #expect(!envelope.isChecksumValid)
    }

    @Test func routineSnapshotResolvesOnlyAnActualFreeWorkoutAsOpenGym() {
        let freeRoutine = PulsarRoutine.emptyGymWorkout()
        let freePlan = WatchGymRoutinePlan(routine: freeRoutine)
        let freeRequest = GymWorkoutStartRequest(
            routineID: freeRoutine.id,
            routineRevision: 1,
            workoutKind: .freeWorkout,
            activityTypeRawValue: HKWorkoutActivityType.traditionalStrengthTraining.rawValue,
            locationTypeRawValue: HKWorkoutSessionLocationType.indoor.rawValue
        )
        let freeEnvelope = GymRoutineSnapshotEnvelope(
            requestID: freeRequest.requestID,
            sessionID: freeRequest.candidateSessionID,
            routineID: freeRoutine.id,
            revision: 1,
            routinePlan: freePlan,
            startRequest: freeRequest
        )

        let routineID = UUID()
        let routinePlan = WatchGymRoutinePlan(
            routineId: routineID,
            name: "Friday",
            emoji: "🏋️",
            exerciseCount: 1,
            mainMuscleGroups: ["Chest"],
            estimatedDurationSeconds: 3_600,
            updatedAt: Date(),
            exercises: [
                WatchGymRoutineExercisePlan(
                    id: UUID(),
                    exerciseId: "friday-bench",
                    name: "Bench Press",
                    muscleGroup: "Chest",
                    equipment: "Barbell",
                    plannedSets: 3,
                    plannedReps: 8,
                    plannedWeight: 80,
                    weightUnit: "kg",
                    plannedRestSeconds: 90,
                    orderIndex: 0
                )
            ]
        )
        let routineRequest = GymWorkoutStartRequest(
            routineID: routineID,
            routineRevision: 2,
            workoutKind: .routine,
            activityTypeRawValue: HKWorkoutActivityType.traditionalStrengthTraining.rawValue,
            locationTypeRawValue: HKWorkoutSessionLocationType.indoor.rawValue
        )
        let routineEnvelope = GymRoutineSnapshotEnvelope(
            requestID: routineRequest.requestID,
            sessionID: routineRequest.candidateSessionID,
            routineID: routineID,
            revision: 2,
            routinePlan: routinePlan,
            startRequest: routineRequest
        )

        #expect(freePlan.hasCompleteExerciseDefinition)
        #expect(
            freeEnvelope.resolvedWorkoutKind(
                pendingRequest: nil,
                current: .routine,
                isLaunchPlaceholder: true
            ) == .freeWorkout
        )
        #expect(
            routineEnvelope.resolvedWorkoutKind(
                pendingRequest: nil,
                current: .freeWorkout,
                isLaunchPlaceholder: true
            ) == .routine
        )
    }

    @Test func watchRunningAcknowledgementIsAuthoritative() {
        let acknowledgement = GymWorkoutStartAcknowledgement(
            requestID: UUID(),
            candidateSessionID: UUID(),
            authoritativeSessionID: UUID(),
            sessionState: .running,
            mirroringState: .active
        )
        #expect(acknowledgement.isAuthoritativeWatchRunning)

        let preparingAck = GymWorkoutStartAcknowledgement(
            requestID: UUID(),
            candidateSessionID: UUID(),
            authoritativeSessionID: UUID(),
            sessionState: .preparing,
            mirroringState: .pending
        )
        #expect(!preparingAck.isAuthoritativeWatchRunning)
    }

    @Test func mirroredMetricsCodecPreservesWatchSamples() throws {
        let sessionID = UUID()
        let payload = GymMirroredMetricsPayload(
            sessionID: sessionID,
            sampledAt: Date(),
            currentHeartRate: 148,
            averageHeartRate: 132,
            maxHeartRate: 161,
            activeEnergyKilocalories: 44
        )

        let data = try #require(GymCrossDeviceCodec.encodeMirroredMetrics(payload))
        let decoded = try #require(GymCrossDeviceCodec.decodeMirroredMetrics(data))
        #expect(decoded.sessionID == sessionID)
        #expect(decoded.currentHeartRate == 148)
        #expect(decoded.activeEnergyKilocalories == 44)
    }

    @Test func watchRecorderAvailabilityUsesRawReachabilityOnly() {
        let snapshot = PulsarWatchRecorderAvailabilitySnapshot(
            isSupported: true,
            activationStateRawValue: 2,
            activationStateDescription: "activated",
            activationErrorMessage: nil,
            isPaired: true,
            rawIsWatchAppInstalled: false,
            rawIsReachable: false,
            lastWatchSeenAt: Date().addingTimeInterval(-60),
            hasEverReceivedWatchPayload: true
        )

        #expect(!snapshot.isReachable)
        #expect(!snapshot.isWatchAppInstalled)
        #expect(snapshot.hasDiagnosticRecentWatchHeartbeat)
        #expect(!snapshot.canStartOnWatch)
    }

    @Test func watchAppLaunchDoesNotRequireInteractiveReachability() {
        let snapshot = PulsarWatchRecorderAvailabilitySnapshot(
            isSupported: true,
            activationStateRawValue: 2,
            activationStateDescription: "activated",
            activationErrorMessage: nil,
            isPaired: true,
            rawIsWatchAppInstalled: true,
            rawIsReachable: false,
            lastWatchSeenAt: nil,
            hasEverReceivedWatchPayload: false
        )

        #expect(snapshot.canAttemptWatchAppLaunch)
        #expect(!snapshot.isWatchInteractivelyReachable)
        #expect(!snapshot.canStartOnWatch)
        #expect(snapshot.fallbackReason == nil)
    }

    @Test func gymCrossDeviceFeatureFlagDefaultsOn() {
        #expect(PulsarGymCrossDeviceStartFeature.isEnabledByDefault)
    }

    @Test func companionMirroringStartIsIdempotentWhileStartingOrActive() {
        var machine = PulsarMirroringStartMachine()
        guard case .startAttempt(1) = machine.beginAttempt() else {
            Issue.record("Expected first mirroring attempt")
            return
        }
        #expect(machine.state == .starting)

        guard case .ignore(let startingReason) = machine.beginAttempt() else {
            Issue.record("Expected ignore while starting")
            return
        }
        #expect(startingReason.contains("already starting"))
        #expect(machine.attemptCount == 1)

        machine.completeSuccess()
        #expect(machine.state == .active)

        guard case .ignore(let activeReason) = machine.beginAttempt() else {
            Issue.record("Expected ignore while active")
            return
        }
        #expect(activeReason.contains("already active"))
        #expect(machine.attemptCount == 1)
    }

    @Test func companionMirroringAllowsRetryOnlyAfterDefinitiveFailure() {
        var machine = PulsarMirroringStartMachine()
        _ = machine.beginAttempt()
        machine.completeFailure(alreadyMirroring: false)
        #expect(machine.state == .failed)

        guard case .startAttempt(2) = machine.beginAttempt() else {
            Issue.record("Expected a new attempt after failure")
            return
        }
        machine.completeFailure(alreadyMirroring: true)
        #expect(machine.state == .active)
    }

    @Test func mirrorAuthorityDistinguishesDuplicateFromReconnectReplacement() {
        let firstObject = NSObject()
        let secondObject = NSObject()
        let first = ObjectIdentifier(firstObject)
        let second = ObjectIdentifier(secondObject)
        #expect(first != second)
        #expect(
            PulsarWorkoutMirroringCoordinator.attachmentDecision(
                existingAuthoritative: nil,
                incoming: first
            ) == .attach
        )
        #expect(
            PulsarWorkoutMirroringCoordinator.attachmentDecision(
                existingAuthoritative: first,
                incoming: first
            ) == .duplicate
        )
        #expect(
            PulsarWorkoutMirroringCoordinator.attachmentDecision(
                existingAuthoritative: first,
                incoming: second
            ) == .replace(previous: first)
        )
    }

    @Test func terminalHealthKitStatesReleaseMirrorAuthority() {
        #expect(!PulsarWorkoutMirroringCoordinator.isTerminalMirroredSessionState(.running))
        #expect(!PulsarWorkoutMirroringCoordinator.isTerminalMirroredSessionState(.paused))
        #expect(PulsarWorkoutMirroringCoordinator.isTerminalMirroredSessionState(.stopped))
        #expect(PulsarWorkoutMirroringCoordinator.isTerminalMirroredSessionState(.ended))
    }

    @MainActor
    @Test func freshLocalRoutineStartSupersedesSuspendedStartupReconciliation() {
        let startupSnapshot = PulsarRestoredWorkoutReconciliationSnapshot(
            workoutState: nil,
            gymState: nil
        )
        let freshState = Self.makeRoutineState()

        #expect(!startupSnapshot.stillMatches(
            workoutState: PulsarActiveWorkoutSyncState(gymState: freshState),
            gymState: freshState
        ))
    }

    @MainActor
    @Test func localRoutineSurvivesTransitionToCompactWatchMirrorState() {
        let local = Self.makeRoutineState()
        var watchUpdate = local
        watchUpdate.startedFrom = .appleWatch
        watchUpdate.isLaunchPlaceholder = false
        watchUpdate.exercises = []
        watchUpdate.totalExercises = 0
        watchUpdate.totalSets = 0
        watchUpdate.updatedAt = local.updatedAt.addingTimeInterval(1)

        let canonical = watchUpdate.preservingRoutineDefinition(from: local)

        #expect(canonical.requestID == local.requestID)
        #expect(canonical.routineId == local.routineId)
        #expect(canonical.exercises == local.exercises)
        #expect(GymWatchMirroredWorkoutView.routineDisplayMode(
            for: canonical,
            expectedSessionID: local.sessionId
        ) == .routine)
    }

    @MainActor
    @Test func gymLiveViewResolverUsesCanonicalRoutineAfterMirrorAttachment() {
        var canonical = Self.makeRoutineState()
        canonical.isLaunchPlaceholder = false
        canonical.startedFrom = .appleWatch

        #expect(GymWatchMirroredWorkoutView.routineDisplayMode(
            for: canonical,
            expectedSessionID: canonical.sessionId
        ) == .routine)
        #expect(GymWatchMirroredWorkoutView.currentExerciseTitle(for: canonical) == "Barbell Full Squat")
        #expect(canonical.currentSet?.targetReps == 8)
        #expect(canonical.currentSet?.targetWeight == 100)
    }

    @MainActor
    @Test func delayedWatchAcknowledgementDoesNotGateLocalRoutineDisplay() {
        let local = Self.makeRoutineState()

        #expect(local.isPrelaunchPlaceholder)
        #expect(local.requestID != nil)
        #expect(GymWatchMirroredWorkoutView.routineDisplayMode(
            for: local,
            expectedSessionID: local.sessionId
        ) == .routine)
        #expect(GymWatchMirroredWorkoutView.currentExerciseTitle(for: local) == "Barbell Full Squat")
    }

    @MainActor
    @Test func delayedActiveGymPayloadDoesNotReplaceKnownLocalRoutineWithLoadingState() {
        let local = Self.makeRoutineState()
        let mirrorOnly = GymWatchMirroredWorkoutView.fallbackLiveState(
            sessionID: local.sessionId,
            snapshot: GymMirroredSessionSnapshot(
                isAttached: true,
                isLive: true,
                sessionID: local.sessionId,
                startedAt: local.startedAt
            )
        )

        #expect(GymWatchMirroredWorkoutView.routineDisplayMode(
            for: local,
            expectedSessionID: local.sessionId
        ) == .routine)
        #expect(GymWatchMirroredWorkoutView.routineDisplayMode(
            for: mirrorOnly,
            expectedSessionID: local.sessionId
        ) == .routinePending)
    }

    @MainActor
    @Test func genuineRecoveryWithoutRoutinePayloadRemainsPending() {
        let sessionID = UUID()
        #expect(GymWatchMirroredWorkoutView.routineDisplayMode(
            for: nil,
            expectedSessionID: sessionID
        ) == .routinePending)
    }

    @MainActor
    @Test func openGymNeverInheritsSavedRoutineDefinition() {
        var openGym = Self.makeRoutineState()
        openGym.workoutKind = .freeWorkout
        openGym.routineName = "Open Gym"
        openGym.exercises = []
        openGym.totalExercises = 0
        openGym.totalSets = 0

        #expect(GymWatchMirroredWorkoutView.routineDisplayMode(
            for: openGym,
            expectedSessionID: openGym.sessionId
        ) == .openGym)
        #expect(GymWatchMirroredWorkoutView.currentExerciseTitle(for: openGym) == "Open Gym")
    }

    @MainActor
    @Test func oldRestoredCleanupCannotMatchNewRequestUsingSameWorkoutID() {
        let restored = Self.makeRoutineState()
        let snapshot = PulsarRestoredWorkoutReconciliationSnapshot(
            workoutState: PulsarActiveWorkoutSyncState(gymState: restored),
            gymState: restored
        )
        var newer = restored
        newer.requestID = UUID()
        newer.lifecycleGeneration = (restored.lifecycleGeneration ?? 0) + 1

        #expect(!snapshot.stillMatches(
            workoutState: PulsarActiveWorkoutSyncState(gymState: newer),
            gymState: newer
        ))
    }

    private static func makeRoutineState() -> ActiveGymWorkoutState {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let exercise = ActiveGymWorkoutExerciseState(
            id: UUID(),
            exerciseId: "barbell-full-squat",
            exerciseName: "Barbell Full Squat",
            muscleGroup: "Quadriceps",
            equipment: "Barbell",
            plannedSets: 3,
            plannedReps: 8,
            plannedWeight: 100,
            weightUnit: "kg",
            plannedRestSeconds: 120,
            orderIndex: 0,
            sets: [
                ActiveGymWorkoutSetState(
                    id: UUID(),
                    setNumber: 1,
                    targetReps: 8,
                    targetWeight: 100,
                    completedReps: nil,
                    completedWeight: nil,
                    isCompleted: false,
                    completedAt: nil
                )
            ]
        )
        return ActiveGymWorkoutState(
            sessionId: UUID(),
            routineId: UUID(),
            routineName: "Friday",
            routineEmoji: "🏋️",
            workoutKind: .routine,
            startedFrom: .iPhoneRequestedWatchStart,
            startedAt: now,
            elapsedSeconds: 0,
            currentExerciseIndex: 0,
            currentSetIndex: 0,
            totalExercises: 1,
            totalSets: 3,
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
            exercises: [exercise],
            requestID: UUID(),
            routineRevision: 1,
            lifecycleGeneration: 1,
            isLaunchPlaceholder: true
        )
    }
}

struct GymLaunchWatchSessionPresentationTests {
    @Test func watchSessionIsRevealedDuringLaunchHandshake() {
        #expect(!GymLaunchWatchSessionPresentation.shouldRevealWatchSession(phase: .idle))
        #expect(!GymLaunchWatchSessionPresentation.shouldRevealWatchSession(phase: .cancelled))
        #expect(GymLaunchWatchSessionPresentation.shouldRevealWatchSession(phase: .preparing))
        #expect(GymLaunchWatchSessionPresentation.shouldRevealWatchSession(phase: .launchingWatch))
        #expect(GymLaunchWatchSessionPresentation.shouldRevealWatchSession(phase: .waitingForWatchAcknowledgement))
        #expect(GymLaunchWatchSessionPresentation.shouldRevealWatchSession(phase: .mirroring))
        #expect(GymLaunchWatchSessionPresentation.shouldRevealWatchSession(phase: .active))
        #expect(GymLaunchWatchSessionPresentation.shouldRevealWatchSession(phase: .failed(.watchLaunchFailed, canRetry: true)))
    }

    @Test func fallbackPromptKeepsChooserUntilUserChoosesAnAction() {
        #expect(!GymLaunchWatchSessionPresentation.shouldFollowCrossDeviceStart(isFallbackPromptVisible: true))
        #expect(GymLaunchWatchSessionPresentation.shouldFollowCrossDeviceStart(isFallbackPromptVisible: false))
        #expect(
            !GymLaunchWatchSessionPresentation.shouldRevealWatchSession(
                phase: .waitingForWatchAcknowledgement,
                isFallbackPromptVisible: true
            )
        )
        #expect(
            !GymLaunchWatchSessionPresentation.shouldRevealWatchSession(
                phase: .failed(.watchNotReachable, canRetry: true),
                isFallbackPromptVisible: true
            )
        )
        #expect(
            GymLaunchWatchSessionPresentation.shouldRevealWatchSession(
                phase: .waitingForWatchAcknowledgement,
                isFallbackPromptVisible: false
            )
        )
    }
}
