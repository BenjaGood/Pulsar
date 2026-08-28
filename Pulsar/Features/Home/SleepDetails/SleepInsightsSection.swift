import SwiftUI

struct SleepInsightsSection: View {
    var insights: [SleepInsight]

    var body: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Insights")
                    .pulsarTextStyle(.sectionHeader)
                    .padding(.horizontal, 4)
                    .accessibilityAddTraits(.isHeader)

                VStack(spacing: 0) {
                    ForEach(insights.prefix(3).enumerated(), id: \.element.id) { index, insight in
                        SleepInsightRow(
                            text: insight.text,
                            symbol: symbol(for: index),
                            tint: tint(for: index)
                        )

                        if index < min(insights.count, 3) - 1 {
                            Divider()
                                .padding(.leading, 42)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .sleepCardSurface()
            }
        }
    }

    private func symbol(for index: Int) -> String {
        switch index {
        case 0:
            "sparkles"
        case 1:
            "moon.stars.fill"
        default:
            "bolt.fill"
        }
    }

    private func tint(for index: Int) -> Color {
        switch index {
        case 0:
            SleepDetailsDesign.deep
        case 1:
            SleepDetailsDesign.rem
        default:
            SleepDetailsDesign.awake
        }
    }
}
