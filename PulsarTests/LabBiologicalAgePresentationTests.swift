//
//  LabBiologicalAgePresentationTests.swift
//  PulsarTests
//

import XCTest
@testable import Pulsar

final class LabBiologicalAgePresentationTests: XCTestCase {
    func testGaugeMapsSmallYoungerDeltaCloseToAlignedCenter() {
        let presentation = makePresentation(delta: -0.1)

        XCTAssertEqual(presentation.gaugeProgress, 0.495, accuracy: 0.000_1)
        XCTAssertEqual(presentation.statusText, "↓ 0.1 years younger")
    }

    func testGaugeMapsRepresentativeYoungerAlignedAndOlderStates() {
        XCTAssertEqual(makePresentation(delta: -7).gaugeProgress, 0.15, accuracy: 0.000_1)
        XCTAssertEqual(makePresentation(delta: 0).gaugeProgress, 0.5, accuracy: 0.000_1)
        XCTAssertEqual(makePresentation(delta: 7).gaugeProgress, 0.85, accuracy: 0.000_1)
        XCTAssertEqual(makePresentation(delta: 7).statusText, "↑ 7.0 years older")
    }

    func testGaugeMapsAllRequestedVisualStates() {
        let states: [(delta: Double, progress: Double)] = [
            (-10, 0),
            (-5, 0.25),
            (-1, 0.45),
            (-0.1, 0.495),
            (0, 0.5),
            (0.1, 0.505),
            (1, 0.55),
            (5, 0.75),
            (10, 1)
        ]

        for state in states {
            XCTAssertEqual(
                makePresentation(delta: state.delta).gaugeProgress,
                state.progress,
                accuracy: 0.000_1,
                "Incorrect gauge position for delta \(state.delta)"
            )
        }
    }

    func testGaugeClampsOnlyItsVisualPosition() {
        let younger = makePresentation(delta: -18)
        let older = makePresentation(delta: 21)

        XCTAssertEqual(younger.gaugeProgress, 0, accuracy: 0.000_1)
        XCTAssertEqual(older.gaugeProgress, 1, accuracy: 0.000_1)
        XCTAssertEqual(younger.result.ageDelta, -18)
        XCTAssertEqual(older.result.ageDelta, 21)
    }

    func testAlignmentToleranceAndGrammar() {
        XCTAssertEqual(makePresentation(delta: -0.05).statusText, "Aligned")
        XCTAssertEqual(makePresentation(delta: 0.05).statusText, "Aligned")
        XCTAssertEqual(makePresentation(delta: -1).statusText, "↓ 1.0 year younger")
        XCTAssertEqual(makePresentation(delta: 1).statusText, "↑ 1.0 year older")
    }

    func testConfidenceAndMissingPillarValuesRemainModelDriven() {
        let low = makePresentation(delta: 0, confidence: .low, lifestyleScore: nil)
        let medium = makePresentation(delta: 0, confidence: .medium, lifestyleScore: 72)
        let high = makePresentation(delta: 0, confidence: .high, lifestyleScore: 91)

        XCTAssertEqual(low.confidencePercent, 38)
        XCTAssertEqual(medium.confidencePercent, 68)
        XCTAssertEqual(high.confidencePercent, 92)
        XCTAssertEqual(low.confidenceProgress, 0.38, accuracy: 0.000_1)
        XCTAssertEqual(medium.confidenceProgress, 0.68, accuracy: 0.000_1)
        XCTAssertEqual(high.confidenceProgress, 0.92, accuracy: 0.000_1)
        XCTAssertEqual(low.result.pillarResults[1].statusLabel, "Insufficient data")
        XCTAssertEqual(high.result.pillarResults[1].statusLabel, "Excellent")
    }

    func testBiomarkerRowPresentationUsesQuietMissingState() {
        let presentation = LabBiomarkerRowPresentation(biomarker: LabBiomarker(
            name: "Albumin",
            value: nil,
            unit: "g/dL",
            referenceLow: 3.5,
            referenceHigh: 5,
            status: .missing,
            collectedAt: nil,
            source: .other
        ))

        XCTAssertTrue(presentation.isMissing)
        XCTAssertEqual(presentation.valueText, "--")
        XCTAssertEqual(presentation.referenceText, "3.5 – 5 g/dL")
        XCTAssertEqual(presentation.metadataText, "3.5 – 5 g/dL  |  No collection date")
        XCTAssertTrue(presentation.accessibilityValue.contains("Missing"))
    }

    func testBiomarkerRowPresentationUsesAvailableValueAndDate() {
        let presentation = LabBiomarkerRowPresentation(biomarker: LabBiomarker(
            name: "Albumin",
            value: 4.2,
            unit: "g/dL",
            referenceLow: 3.5,
            referenceHigh: 5,
            status: .optimal,
            collectedAt: Date(timeIntervalSince1970: 1_787_004_000),
            source: .manual
        ))

        XCTAssertFalse(presentation.isMissing)
        XCTAssertEqual(presentation.valueText, "4.2")
        XCTAssertFalse(presentation.metadataText.contains("No collection date"))
        XCTAssertTrue(presentation.accessibilityValue.contains("4.2 g/dL"))
    }

    private func makePresentation(
        delta: Double,
        confidence: LabConfidenceLevel = .low,
        lifestyleScore: Double? = nil
    ) -> LabBiologicalAgePresentation {
        let chronologicalAge = 24.0
        return LabBiologicalAgePresentation(result: BiologicalAgeResult(
            biologicalAge: chronologicalAge + delta,
            chronologicalAge: chronologicalAge,
            ageDelta: delta,
            paceOfAging: nil,
            confidence: confidence,
            updatedAt: .now,
            nextUpdateAt: .now,
            physiologicalScore: 90,
            lifestyleScore: lifestyleScore,
            biomarkerScore: nil,
            physiologicalContributionYears: delta,
            lifestyleContributionYears: 0,
            biomarkerContributionYears: 0,
            missingDataMessages: [],
            wearableDataDays: 20,
            recentBiomarkerCount: 0,
            lifestyleSurveyCompleted: lifestyleScore != nil
        ))
    }
}
