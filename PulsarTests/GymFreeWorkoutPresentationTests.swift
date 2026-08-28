//
//  GymFreeWorkoutPresentationTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

struct GymFreeWorkoutPresentationTests {
    @Test func dedicatedPresentationRequiresExplicitFreeWorkoutKind() {
        var pendingRoutine = makeState(workoutKind: .routine, exerciseCount: 0)
        #expect(!GymFreeWorkoutTelemetry.usesDedicatedPresentation(pendingRoutine))
        #expect(
            GymWatchMirroredWorkoutView.routineDisplayMode(
                for: pendingRoutine,
                expectedSessionID: pendingRoutine.sessionId
            ) == .routinePending
        )
        #expect(GymWatchMirroredWorkoutView.currentExerciseTitle(for: pendingRoutine) == "Loading Routine…")

        pendingRoutine.workoutKind = .freeWorkout
        pendingRoutine.routineName = "Open Gym"
        #expect(GymFreeWorkoutTelemetry.usesDedicatedPresentation(pendingRoutine))
        #expect(
            GymWatchMirroredWorkoutView.routineDisplayMode(
                for: pendingRoutine,
                expectedSessionID: pendingRoutine.sessionId
            ) == .openGym
        )
    }

    @Test func populatedRoutineNeverUsesFreeWorkoutPresentation() {
        let routine = makeState(workoutKind: .routine, exerciseCount: 2)
        #expect(!GymFreeWorkoutTelemetry.usesDedicatedPresentation(routine))
        #expect(
            GymWatchMirroredWorkoutView.routineDisplayMode(
                for: routine,
                expectedSessionID: routine.sessionId
            ) == .routine
        )
        #expect(GymWatchMirroredWorkoutView.currentExerciseTitle(for: routine) == "Barbell Full Squat")
    }

    @Test func fallbackKindNeverInfersFreeWorkoutFromMissingRoutine() {
        #expect(
            GymFreeWorkoutTelemetry.resolvedFallbackWorkoutKind(
                placeholderKind: nil,
                startTransactionWorkoutType: nil
            ) == .routine
        )
        #expect(
            GymFreeWorkoutTelemetry.resolvedFallbackWorkoutKind(
                placeholderKind: .routine,
                startTransactionWorkoutType: PulsarGymWorkoutKind.freeWorkout.rawValue
            ) == .routine
        )
        #expect(
            GymFreeWorkoutTelemetry.resolvedFallbackWorkoutKind(
                placeholderKind: .freeWorkout,
                startTransactionWorkoutType: PulsarGymWorkoutKind.routine.rawValue
            ) == .freeWorkout
        )
        #expect(
            GymFreeWorkoutTelemetry.resolvedFallbackWorkoutKind(
                placeholderKind: nil,
                startTransactionWorkoutType: PulsarGymWorkoutKind.freeWorkout.rawValue
            ) == .freeWorkout
        )
    }

    @Test func healthKitFallbackCanCarryKnownFreeWorkoutKind() {
        let sessionID = UUID()
        let snapshot = GymMirroredSessionSnapshot(
            isAttached: true,
            isLive: true,
            sessionID: sessionID,
            startedAt: Date().addingTimeInterval(-30),
            currentHeartRate: 62,
            averageHeartRate: 61,
            maxHeartRate: 64,
            activeEnergyKilocalories: 1
        )

        let defaultFallback = GymWatchMirroredWorkoutView.fallbackLiveState(
            sessionID: sessionID,
            snapshot: snapshot
        )
        #expect(!GymFreeWorkoutTelemetry.usesDedicatedPresentation(defaultFallback))
        #expect(
            GymWatchMirroredWorkoutView.routineDisplayMode(
                for: defaultFallback,
                expectedSessionID: sessionID
            ) == .routinePending
        )

        let freeFallback = GymWatchMirroredWorkoutView.fallbackLiveState(
            sessionID: sessionID,
            snapshot: snapshot,
            workoutKind: .freeWorkout
        )
        #expect(GymFreeWorkoutTelemetry.usesDedicatedPresentation(freeFallback))
        #expect(freeFallback.routineName == PulsarGymWorkoutKind.freeWorkout.displayName)
        #expect(freeFallback.currentHeartRate == 62)
        #expect(freeFallback.averageHeartRate == 61)
        #expect(freeFallback.activeEnergyKilocalories == 1)
        #expect(
            GymWatchMirroredWorkoutView.routineDisplayMode(
                for: freeFallback,
                expectedSessionID: sessionID
            ) == .openGym
        )
    }

    @Test func fourthMetricUsesAverageHeartRateNotFabricatedOxygen() {
        let state = makeState(workoutKind: .freeWorkout, exerciseCount: 0)
        #expect(state.averageHeartRate == 118)
        #expect(PulsarGymFormatters.heartRate(state.averageHeartRate) == "118")
        #expect(GymFreeWorkoutTelemetry.caloriesText(state.activeEnergyKilocalories) == "12")
        #expect(GymFreeWorkoutTelemetry.caloriesText(nil) == "--")
    }

    @Test func heartRateZoneUsesExistingLiveWorkoutProfile() {
        var profile = UserProfile.empty
        profile.manualMaxHeartRate = 190
        let zoneProfile = PulsarHeartRateZoneProfile(profile: profile)

        #expect(zoneProfile.zone(for: 62)?.number == 1)
        #expect(zoneProfile.zone(for: 148)?.number == 3)
        #expect(PulsarHeartRateZoneProfile(profile: .empty).zone(for: 148) == nil)
    }

    @Test func elapsedTimeUsesStartedAtWithoutGoingBackwards() {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        var state = makeState(workoutKind: .freeWorkout, exerciseCount: 0, startedAt: startedAt)
        state.elapsedSeconds = 12
        let later = startedAt.addingTimeInterval(30)
        #expect(GymFreeWorkoutTelemetry.elapsedSeconds(for: state, at: later) == 30)

        state.isFinished = true
        state.elapsedSeconds = 18
        #expect(GymFreeWorkoutTelemetry.elapsedSeconds(for: state, at: later) == 18)
    }
}

