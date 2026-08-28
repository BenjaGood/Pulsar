//
//  GymMirroredWorkoutProgressCard.swift
//  Pulsar
//

import SwiftUI

struct GymMirroredWorkoutProgressCard: View {
    let state: ActiveGymWorkoutState

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(state.progressText)
                        .font(.title2.bold())
                        .foregroundStyle(Color.black)
                    Text(state.exerciseProgressText)
                        .font(.body)
                        .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                GymMirroredWorkoutMetric(
                    symbolName: "heart",
                    accessibilityLabel: "Heart rate",
                    value: PulsarGymFormatters.heartRate(state.currentHeartRate),
                    unit: "bpm"
                )

                Divider()

                GymMirroredWorkoutMetric(
                    symbolName: "flame",
                    accessibilityLabel: "Active calories",
                    value: state.activeEnergyKilocalories.map { "\(Int($0.rounded()))" } ?? "--",
                    unit: "kcal"
                )
            }
            .frame(minHeight: 86)

            ProgressView(value: GymWatchMirroredWorkoutView.progressFraction(for: state))
                .progressViewStyle(.linear)
                .tint(Color.black)
                .accessibilityLabel("Workout progress")
                .accessibilityValue(state.progressText)
        }
        .padding(20)
        .gymWorkoutWhiteGlassSurface(cornerRadius: 30)
    }
}

private struct GymMirroredWorkoutMetric: View {
    let symbolName: String
    let accessibilityLabel: String
    let value: String
    let unit: String

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbolName)
                .font(.title3)
                .accessibilityHidden(true)
            Text(value)
                .font(.title3.bold().monospacedDigit())
            Text(unit)
                .font(.subheadline)
                .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
        }
        .foregroundStyle(Color.black)
        .frame(minWidth: 54)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(value == "--" ? "Unavailable" : "\(value) \(unit)")
    }
}
