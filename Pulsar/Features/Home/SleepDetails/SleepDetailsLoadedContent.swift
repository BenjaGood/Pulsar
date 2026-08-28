import SwiftUI

struct SleepDetailsLoadedContent: View {
    @ObservedObject var viewModel: SleepDetailsViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentVisible = false

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(alignment: .leading, spacing: SleepDetailsDesign.sectionSpacing) {
                SleepDetailsHeader(
                    dateSubtitle: viewModel.dateSubtitle
                )
                .sleepEntryTransition(
                    isVisible: contentVisible,
                    delay: 0,
                    offset: 8,
                    reduceMotion: reduceMotion
                )

                SleepHeroCard(viewModel: viewModel)
                    .sleepEntryTransition(
                        isVisible: contentVisible,
                        delay: 0.04,
                        offset: 14,
                        reduceMotion: reduceMotion
                    )

                SleepFlowCard(summary: viewModel.summary)
                    .sleepEntryTransition(
                        isVisible: contentVisible,
                        delay: 0.10,
                        offset: 18,
                        reduceMotion: reduceMotion
                    )

                SleepBalanceCard(
                    totalSleepText: viewModel.totalSleepText,
                    rows: viewModel.sleepBalanceRows
                )
                .sleepEntryTransition(
                    isVisible: contentVisible,
                    delay: 0.16,
                    offset: 20,
                    reduceMotion: reduceMotion
                )

                SleepMetricsGrid(metrics: viewModel.keyMetricTiles)
                    .sleepEntryTransition(
                        isVisible: contentVisible,
                        delay: 0.22,
                        offset: 22,
                        reduceMotion: reduceMotion
                    )

                SleepInsightsSection(insights: viewModel.insights)
                    .sleepEntryTransition(
                        isVisible: contentVisible,
                        delay: 0.28,
                        offset: 24,
                        reduceMotion: reduceMotion
                    )
            }
        }
        .task {
            if reduceMotion {
                contentVisible = true
            } else {
                withAnimation(.smooth(duration: 0.72)) {
                    contentVisible = true
                }
            }
        }
    }
}
