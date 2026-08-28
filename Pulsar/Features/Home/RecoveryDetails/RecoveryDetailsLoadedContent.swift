import SwiftUI

struct RecoveryDetailsLoadedContent: View {
    @ObservedObject var viewModel: RecoveryDetailsViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentVisible = false

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(alignment: .leading, spacing: RecoveryDetailsDesign.sectionSpacing) {
                RecoveryDetailsHeader(dateSubtitle: viewModel.dateSubtitle)
                    .recoveryEntryTransition(
                        isVisible: contentVisible,
                        delay: 0,
                        offset: 8,
                        reduceMotion: reduceMotion
                    )

                RecoveryHeroView(
                    scoreText: viewModel.scoreText,
                    score: viewModel.summary.score,
                    status: viewModel.summary.status
                )
                .recoveryEntryTransition(
                    isVisible: contentVisible,
                    delay: 0.04,
                    offset: 12,
                    reduceMotion: reduceMotion
                )

                RecoveryDriversCard(drivers: viewModel.recoveryDrivers)
                    .recoveryEntryTransition(
                        isVisible: contentVisible,
                        delay: 0.08,
                        offset: 14,
                        reduceMotion: reduceMotion
                    )

                RecoveryTrendCard(
                    points: viewModel.summary.trend,
                    currentScoreText: viewModel.scoreText
                )
                    .recoveryEntryTransition(
                        isVisible: contentVisible,
                        delay: 0.12,
                        offset: 16,
                        reduceMotion: reduceMotion
                    )

                RecoveryInsightsCard(insights: viewModel.insights)
                    .recoveryEntryTransition(
                        isVisible: contentVisible,
                        delay: 0.16,
                        offset: 18,
                        reduceMotion: reduceMotion
                    )
            }
        }
        .task {
            if reduceMotion {
                contentVisible = true
            } else {
                withAnimation(.smooth(duration: 0.58)) {
                    contentVisible = true
                }
            }
        }
    }
}
