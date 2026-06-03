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
            } else {
                PersonalizedWorkoutStartView(
                    workoutKind: workoutKind,
                    completionBehavior: .continueAutomatically,
                    onIntroCompleted: showRunExperience,
                    onCancel: { dismiss() }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
        }
        .background(Color.black.ignoresSafeArea())
        .animation(.smooth(duration: 0.42), value: isShowingRunExperience)
    }

    private func showRunExperience() {
        withAnimation(.smooth(duration: 0.42)) {
            isShowingRunExperience = true
        }
    }
}

#Preview {
    PulsarRunIntroExperienceView(coordinator: PulsarRunCoordinator())
}
