//
//  GymMirroredRestCard.swift
//  Pulsar
//

import SwiftUI

struct GymMirroredRestCard: View {
    let state: ActiveGymWorkoutState
    let onSkip: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "timer")
                .font(.title2)

            VStack(alignment: .leading, spacing: 3) {
                Text("Rest")
                    .font(.subheadline)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Text(PulsarGymFormatters.duration(remainingSeconds(at: timeline.date)))
                        .font(.title2.bold().monospacedDigit())
                }
            }

            Spacer()

            Button("Skip", action: onSkip)
                .font(.headline)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .pulsarLiquidGlass(cornerRadius: 22, interactive: true, isClear: true)
        }
        .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
        .padding(18)
        .gymWorkoutWhiteGlassSurface(cornerRadius: 26, shadowOpacity: 0.025)
    }

    private func remainingSeconds(at date: Date) -> Int {
        guard let remaining = state.restRemainingSeconds else { return 0 }
        let elapsedSinceSync = max(0, Int(date.timeIntervalSince(state.updatedAt)))
        return max(0, remaining - elapsedSinceSync)
    }
}
