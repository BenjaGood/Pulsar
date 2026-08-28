import SwiftUI

struct RecoveryTrendHeader: View {
    var currentScoreText: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    headerCopy
                    indicator
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    headerCopy

                    Spacer(minLength: 8)

                    indicator
                }
            }
        }
    }

    private var headerCopy: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("7-Day Trend")
                .pulsarTextStyle(.sectionHeader)
                .accessibilityAddTraits(.isHeader)

            Text("Based on available HealthKit data")
                .pulsarTextStyle(.metadata)
                .foregroundStyle(.secondary)
        }
    }

    private var indicator: some View {
        VStack(spacing: 1) {
            Text(currentScoreText)
                .pulsarMonospacedMetric(.metricMedium)

            Text("Today")
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(RecoveryDetailsDesign.trendGreen)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today’s recovery score \(currentScoreText)")
    }
}
