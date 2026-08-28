import XCTest
@testable import Pulsar

final class StressInsightFactoryTests: XCTestCase {
    func testLowStressUsesCurrentPhysiologyForContextualCards() {
        let summary = MockHealthData.stressPreviewSummary(score: 18)

        let insights = StressInsightFactory.insights(for: summary)

        XCTAssertEqual(insights.first?.id, "physiological-load")
        XCTAssertEqual(insights.first?.title, "Your body appears relaxed")
        XCTAssertTrue(insights.contains { $0.id == "recovery-contribution" })
        XCTAssertTrue(insights.contains { $0.id == "movement-adjustment" })
        XCTAssertTrue((2...4).contains(insights.count))
    }

    func testMissingWorkoutLoadCreatesAvailabilityInsight() {
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

        let insight = StressInsightFactory.insights(for: summary)
            .first { $0.id == "signal-availability" }

        XCTAssertEqual(insight?.title, "More data improves accuracy")
        XCTAssertTrue(insight?.description.contains("Recent workout load") == true)
    }

    func testMissingStressStillProducesContextInsteadOfStaticHelp() {
        let insights = StressInsightFactory.insights(for: .missing)

        XCTAssertTrue((2...4).contains(insights.count))
        XCTAssertEqual(insights.first?.id, "no-current-estimate")
        XCTAssertTrue(insights.contains { $0.id == "signal-availability" })
    }
}