private extension GymFreeWorkoutPresentationTests {
    func makeState(
        workoutKind: PulsarGymWorkoutKind,
        exerciseCount: Int,
        startedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> ActiveGymWorkoutState {
        let exercises: [ActiveGymWorkoutExerciseState]
        if exerciseCount > 0 {
            exercises = [
                ActiveGymWorkoutExerciseState(
                    id: UUID(),
                    exerciseId: nil,
                    exerciseName: "Barbell Full Squat",
                    muscleGroup: "Glutes",
                    equipment: "Barbell",
                    plannedSets: 4,
                    plannedReps: 8,
                    plannedWeight: 100,
                    weightUnit: "lb",
                    plannedRestSeconds: 90,
                    orderIndex: 0,
                    notes: nil,
                    thumbnailURL: nil,
                    instructionsPreview: nil,
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
            ]
        } else {
            exercises = []
        }

        return ActiveGymWorkoutState(
            sessionId: UUID(),
            routineId: UUID(),
            routineName: workoutKind == .freeWorkout ? "Open Gym" : "Friday",
            routineEmoji: "💪",
            workoutKind: workoutKind,
            startedFrom: .appleWatch,
            startedAt: startedAt,
            elapsedSeconds: 30,
            currentExerciseIndex: 0,
            currentSetIndex: 0,
            totalExercises: exercises.count,
            totalSets: exercises.reduce(0) { $0 + $1.sets.count },
            completedSets: 0,
            currentHeartRate: 62,
            averageHeartRate: 118,
            maxHeartRate: 124,
            activeEnergyKilocalories: 12,
            restRemainingSeconds: nil,
            restTotalSeconds: nil,
            isHealthKitEnabled: true,
            healthKitStatusMessage: nil,
            isFinished: false,
            updatedAt: startedAt,
            exercises: exercises
        )
    }
}
