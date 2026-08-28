import SwiftUI

struct StrainDetailsLoadedContent: View {
    @ObservedObject var viewModel: StrainDetailsViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: StrainDetailsDesign.sectionSpacing) {
            StrainDetailsHeader(dateSubtitle: viewModel.dateSubtitle)
                .strainEntryTransition(
                    isVisible: contentVisible,
                    delay: 0,
                    offset: 8,
                    reduceMotion: reduceMotion
                )

            StrainHeroCard(viewModel: viewModel)
                .strainEntryTransition(
                    isVisible: contentVisible,
                    delay: 0.04,
                    offset: 12,
                    reduceMotion: reduceMotion
                )

            HeartLoadCard(
                chart: viewModel.heartLoadChart,
                peakHeartRate: viewModel.summary.peakHeartRate,
                averageActiveHeartRate: viewModel.summary.averageActiveHeartRate,
                restingHeartRate: viewModel.summary.restingHeartRate
            )
            .strainEntryTransition(
                isVisible: contentVisible,
                delay: 0.10,
                offset: 16,
                reduceMotion: reduceMotion
            )

            MovementSummaryCard(
                steps: viewModel.summary.steps,
                goal: viewModel.summary.stepGoal,
                progress: viewModel.stepProgress
            )
            .strainEntryTransition(
                isVisible: contentVisible,
                delay: 0.16,
                offset: 18,
                reduceMotion: reduceMotion
            )

            StrainInsightsSection(insights: viewModel.insights)
                .strainEntryTransition(
                    isVisible: contentVisible,
                    delay: 0.22,
                    offset: 20,
                    reduceMotion: reduceMotion
                )
        }
        .task {
            if reduceMotion {
                contentVisible = true
            } else {
                withAnimation(.smooth(duration: 0.55)) {
                    contentVisible = true
                }
            }
        }
    }
}
