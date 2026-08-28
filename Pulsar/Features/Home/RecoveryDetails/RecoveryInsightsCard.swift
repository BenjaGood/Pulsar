import SwiftUI

struct RecoveryInsightsCard: View {
    var insights: [RecoveryInsight]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Insights")
                .pulsarTextStyle(.sectionHeader)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(insights) { insight in
                    RecoveryInsightRow(insight: insight)

                    if insight.id != insights.last?.id {
                        Divider()
                            .overlay(.primary.opacity(0.04))
                            .padding(.leading, 48)
                    }
                }
            }
        }
        .padding(RecoveryDetailsDesign.cardPadding)
        .recoveryCardSurface()
    }
}
