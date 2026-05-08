//
//  PulsarRunIntroExperienceView.swift
//  Pulsar
//

import SwiftUI

struct PulsarRunIntroExperienceView: View {
    @ObservedObject var coordinator: PulsarRunCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingRunExperience = false

    var body: some View {
        ZStack {
            if isShowingRunExperience {
                PulsarRunExperienceView(coordinator: coordinator)
                    .transition(.opacity.combined(with: .scale(scale: 1.015)))
            } else {
                PersonalizedWorkoutStartView(
                    workout: .running,
                    completionBehavior: .continueAutomatically,
                    onIntroCompleted: showRunExperience,
                    onCancel: { dismiss() }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
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
}

#Preview {
    PulsarRunIntroExperienceView(coordinator: PulsarRunCoordinator())
}
