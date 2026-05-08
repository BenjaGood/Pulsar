//
//  ScoringEngineTests.swift
//  PulsarTests
//

import XCTest
@testable import Pulsar

final class ScoringEngineTests: XCTestCase {
    func testSleepPerformanceUsesDurationEfficiencyRegularityAndContinuity() {
        let summary = SleepScoringEngine(calendar: MockHealthData.calendar).score(
            night: MockHealthData.sleepNight,
            recentNights: MockHealthData.recentSleepNights,
            schedule: MockHealthData.profile.sleepSchedule
        )

        XCTAssertGreaterThan(summary.totalSleepMinutes, 430)
        XCTAssertEqual(Int(summary.awakeMinutes), 36)
        XCTAssertEqual(summary.confidence, .high)
        XCTAssertGreaterThan(summary.score, 70)
        XCTAssertLessThanOrEqual(summary.stageBreakdown.first(where: { $0.stage == .deep })?.percentOfSleep ?? 0, 0.20)
    }

    func testBinarySleepDegradesConfidenceButStillScores() {
        let start = MockHealthData.calendar.date(from: DateComponents(year: 2026, month: 5, day: 1, hour: 23))!
        let end = MockHealthData.calendar.date(byAdding: .hour, value: 7, to: start)!
        let night = NightlySleepInput(
            nightStart: start,
            nightEnd: end,
            segments: [SleepSegment(stage: .asleepUnspecified, start: start, end: end, provenance: .sample)]
        )

        let summary = SleepScoringEngine(calendar: MockHealthData.calendar).score(night: night, recentNights: [], schedule: MockHealthData.profile.sleepSchedule)

        XCTAssertEqual(summary.confidence, .moderate)
        XCTAssertGreaterThan(summary.score, 60)
        XCTAssertTrue(summary.notes.contains { $0.contains("Stage data is unavailable") })
    }

    func testRecoveryIsBaselineRelativeAndWinsorized() {
        let summary = RecoveryScoringEngine().score(today: MockHealthData.todayBiometrics, baselineDays: MockHealthData.baselineBiometrics)

        XCTAssertEqual(summary.confidence, .high)
        XCTAssertGreaterThan(summary.hrvReadiness, 0.5)
        XCTAssertGreaterThan(summary.restingHeartRateReadiness, 0.5)
        XCTAssertGreaterThan(summary.score, 60)
        XCTAssertTrue(summary.explanation.contains("HRV"))
    }

    func testRecoveryRequiresSufficientBaselineForPhysiologyContributors() {
        let summary = RecoveryScoringEngine().score(
            today: MockHealthData.todayBiometrics,
            baselineDays: Array(MockHealthData.baselineBiometrics.prefix(3))
        )

        XCTAssertEqual(summary.confidence, .low)
        XCTAssertEqual(summary.hrvReadiness, 0)
        XCTAssertGreaterThan(summary.sleepContribution, 0)
    }

    func testStrainUsesEdwardsZoneLoadBeforeMovement() {
        let summary = StrainScoringEngine().score(input: MockHealthData.strainInput)

        XCTAssertEqual(summary.confidence, .high)
        XCTAssertGreaterThan(summary.workoutLoad, summary.movementLoad)
        XCTAssertEqual(summary.timeInZones.count, 5)
        XCTAssertGreaterThan(summary.timeInZones.first(where: { $0.zone == 4 })?.minutes ?? 0, 0)
        XCTAssertGreaterThan(summary.score, 50)
    }

    func testMorningNoActivityStrainStaysLowDespiteRecentHistory() {
        let date = MockHealthData.calendar.date(from: DateComponents(year: 2026, month: 5, day: 3, hour: 7))!
        let input = DailyStrainInput(
            date: date,
            maxHeartRate: 188,
            workouts: [],
            activity: DailyActivityInput(
                date: date,
                steps: 250,
                activeEnergyKilocalories: 18,
                basalEnergyKilocalories: 420,
                distanceMeters: 140,
                exerciseMinutes: 0,
                provenance: [.sample]
            ),
            recentRawLoads: Array(repeating: 4, count: 28),
            sevenDayRawLoad: 28,
            twentyEightDayRawLoad: 112
        )

        let summary = StrainScoringEngine().score(input: input, dayHeartRateSamples: [], restingHeartRate: 52)

        XCTAssertLessThanOrEqual(summary.score, 10)
    }

