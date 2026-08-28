import SwiftUI

#Preview("Recovery – iPhone Pro", traits: .fixedLayout(width: 393, height: 852)) {
    NavigationStack {
        RecoveryDetailsView(
            viewModel: RecoveryDetailsViewModel(
                initialSummary: .recoveryReferencePreview,
                profile: MockHealthData.profile,
                date: recoveryPreviewDate,
                provider: PreviewRecoverySummaryProvider(summary: .recoveryReferencePreview),
                calendar: MockHealthData.calendar
            ),
            bottomChromeLayoutStore: PulsarBottomChromeLayoutStore()
        )
    }
}

#Preview("Recovery – Missing Sleep", traits: .fixedLayout(width: 393, height: 852)) {
    NavigationStack {
        RecoveryDetailsView(
            viewModel: RecoveryDetailsViewModel(
                initialSummary: .recoveryPreviewMissingSleep,
                profile: MockHealthData.profile,
                date: recoveryPreviewDate,
                provider: PreviewRecoverySummaryProvider(summary: .recoveryPreviewMissingSleep),
                calendar: MockHealthData.calendar
            ),
            bottomChromeLayoutStore: PulsarBottomChromeLayoutStore()
        )
    }
}

#Preview("Recovery – Small iPhone", traits: .fixedLayout(width: 375, height: 812)) {
    NavigationStack {
        RecoveryDetailsView(
            viewModel: RecoveryDetailsViewModel(
                initialSummary: .recoveryReferencePreview,
                profile: MockHealthData.profile,
                date: recoveryPreviewDate,
                provider: PreviewRecoverySummaryProvider(summary: .recoveryReferencePreview),
                calendar: MockHealthData.calendar
            ),
            bottomChromeLayoutStore: PulsarBottomChromeLayoutStore()
        )
    }
}

#Preview("Recovery – Pro Max", traits: .fixedLayout(width: 440, height: 956)) {
    NavigationStack {
        RecoveryDetailsView(
            viewModel: RecoveryDetailsViewModel(
                initialSummary: .recoveryReferencePreview,
                profile: MockHealthData.profile,
                date: recoveryPreviewDate,
                provider: PreviewRecoverySummaryProvider(summary: .recoveryReferencePreview),
                calendar: MockHealthData.calendar
            ),
            bottomChromeLayoutStore: PulsarBottomChromeLayoutStore()
        )
    }
}

#Preview("Recovery – Trend Card", traits: .fixedLayout(width: 393, height: 320)) {
    ZStack {
        RecoveryDetailsBackground()

        RecoveryTrendCard(
            points: RecoverySummary.recoveryReferencePreview.trend,
            currentScoreText: "67"
        )
        .padding(20)
    }
}

private extension RecoverySummary {
    static var recoveryReferencePreview: RecoverySummary {
        var summary = MockHealthData.recoverySummary
        summary.score = 67
        summary.status = .moderate
        summary.hrvSDNN = 83
        summary.hrvBaseline = 67
        summary.restingHeartRate = 57
        summary.restingHeartRateBaseline = 57
        summary.sleepDuration = TimeInterval((8 * 60 + 13) * 60)
        summary.sleepContribution = 0.86
        summary.strainScore = 64

        let scores = [58.0, 67.0, 53.0, 66.0, 65.0, 52.0, 61.0]
        summary.trend = summary.trend.enumerated().map { index, point in
            var updated = point
            updated.recoveryScore = scores[index % scores.count]
            return updated
        }
        return summary
    }

    static var recoveryPreviewMissingSleep: RecoverySummary {
        var summary = RecoverySummary.recoveryReferencePreview
        summary.sleepDuration = nil
        summary.sleepEfficiency = nil
        summary.deepSleep = nil
        summary.remSleep = nil
        summary.components = summary.components.map { component in
            guard component.title == "Sleep" else { return component }
            var missing = component
            missing.valueText = "Not enough data"
            missing.contribution = nil
            missing.status = .unknown
            missing.detail = "Sleep data was unavailable for this recovery window."
            return missing
        }
        return summary
    }
}

private var recoveryPreviewDate: Date {
    MockHealthData.calendar.date(byAdding: .day, value: -1, to: .now) ?? .now
}

private struct PreviewRecoverySummaryProvider: RecoverySummaryProviding {
    var summary: RecoverySummary

    func recoverySummary(
        profile: UserProfile,
        date: Date,
        calendar: Calendar,
        refreshedAt: Date
    ) async throws -> RecoverySummary {
        var copy = summary
        copy.lastUpdated = refreshedAt
        return copy
    }
}
