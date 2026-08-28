import SwiftUI

#Preview("Strain – Small iPhone", traits: .fixedLayout(width: 375, height: 812)) {
    NavigationStack {
        StrainDetailsView(
            viewModel: StrainDetailsViewModel(
                initialSummary: MockHealthData.strainSummary,
                profile: MockHealthData.profile,
                date: MockHealthData.calendar.date(
                    from: DateComponents(year: 2026, month: 5, day: 3)
                ) ?? .now,
                recoveryScore: 64,
                recentStrainScores: [48, 55, 62, 57, 66],
                provider: StrainDetailsPreviewProvider(
                    summary: MockHealthData.strainSummary
                ),
                calendar: MockHealthData.calendar
            ),
            bottomChromeLayoutStore: PulsarBottomChromeLayoutStore()
        )
    }
}

#Preview("Strain – iPhone Pro", traits: .fixedLayout(width: 393, height: 852)) {
    NavigationStack {
        StrainDetailsView(
            viewModel: StrainDetailsViewModel(
                initialSummary: MockHealthData.strainSummary,
                profile: MockHealthData.profile,
                date: MockHealthData.calendar.date(
                    from: DateComponents(year: 2026, month: 5, day: 3)
                ) ?? .now,
                recoveryScore: 64,
                recentStrainScores: [48, 55, 62, 57, 66],
                provider: StrainDetailsPreviewProvider(
                    summary: MockHealthData.strainSummary
                ),
                calendar: MockHealthData.calendar
            ),
            bottomChromeLayoutStore: PulsarBottomChromeLayoutStore()
        )
    }
}

#Preview("Strain – Pro Max", traits: .fixedLayout(width: 440, height: 956)) {
    NavigationStack {
        StrainDetailsView(
            viewModel: StrainDetailsViewModel(
                initialSummary: MockHealthData.strainSummary,
                profile: MockHealthData.profile,
                date: MockHealthData.calendar.date(
                    from: DateComponents(year: 2026, month: 5, day: 3)
                ) ?? .now,
                recoveryScore: 64,
                recentStrainScores: [48, 55, 62, 57, 66],
                provider: StrainDetailsPreviewProvider(
                    summary: MockHealthData.strainSummary
                ),
                calendar: MockHealthData.calendar
            ),
            bottomChromeLayoutStore: PulsarBottomChromeLayoutStore()
        )
    }
}

#Preview("Strain – Supporting Cards", traits: .fixedLayout(width: 393, height: 1200)) {
    let viewModel = StrainDetailsViewModel(
        initialSummary: MockHealthData.strainSummary,
        profile: MockHealthData.profile,
        date: MockHealthData.calendar.date(
            from: DateComponents(year: 2026, month: 5, day: 3)
        ) ?? .now,
        recoveryScore: 64,
        recentStrainScores: [48, 55, 62, 57, 66],
        provider: StrainDetailsPreviewProvider(
            summary: MockHealthData.strainSummary
        ),
        calendar: MockHealthData.calendar
    )

    ScrollView {
        VStack(spacing: StrainDetailsDesign.sectionSpacing) {
            HeartLoadCard(
                chart: viewModel.heartLoadChart,
                peakHeartRate: viewModel.summary.peakHeartRate,
                averageActiveHeartRate: viewModel.summary.averageActiveHeartRate,
                restingHeartRate: viewModel.summary.restingHeartRate
            )

            MovementSummaryCard(
                steps: viewModel.summary.steps,
                goal: viewModel.summary.stepGoal,
                progress: viewModel.stepProgress
            )

            StrainInsightsSection(insights: viewModel.insights)
        }
        .padding(StrainDetailsDesign.pagePadding)
    }
    .scrollIndicators(.hidden)
    .background(StrainDetailsBackground())
}
