import XCTest
@testable import Pulsar

final class HealthMetricStatusClassifierTests: XCTestCase {
    func testHRVUsesRecentBaselineWhenAvailable() {
        let classifier = HealthMetricStatusClassifier()

        let assessment = classifier.hrv(
            current: 72,
            baseline: [54, 56, 57, 58, 55, 59, 56]
        )

        XCTAssertEqual(assessment.status, .higher)
        XCTAssertEqual(assessment.referenceValue ?? 0, 56, accuracy: 0.5)
        XCTAssertEqual(assessment.comparisonText, "Higher than your recent baseline.")
    }

    func testOxygenSaturationFallsBackToConservativeRange() {
        let classifier = HealthMetricStatusClassifier()

        let assessment = classifier.oxygenSaturation(
            current: 0.93,
            baseline: []
        )

        XCTAssertEqual(assessment.status, .lower)
        XCTAssertNil(assessment.referenceValue)
        XCTAssertEqual(assessment.comparisonText, "Below a conservative general range.")
    }

    func testSleepFallsBackToTargetWhenHistoryIsShort() {
        let classifier = HealthMetricStatusClassifier()

        let assessment = classifier.sleepDuration(
            current: 360,
            baseline: [440, 450],
            targetMinutes: 480
        )

        XCTAssertEqual(assessment.status, .lower)
        XCTAssertEqual(assessment.referenceValue ?? 0, 480, accuracy: 0.1)
        XCTAssertEqual(assessment.comparisonText, "Lower than your current sleep target.")
    }

    func testNoDataStatusIsReturnedWhenMetricIsMissing() {
        let classifier = HealthMetricStatusClassifier()

        let assessment = classifier.respiratoryRate(
            current: nil,
            baseline: [13.8, 14.1, 14.0, 13.9, 14.2]
        )

        XCTAssertEqual(assessment.status, .noData)
        XCTAssertNil(assessment.referenceValue)
        XCTAssertEqual(assessment.comparisonText, "No HealthKit data was available for this metric on the selected day.")
    }
}
