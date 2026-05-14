//
//  PulsarRunIntroExperienceView.swift
//  Pulsar
//

import SwiftUI

struct PulsarRunIntroExperienceView: View {
    @ObservedObject var coordinator: PulsarRunCoordinator
    var workoutKind: PulsarOutdoorWorkoutKind = .running
    var onMinimize: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingRunExperience = false

    var body: some View {
        ZStack {
            if isShowingRunExperience {
                PulsarRunExperienceView(coordinator: coordinator, workoutKind: workoutKind, onMinimize: onMinimize)
                    .transition(.opacity.combined(with: .scale(scale: 1.015)))
            } else if let personalizedWorkoutKind {
                PersonalizedWorkoutStartView(
                    workout: personalizedWorkoutKind,
                    completionBehavior: .continueAutomatically,
                    onIntroCompleted: showRunExperience,
                    onCancel: { dismiss() }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            } else {
                PulsarRunExperienceView(coordinator: coordinator, workoutKind: workoutKind, onMinimize: onMinimize)
                    .transition(.opacity)
            }
        }
        .onAppear {
            if personalizedWorkoutKind == nil {
                isShowingRunExperience = true
            }
        }
        .background(Color(red: 0.04, green: 0.00, blue: 0.01).ignoresSafeArea())
        .animation(.smooth(duration: 0.42), value: isShowingRunExperience)
    }

    private func showRunExperience() {
        withAnimation(.smooth(duration: 0.42)) {
            isShowingRunExperience = true
        }
    }

    private var personalizedWorkoutKind: PersonalizedWorkoutKind? {
        switch workoutKind {
        case .running: .running
        case .walking: .walking
        case .hiking: .hiking
        case .cycling, .hiit, .strength, .yoga, .pilates, .swimming, .rowing, .dance, .boxing, .stretching, .core, .mobility, .elliptical, .stairClimber, .cooldown, .other:
            nil
        }
    }
}

#Preview {
    PulsarRunIntroExperienceView(coordinator: PulsarRunCoordinator())
}
