//
//  MindfulnessInsightsOverviewCard.swift
//  Pulsar
//

import SwiftUI

struct MindfulnessInsightsOverviewCard: View {
    var average: Double?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))

        layout {
            Label {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Insights")
                        .font(.headline)
                        .foregroundStyle(MindfulnessDesign.primaryText)
                        .accessibilityAddTraits(.isHeader)

                    Text(insightText)
                        .font(.subheadline)
                        .foregroundStyle(MindfulnessDesign.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(MindfulnessDesign.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            MindfulnessWeeklyAverageBadge(average: average)
                .frame(
                    maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil,
                    alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing
                )
        }
        .padding(MindfulnessDesign.cardPadding)
        .mindfulnessCardSurface(cornerRadius: 24, shadowOpacity: 0.035)
    }

    private var insightText: String {
        guard let average else {
            return "Log a few days to reveal your weekly pattern."
        }

        return switch average {
        case 0.72...: "You've been balanced most of this week."
        case 0.56..<0.72: "Your week is holding a steady rhythm."
        case 0.40..<0.56: "Your week has included lighter and heavier days."
        default: "Your signals suggest making room for gentle recovery."
        }
    }
}
