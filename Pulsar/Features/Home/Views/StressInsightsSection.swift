import SwiftUI

struct StressInsightsSection: View {
    var summary: StressSummary

    var body: some View {
        let insights = StressInsightFactory.insights(for: summary)

        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Insights")
                    .pulsarTextStyle(.sectionHeader)
                    .accessibilityAddTraits(.isHeader)

                Text("Personalized interpretation of today’s physiology")
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 12) {
                    ForEach(insights) { insight in
                        StressInsightCard(insight: insight)
                    }
                }
            }
        }
    }
}

#Preview("Low Stress Insights") {
    ScrollView {
        StressInsightsSection(summary: MockHealthData.stressPreviewSummary(score: 18))
            .padding(20)
    }
    .background(StressDetailsBackground())
}

#Preview("Limited Stress Insights") {
    var summary = MockHealthData.stressPreviewSummary(score: 18)
    summary.signals.append(
        StressSignal(
            id: "recent-load",
            title: "Recent strain/load",
            value: "Not available",
            baseline: nil,
            availability: .unavailable
        )
    )

    return ScrollView {
        StressInsightsSection(summary: summary)
            .padding(20)
    }
    .background(StressDetailsBackground())
}
