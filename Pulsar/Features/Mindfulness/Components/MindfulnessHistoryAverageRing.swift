//
//  MindfulnessHistoryAverageRing.swift
//  Pulsar
//

import SwiftUI

struct MindfulnessHistoryAverageRing: View {
    var average: Double?

    @ScaledMetric(relativeTo: .body) private var ringSize = 80.0

    var body: some View {
        ZStack {
            Circle()
                .stroke(MindfulnessDesign.track.opacity(0.60), lineWidth: 4)

            Circle()
                .trim(from: 0, to: average ?? 0)
                .stroke(
                    MindfulnessDesign.primaryText,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text(scoreText)
                    .pulsarTextStyle(.metricMedium)
                    .monospacedDigit()
                    .foregroundStyle(MindfulnessDesign.primaryText)

                Text("Average")
                    .font(.caption)
                    .foregroundStyle(MindfulnessDesign.secondaryText)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .frame(width: min(ringSize, 90), height: min(ringSize, 90))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var scoreText: String {
        guard let average else { return "--" }
        return (average * 5).formatted(.number.precision(.fractionLength(1)))
    }

    private var accessibilityLabel: String {
        guard average != nil else { return "Monthly average unavailable" }
        return "Monthly average \(scoreText) out of 5"
    }
}
