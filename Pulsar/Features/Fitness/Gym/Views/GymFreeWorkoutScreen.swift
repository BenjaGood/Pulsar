//
//  GymFreeWorkoutScreen.swift
//  Pulsar
//

import SwiftUI

struct GymFreeWorkoutScreen: View {
    let state: ActiveGymWorkoutState
    let zoneProfile: PulsarHeartRateZoneProfile
    let isRequestingFinish: Bool
    let onOpenAudio: () -> Void
    let onMinimize: () -> Void
    let onFinish: () -> Bool

    var body: some View {
        ViewThatFits(in: .vertical) {
            VStack(spacing: 0) {
                mainColumn
                Spacer(minLength: 24)
            }

            ScrollView {
                mainColumn
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SlideToFinishWorkoutControl(
                isFinishing: isRequestingFinish,
                onFinish: onFinish
            )
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
    }

    private var mainColumn: some View {
        VStack(spacing: 0) {
            GymFreeWorkoutHeader(
                state: state,
                onOpenAudio: onOpenAudio,
                onMinimize: onMinimize
            )

            GymFreeWorkoutMetricsCard(
                currentHeartRate: state.currentHeartRate,
                activeEnergyKilocalories: state.activeEnergyKilocalories,
                averageHeartRate: state.averageHeartRate,
                zoneProfile: zoneProfile
            )
            .padding(.top, 22)
        }
    }
}

#if DEBUG
#Preview("Free Workout") {
    GymFreeWorkoutScreen(
        state: .freeWorkoutPreview,
        zoneProfile: PulsarHeartRateZoneProfile(maxHeartRate: 190, source: .manual),
        isRequestingFinish: false,
        onOpenAudio: {},
        onMinimize: {},
        onFinish: { true }
    )
    .preferredColorScheme(.light)
}

#Preview("Free Workout unavailable metrics") {
    GymFreeWorkoutScreen(
        state: .freeWorkoutUnavailablePreview,
        zoneProfile: PulsarHeartRateZoneProfile(profile: .empty),
        isRequestingFinish: false,
        onOpenAudio: {},
        onMinimize: {},
        onFinish: { true }
    )
    .preferredColorScheme(.light)
}

private extension ActiveGymWorkoutState {
    static let freeWorkoutPreview: ActiveGymWorkoutState = {
        freeWorkoutPreviewState(
            currentHeartRate: 62,
            averageHeartRate: 61,
            activeEnergyKilocalories: 1
        )
    }()

    static let freeWorkoutUnavailablePreview: ActiveGymWorkoutState = {
        freeWorkoutPreviewState(
            currentHeartRate: nil,
            averageHeartRate: nil,
            activeEnergyKilocalories: nil
        )
    }()

    static func freeWorkoutPreviewState(
        currentHeartRate: Double?,
        averageHeartRate: Double?,
        activeEnergyKilocalories: Double?
    ) -> ActiveGymWorkoutState {
        ActiveGymWorkoutState(
            sessionId: UUID(),
            routineId: UUID(),
            routineName: "Open Gym",
            routineEmoji: "🏋️",
            workoutKind: .freeWorkout,
            startedFrom: .appleWatch,
            startedAt: Date.now.addingTimeInterval(-30),
            elapsedSeconds: 30,
            currentExerciseIndex: 0,
            currentSetIndex: 0,
            totalExercises: 0,
            totalSets: 0,
            completedSets: 0,
            currentHeartRate: currentHeartRate,
            averageHeartRate: averageHeartRate,
            maxHeartRate: currentHeartRate,
            activeEnergyKilocalories: activeEnergyKilocalories,
            restRemainingSeconds: nil,
            restTotalSeconds: nil,
            isHealthKitEnabled: true,
            healthKitStatusMessage: nil,
            isFinished: false,
            updatedAt: .now,
            exercises: []
        )
    }
}
#endif
