//
//  PulsarRunExperienceView.swift
//  Pulsar
//

import SwiftUI

struct PulsarRunExperienceView: View {
    @ObservedObject var coordinator: PulsarRunCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            if let summary = coordinator.summary {
                PulsarRunSummaryView(summary: summary) {
                    coordinator.resetAfterSummary()
                    dismiss()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if coordinator.snapshot.phase == .running ||
                        coordinator.snapshot.phase == .paused ||
                        coordinator.snapshot.phase == .finishing ||
                        coordinator.snapshot.phase == .connectingToWatch {
                PulsarLiveRunView(coordinator: coordinator) {
                    dismiss()
                }
                .transition(.opacity)
            } else {
                PulsarRunSetupView(coordinator: coordinator) {
                    dismiss()
                }
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.28), value: coordinator.snapshot.phase)
        .animation(.smooth(duration: 0.28), value: coordinator.summary != nil)
    }
}

#Preview {
    PulsarRunExperienceView(coordinator: PulsarRunCoordinator())
}
