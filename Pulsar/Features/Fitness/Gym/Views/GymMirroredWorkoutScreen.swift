//
//  GymMirroredWorkoutScreen.swift
//  Pulsar
//

import SwiftUI

struct GymMirroredWorkoutScreen: View {
    @ObservedObject var syncStore: PulsarWatchConnectivitySyncStore

    let state: ActiveGymWorkoutState
    let expectedSessionID: UUID
    let statusMessage: String
    let isRequestingFinish: Bool
    let onOpenAudio: () -> Void
    let onMinimize: () -> Void
    let onCompleteSet: () -> Void
    let onUpdateSet: (Int?, Double?) -> Void
    let onSkipRest: () -> Void
    let onFinish: () -> Bool

    @State private var isShowingRoutineOverview = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GymMirroredWorkoutHeader(
                    state: state,
                    statusMessage: statusMessage,
                    canShowRoutine: !state.exercises.isEmpty,
                    onOpenAudio: onOpenAudio,
                    onMinimize: onMinimize,
                    onShowRoutine: showRoutineOverview
                )

                GymMirroredWorkoutProgressCard(state: state)

                GymMirroredCurrentExerciseCard(
                    state: state,
                    onCompleteSet: onCompleteSet,
                    onUpdateSet: onUpdateSet
                )

                if state.restRemainingSeconds.map({ $0 > 0 }) == true {
                    GymMirroredRestCard(
                        state: state,
                        onSkip: onSkipRest
                    )
                }

                SlideToFinishWorkoutControl(
                    isFinishing: isRequestingFinish,
                    onFinish: onFinish
                )
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.white)
        .sheet(isPresented: $isShowingRoutineOverview) {
            GymRoutineOverviewSheet(
                syncStore: syncStore,
                expectedSessionID: expectedSessionID,
                fallbackState: state
            )
        }
    }

    private func showRoutineOverview() {
        guard !state.exercises.isEmpty else { return }
        isShowingRoutineOverview = true
    }
}

#if DEBUG
#Preview("Mirrored gym workout") {
    GymMirroredWorkoutScreen(
        syncStore: .shared,
        state: .mirroredWorkoutPreview,
        expectedSessionID: ActiveGymWorkoutState.mirroredWorkoutPreview.sessionId,
        statusMessage: "Mirroring live workout to iPhone…",
        isRequestingFinish: false,
        onOpenAudio: {},
        onMinimize: {},
        onCompleteSet: {},
        onUpdateSet: { _, _ in },
        onSkipRest: {},
        onFinish: { true }
    )
    .preferredColorScheme(.light)
}

private extension ActiveGymWorkoutState {
    static let mirroredWorkoutPreview: ActiveGymWorkoutState = {
        let exercises = [
            ActiveGymWorkoutExerciseState.preview(
                orderIndex: 0,
                name: "Barbell Full Squat",
                muscleGroup: "Glutes",
                equipment: "Barbell",
                thumbnailURL: "images/0043-qXTaZnJ.jpg"
            ),
            ActiveGymWorkoutExerciseState.preview(orderIndex: 1, name: "Bench Press", muscleGroup: "Chest", equipment: "Barbell"),
            ActiveGymWorkoutExerciseState.preview(orderIndex: 2, name: "Bent Over Row", muscleGroup: "Back", equipment: "Barbell"),
            ActiveGymWorkoutExerciseState.preview(orderIndex: 3, name: "Shoulder Press", muscleGroup: "Shoulders", equipment: "Dumbbell"),
            ActiveGymWorkoutExerciseState.preview(orderIndex: 4, name: "Biceps Curl", muscleGroup: "Biceps", equipment: "Dumbbell"),
            ActiveGymWorkoutExerciseState.preview(orderIndex: 5, name: "Triceps Extension", muscleGroup: "Triceps", equipment: "Cable")
        ]

        return ActiveGymWorkoutState(
            sessionId: UUID(),
            routineId: UUID(),
            routineName: "Friday",
            routineEmoji: "💪",
            workoutKind: .routine,
            startedFrom: .iPhoneRequestedWatchStart,
            startedAt: Date.now.addingTimeInterval(-305),
            elapsedSeconds: 305,
            currentExerciseIndex: 0,
            currentSetIndex: 0,
            totalExercises: exercises.count,
            totalSets: exercises.reduce(0) { $0 + $1.sets.count },
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
            updatedAt: .now,
            exercises: exercises
        )
    }()
}

private extension ActiveGymWorkoutExerciseState {
    static func preview(
        orderIndex: Int,
        name: String,
        muscleGroup: String,
        equipment: String,
        thumbnailURL: String? = nil
    ) -> ActiveGymWorkoutExerciseState {
        let sets = (1...4).map { setNumber in
            ActiveGymWorkoutSetState(
                id: UUID(),
                setNumber: setNumber,
                targetReps: 10,
                targetWeight: 0,
                completedReps: nil,
                completedWeight: nil,
                isCompleted: false,
                completedAt: nil
            )
        }

        return ActiveGymWorkoutExerciseState(
            id: UUID(),
            exerciseId: nil,
            exerciseName: name,
            muscleGroup: muscleGroup,
            equipment: equipment,
            plannedSets: sets.count,
            plannedReps: 10,
            plannedWeight: 0,
            weightUnit: "lb",
            plannedRestSeconds: 90,
            orderIndex: orderIndex,
            notes: nil,
            thumbnailURL: thumbnailURL,
            instructionsPreview: nil,
            sets: sets
        )
    }
}
#endif
