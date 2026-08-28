//
//  MindfulnessWeeklyAverageBadge.swift
//  Pulsar
//

import SwiftUI

struct MindfulnessWeeklyAverageBadge: View {
    var average: Double?

    @ScaledMetric(relativeTo: .body) private var badgeSize = 72.0

    var body: some View {
        VStack(spacing: 1) {
            Text(displayedAverage)
                .pulsarTextStyle(.sectionHeader)
                .monospacedDigit()
                .foregroundStyle(MindfulnessDesign.primaryText)

            Text("Average")
                .font(.caption)
                .foregroundStyle(MindfulnessDesign.secondaryText)
        }
        .frame(width: badgeSize, height: badgeSize)
        .background {
            Color.clear
                .mindfulnessCardSurface(cornerRadius: badgeSize / 2, shadowOpacity: 0.025)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var displayedAverage: String {
        guard let average else { return "--" }
        return (average * 5).formatted(.number.precision(.fractionLength(1)))
    }

    private var accessibilityLabel: String {
        guard average != nil else { return "Weekly average unavailable" }
        return "Weekly average \(displayedAverage) out of 5"
    }
}
