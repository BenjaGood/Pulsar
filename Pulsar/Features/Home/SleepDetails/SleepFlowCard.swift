import SwiftUI

struct SleepFlowCard: View {
    var summary: SleepSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sleep Flow")
                    .pulsarTextStyle(.sectionHeader)
                    .accessibilityAddTraits(.isHeader)

                Text("Timeline of your sleep stages")
                    .pulsarTextStyle(.metadata)
                    .foregroundStyle(.secondary)
            }

            SleepStageTimelineView(intervals: summary.intervals)
        }
        .padding(SleepDetailsDesign.cardPadding)
        .sleepCardSurface()
    }
}
