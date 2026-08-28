//
//  TrainingBalanceGauge.swift
//  Pulsar
//

import SwiftUI

struct TrainingBalanceGauge: View {
    var score: Int
    var label: String
    var hasTrainingData: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var displayedScore = 0

    var body: some View {
        Gauge(value: Double(displayedScore), in: 0...100) {
            EmptyView()
        } currentValueLabel: {
            VStack(spacing: 1) {
                Text("\(displayedScore)%")
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(hasTrainingData ? PulsarFitnessMonochromeDesign.primaryText : PulsarTheme.fitnessSecondaryText(for: colorScheme))

                Text(label)
                    .font(.caption)
                    .foregroundStyle(PulsarTheme.fitnessSecondaryText(for: colorScheme))
                    .lineLimit(1)
            }
        }
        .gaugeStyle(
            MuscleFocusMapGaugeStyle(
                isActive: hasTrainingData,
                progress: Double(displayedScore) / 100
            )
        )
        .frame(width: 102, height: 102)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Training balance")
        .accessibilityValue(hasTrainingData ? "\(score) percent, \(label)" : "No training data")
        .task(id: score) {
            if reduceMotion {
                displayedScore = score
            } else {
                displayedScore = 0
                withAnimation(.smooth(duration: 0.72)) {
                    displayedScore = score
                }
            }
        }
    }
}

private struct MuscleFocusMapGaugeStyle: GaugeStyle {
    var isActive: Bool
    var progress: Double

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            Circle()
                .trim(from: 0.12, to: 0.88)
                .stroke(.white.opacity(0.10), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(90))

            Circle()
                .trim(from: 0.12, to: 0.12 + 0.76 * progress)
                .stroke(
                    AngularGradient(
                        colors: isActive
                            ? [PulsarFitnessMonochromeDesign.primaryText, PulsarFitnessMonochromeDesign.primaryText]
                            : [.white.opacity(0.16), .white.opacity(0.26)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(90))
                .shadow(color: isActive ? PulsarFitnessMonochromeDesign.primaryText.opacity(0.36) : .clear, radius: 7)

            configuration.currentValueLabel
        }
    }
}
