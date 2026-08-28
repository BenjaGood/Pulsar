//
//  WorkoutOwnershipPhase3Tests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

@MainActor
struct WorkoutOwnershipPhase3Tests {
    @Test func mirroredSessionRejectPolicyRequiresIdentity() {
        #expect(
            GymMirroredSessionBridge.shouldEndMirroredSession(
                reason: "unexpectedDestination",
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
        #expect(
            GymMirroredSessionBridge.shouldEndMirroredSession(
                reason: "explicitCancel",
                requestID: nil,
                sessionID: UUID()
            )
        )
        #expect(
            GymMirroredSessionBridge.shouldEndMirroredSession(
                reason: "timeout",
                requestID: nil,
                sessionID: nil
            ) == false
        )
    }

    @Test func applicationContextOmitsTerminalStandInsWhenLiveStateNil() {
        let store = PulsarWatchConnectivitySyncStore.shared
        #expect(store.applicationContextOmitsTerminalStandInsWhenLiveStateNilForTesting())
    }

    @Test func finishedGymForDifferentSessionDoesNotReplaceLiveGym() {
        let store = PulsarWatchConnectivitySyncStore.shared
        let liveSessionID = UUID()
        let finishedSessionID = UUID()
        let now = Date()

        let live = ActiveGymWorkoutState(
            sessionId: liveSessionID,
            routineId: liveSessionID,
            routineName: "Live Push",
            routineEmoji: "🏋️",
            workoutKind: .routine,
            startedFrom: .iPhoneRequestedWatchStart,
            startedAt: now,
            elapsedSeconds: 30,
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
            updatedAt: now,
            exercises: []
        )
        #expect(store.storeActiveGymState(live, broadcast: false, reason: "phase3LiveSeed"))

        let finished = ActiveGymWorkoutState(
            sessionId: finishedSessionID,
            routineId: finishedSessionID,
            routineName: "Old Pull",
            routineEmoji: "💪",
            workoutKind: .routine,
            startedFrom: .appleWatch,
            startedAt: now.addingTimeInterval(1),
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
            updatedAt: now.addingTimeInterval(2),
            exercises: []
        )
        #expect(store.storeActiveGymState(finished, broadcast: false, reason: "phase3StaleFinished") == false)
        #expect(store.activeGymState?.sessionId == liveSessionID)
        #expect(store.activeGymState?.isFinished == false)

        store.clearActiveGymState(reason: "phase3LiveCleanup", broadcastEndedState: false)
    }

    @Test func startingGraceProtectsFreshGymFromStaleRouteReason() {
        let now = Date()
        let state = ActiveGymWorkoutState(
            sessionId: UUID(),
            routineId: UUID(),
            routineName: "Starting Session",
            routineEmoji: "🏋️",
            workoutKind: .freeWorkout,
            startedFrom: .iPhoneRequestedWatchStart,
            startedAt: now.addingTimeInterval(-30),
            elapsedSeconds: 30,
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
            updatedAt: now.addingTimeInterval(-30),
            exercises: []
        )

        #expect(state.staleRouteReason(now: now) == nil)
        #expect(state.isValidLiveRouteCandidate(now: now))
    }
}
