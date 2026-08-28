//
//  MindfulnessMonthlyInsightCard.swift
//  Pulsar
//

import SwiftUI

struct MindfulnessMonthlyInsightCard: View {
    var average: Double?
    var summary: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))

        layout {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(MindfulnessDesign.primaryText)
                    .frame(width: 24, alignment: .leading)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Monthly Insight")
                        .pulsarTextStyle(.sectionHeader)
                        .foregroundStyle(MindfulnessDesign.primaryText)
                        .accessibilityAddTraits(.isHeader)

                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(MindfulnessDesign.secondaryText)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            MindfulnessHistoryAverageRing(average: average)
                .frame(
                    maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil,
                    alignment: .trailing
                )
        }
        .padding(MindfulnessDesign.historyCardPadding)
        .mindfulnessCardSurface(
            cornerRadius: MindfulnessDesign.historyCardCornerRadius,
            shadowOpacity: 0.035
        )
    }
}