    func testRecoveryOnlySetsRecommendedStrainTarget() {
        let lowActivityMetric = PulsarSharedMetricCalculator.makeStrainMetric(
            activity: PulsarSharedActivityInput(steps: 400, activeEnergyKilocalories: 25, exerciseMinutes: 0),
            workouts: [],
            recentRawLoads: Array(repeating: 2, count: 28),
            computedAt: Date()
        )
        let targetRange = PulsarSharedMetricCalculator.recommendedStrainTargetRange(forRecoveryScore: 92)

        XCTAssertNotNil(lowActivityMetric)
        XCTAssertLessThanOrEqual(lowActivityMetric?.score ?? 100, 10)
        XCTAssertEqual(targetRange?.lowerBound, 68)
        XCTAssertEqual(targetRange?.upperBound, 86)
    }

    func testModerateStrengthDayDoesNotInflateToPeakStrain() {
        let date = MockHealthData.calendar.date(from: DateComponents(year: 2026, month: 5, day: 4, hour: 12))!
        let workout = PulsarSharedWorkoutInput(
            type: "Traditional Strength Training",
            durationMinutes: 43,
            activeEnergyKilocalories: 190,
            averageHeartRate: 104,
            peakHeartRate: 132,
            sourceName: "Apple Watch"
        )
        let metric = PulsarSharedMetricCalculator.makeStrainMetric(
            activity: PulsarSharedActivityInput(
                steps: 5_537,
                activeEnergyKilocalories: 360,
                basalEnergyKilocalories: 1_568,
                distanceMeters: 4_200,
                exerciseMinutes: 43,
                averageElevatedHeartRate: 86,
                peakHeartRate: 132,
                restingHeartRate: 64,
                maxHeartRate: 188
            ),
            workouts: [workout],
            recentRawLoads: Array(repeating: 35, count: 7),
            computedAt: date
        )

        XCTAssertNotNil(metric)
        XCTAssertGreaterThanOrEqual(metric?.score ?? 0, 45)
        XCTAssertLessThanOrEqual(metric?.score ?? 100, 60)
    }

    func testTotalEnergyLikeInputCannotCreatePeakStrainByItself() {
        let date = MockHealthData.calendar.date(from: DateComponents(year: 2026, month: 5, day: 4, hour: 12))!
        let metric = PulsarSharedMetricCalculator.makeStrainMetric(
            activity: PulsarSharedActivityInput(
                steps: 5_537,
                activeEnergyKilocalories: 1_928,
                basalEnergyKilocalories: 1_568,
                distanceMeters: 4_200,
                exerciseMinutes: 43,
                averageElevatedHeartRate: 86,
                peakHeartRate: 132,
                restingHeartRate: 64,
                maxHeartRate: 188
            ),
            workouts: [
                PulsarSharedWorkoutInput(
                    type: "Traditional Strength Training",
                    durationMinutes: 43,
                    activeEnergyKilocalories: 190,
                    averageHeartRate: 104,
                    peakHeartRate: 132,
                    sourceName: "Apple Watch"
                )
            ],
            recentRawLoads: Array(repeating: 35, count: 7),
            computedAt: date
        )

        XCTAssertNotNil(metric)
        XCTAssertLessThanOrEqual(metric?.score ?? 100, 65)
    }

    func testMaxHeartRateFallsBackOnlyWhenManualValueIsMissing() {
        var profile = MockHealthData.profile
        profile.manualMaxHeartRate = nil

        let resolution = profile.resolvedMaxHeartRate(on: MockHealthData.calendar.date(from: DateComponents(year: 2026, month: 5, day: 3))!, calendar: MockHealthData.calendar)

        XCTAssertEqual(resolution?.source, .fallbackTanaka)
        XCTAssertEqual(Int((resolution?.value ?? 0).rounded()), 186)
    }
}
