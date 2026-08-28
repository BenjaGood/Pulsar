import SwiftUI

struct StrainInsightsSection: View {
    var insights: [StrainInsight]

    var body: some View {
        let visibleInsights = Array(insights.prefix(3))

        VStack(alignment: .leading, spacing: 12) {
            Text("Insights")
                .pulsarTextStyle(.sectionHeader)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(visibleInsights) { insight in
                    StrainInsightRow(insight: insight)

                    if insight.id != visibleInsights.last?.id {
                        Divider()
                            .overlay(.primary.opacity(0.04))
                            .padding(.leading, 48)
                    }
                }
            }
        }
        .padding(StrainDetailsDesign.cardPadding)
        .strainCardSurface()
    }
}
