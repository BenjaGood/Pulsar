//
//  StressEngineTests.swift
//  PulsarTests
//

import XCTest
@testable import Pulsar

final class StressEngineTests: XCTestCase {
    func testBaselineBuilderUsesRollingPersonalBaselines() {
        let baseline = StressBaselineBuilder().build(from: MockHealthData.stressBaselineSignals)

        XCTAssertEqual(baseline.validDayCount, 21)
        XCTAssertEqual(baseline.hrvSDNN?.sampleCount, 21)
        XCTAssertEqual(baseline.restingHeartRate?.sampleCount, 21)
        XCTAssertEqual(baseline.recentWorkoutLoad?.sampleCount, 21)
        XCTAssertTrue(baseline.isSufficient)
    }

    func testStressScoreUsesBaselineRelativeContributors() {
        var today = MockHealthData.stressTodaySignals
        today.heartRateVariabilitySDNN = 44
        today.heartRateVariabilityTimestamp = today.date.addingTimeInterval(10 * 60 * 60)
        today.restingHeartRate = 62
        today.sleepRespiratoryRate = 15.6
        today.wristTemperatureDelta = 0.28
        today.sleepDurationHours = 5.8
        today.sleepInterruptions = 8
        today.recentWorkoutLoad = 150
        today.currentHeartRate = 88
        today.currentHeartRateTimestamp = today.date.addingTimeInterval(11 * 60 * 60)
        today.recentHeartRate = 88
        today.computedAt = today.currentHeartRateTimestamp

        let summary = StressEngine().score(today: today, baselineDays: MockHealthData.stressBaselineSignals)

        XCTAssertNotNil(summary.score)
        XCTAssertEqual(summary.confidence, .high)
        XCTAssertGreaterThanOrEqual(summary.score ?? 0, 60)
        XCTAssertEqual(summary.level, summary.score.map(StressLevel.level(for:)))
        XCTAssertFalse(summary.drivers.isEmpty)
        XCTAssertFalse(summary.signals.isEmpty)
        XCTAssertTrue(summary.driverInsights.contains { $0.contains("HRV") || $0.contains("heart rate") || $0.contains("HR and HRV") })
    }

    func testBevelLikeMediumSignalsDoNotInflateToHighStress() {
        let day = MockHealthData.calendar.date(from: DateComponents(year: 2026, month: 5, day: 7))!
        let measuredAt = day.addingTimeInterval(13 * 60 * 60)
        let today = StressDailySignals(
            date: day,
            computedAt: measuredAt,
            heartRateVariabilitySDNN: 36,
            heartRateVariabilityTimestamp: measuredAt.addingTimeInterval(-45 * 60),
            restingHeartRate: 60,
            walkingHeartRateAverage: 82,
            sleepRespiratoryRate: 15,
            currentMotionContext: .resting,
            currentHeartRate: 68,
            currentHeartRateTimestamp: measuredAt.addingTimeInterval(-3 * 60),
            recentHeartRate: 68,
            minutesSinceWorkout: 240,
            recentSteps: 12,
            recentActiveEnergyKilocalories: 1.5,
            recentExerciseMinutes: 0,
            overnightWearMinutes: 460,
            signalQuality: nil,
            sourceBadges: [.sample]
        )

        let summary = StressEngine().score(today: today, baselineDays: stressBaseline(day: day, hrv: 44, restingHeartRate: 60, walkingHeartRate: 82))

        XCTAssertNotNil(summary.score)
        XCTAssertLessThan(summary.score ?? 100, 60)
        XCTAssertEqual(summary.level, summary.score.map(StressLevel.level(for:)))
        XCTAssertNotEqual(summary.level, .high)
    }

    func testElevatedHeartRateAndLowHRVIncreaseStressAboveNormal() {
        let day = MockHealthData.calendar.date(from: DateComponents(year: 2026, month: 5, day: 7))!
        let measuredAt = day.addingTimeInterval(13 * 60 * 60)
        let baseline = stressBaseline(day: day, hrv: 58, restingHeartRate: 56, walkingHeartRate: 76)
        let calm = StressDailySignals(
            date: day,
            computedAt: measuredAt,
            heartRateVariabilitySDNN: 62,
            heartRateVariabilityTimestamp: measuredAt.addingTimeInterval(-20 * 60),
            restingHeartRate: 56,
            walkingHeartRateAverage: 76,
            currentMotionContext: .resting,
            currentHeartRate: 60,
            currentHeartRateTimestamp: measuredAt.addingTimeInterval(-2 * 60),
            recentHeartRate: 60,
            recentSteps: 0,
            recentActiveEnergyKilocalories: 0,
            recentExerciseMinutes: 0,
            sourceBadges: [.sample]
        )
        var stressed = calm
        stressed.heartRateVariabilitySDNN = 34
        stressed.currentHeartRate = 86
        stressed.recentHeartRate = 86

        let calmSummary = StressEngine().score(today: calm, baselineDays: baseline)
        let stressedSummary = StressEngine().score(today: stressed, baselineDays: baseline)

        XCTAssertNotNil(calmSummary.score)
        XCTAssertNotNil(stressedSummary.score)
        XCTAssertGreaterThan((stressedSummary.score ?? 0) - (calmSummary.score ?? 0), 20)
        XCTAssertGreaterThanOrEqual(stressedSummary.score ?? 0, 50)
    }

    func testLowHRVAloneCannotCreateHighStress() {
        let day = MockHealthData.calendar.date(from: DateComponents(year: 2026, month: 5, day: 7))!
        let measuredAt = day.addingTimeInterval(12 * 60 * 60)
        let today = StressDailySignals(
            date: day,
            computedAt: measuredAt,
            heartRateVariabilitySDNN: 28,
            heartRateVariabilityTimestamp: measuredAt.addingTimeInterval(-30 * 60),
            restingHeartRate: 60,
            walkingHeartRateAverage: 82,
            currentMotionContext: .resting,
            currentHeartRate: 61,
            currentHeartRateTimestamp: measuredAt.addingTimeInterval(-2 * 60),
            recentHeartRate: 61,
            recentSteps: 0,
            recentActiveEnergyKilocalories: 0,
            recentExerciseMinutes: 0,
            overnightWearMinutes: 460,
            sourceBadges: [.sample]
        )

        let summary = StressEngine().score(today: today, baselineDays: stressBaseline(day: day, hrv: 44, restingHeartRate: 60, walkingHeartRate: 82))

        XCTAssertNotNil(summary.score)
        XCTAssertLessThanOrEqual(summary.score ?? 100, 56)
        XCTAssertNotEqual(summary.level, .high)
    }

    func testMovementDiscountPreventsActivityHeartRateFromBecomingStress() {
        let day = MockHealthData.calendar.date(from: DateComponents(year: 2026, month: 5, day: 7))!
        let measuredAt = day.addingTimeInterval(15 * 60 * 60)
        let today = StressDailySignals(
            date: day,
            computedAt: measuredAt,
            heartRateVariabilitySDNN: 36,
            heartRateVariabilityTimestamp: measuredAt.addingTimeInterval(-50 * 60),
            restingHeartRate: 60,
            walkingHeartRateAverage: 82,
            currentMotionContext: .active,
            currentHeartRate: 104,
            currentHeartRateTimestamp: measuredAt.addingTimeInterval(-2 * 60),
            recentHeartRate: 104,
            recentSteps: 520,
            recentActiveEnergyKilocalories: 22,
            recentExerciseMinutes: 4,
            overnightWearMinutes: 460,
            sourceBadges: [.sample]
        )

        let summary = StressEngine().score(today: today, baselineDays: stressBaseline(day: day, hrv: 44, restingHeartRate: 60, walkingHeartRate: 82))

        XCTAssertNotNil(summary.score)
        XCTAssertLessThan(summary.score ?? 100, 70)
        XCTAssertTrue(summary.driverInsights.contains { $0.localizedCaseInsensitiveContains("movement") })
    }

    func testStressPausesDuringWorkoutAndCooldown() {
        let day = MockHealthData.calendar.date(from: DateComponents(year: 2026, month: 5, day: 7))!
        let measuredAt = day.addingTimeInterval(16 * 60 * 60)
        var workout = StressDailySignals(
            date: day,
            computedAt: measuredAt,
            heartRateVariabilitySDNN: 36,
            heartRateVariabilityTimestamp: measuredAt.addingTimeInterval(-45 * 60),
            restingHeartRate: 60,
            walkingHeartRateAverage: 82,
            currentMotionContext: .workout,
            currentHeartRate: 142,
            currentHeartRateTimestamp: measuredAt.addingTimeInterval(-2 * 60),
            recentHeartRate: 142,
            minutesSinceWorkout: 0,
            recentSteps: 900,
            recentActiveEnergyKilocalories: 45,
            recentExerciseMinutes: 8,
            sourceBadges: [.sample]
        )
        let baseline = stressBaseline(day: day, hrv: 44, restingHeartRate: 60, walkingHeartRate: 82)

        let workoutSummary = StressEngine().score(today: workout, baselineDays: baseline)
        XCTAssertNil(workoutSummary.score)
        XCTAssertEqual(workoutSummary.state, .workoutPaused)

        workout.currentMotionContext = .postWorkout
        workout.minutesSinceWorkout = 8
        workout.lastWorkoutEnd = measuredAt.addingTimeInterval(-8 * 60)

        let cooldownSummary = StressEngine().score(today: workout, baselineDays: baseline)
        XCTAssertNil(cooldownSummary.score)
        XCTAssertEqual(cooldownSummary.state, .cooldown)

        workout.minutesSinceWorkout = 20
        workout.lastWorkoutEnd = measuredAt.addingTimeInterval(-20 * 60)

        let decayedCooldownSummary = StressEngine().score(today: workout, baselineDays: baseline)
        XCTAssertNotNil(decayedCooldownSummary.score)
        XCTAssertNotEqual(decayedCooldownSummary.state, .cooldown)
        XCTAssertLessThan(decayedCooldownSummary.score ?? 100, 65)
    }

    func testRecentMovementUpgradesInactiveContextBeforeScoring() {
        let day = MockHealthData.calendar.date(from: DateComponents(year: 2026, month: 5, day: 7))!
        let measuredAt = day.addingTimeInterval(15 * 60 * 60)
        let today = StressDailySignals(
            date: day,
            computedAt: measuredAt,
            heartRateVariabilitySDNN: 36,
            heartRateVariabilityTimestamp: measuredAt.addingTimeInterval(-45 * 60),
            restingHeartRate: 60,
            walkingHeartRateAverage: 82,
            currentMotionContext: .resting,
            currentHeartRate: 108,
            currentHeartRateTimestamp: measuredAt.addingTimeInterval(-2 * 60),
            recentHeartRate: 108,
            recentSteps: 620,
            recentActiveEnergyKilocalories: 24,
            recentExerciseMinutes: 4,
            sourceBadges: [.sample]
        )

        let summary = StressEngine().score(today: today, baselineDays: stressBaseline(day: day, hrv: 44, restingHeartRate: 60, walkingHeartRate: 82))

        XCTAssertNotNil(summary.score)
        XCTAssertEqual(summary.movementStateText, PulsarSharedStressMovementState.activeMovement.displayText)
        XCTAssertLessThan(summary.score ?? 100, 70)
    }

    func testMissingHRVUsesPartialConfidenceInsteadOfUnavailable() {
        let day = MockHealthData.calendar.date(from: DateComponents(year: 2026, month: 5, day: 7))!
        let measuredAt = day.addingTimeInterval(13 * 60 * 60)
        let today = StressDailySignals(
            date: day,
            computedAt: measuredAt,
            heartRateVariabilitySDNN: nil,
            restingHeartRate: 58,
            walkingHeartRateAverage: 78,
            currentMotionContext: .resting,
            currentHeartRate: 82,
            currentHeartRateTimestamp: measuredAt.addingTimeInterval(-2 * 60),
            recentHeartRate: 82,
            recentSteps: 0,
            recentActiveEnergyKilocalories: 0,
            recentExerciseMinutes: 0,
            sourceBadges: [.sample]
        )

        let summary = StressEngine().score(today: today, baselineDays: stressBaseline(day: day, hrv: 48, restingHeartRate: 58, walkingHeartRate: 78))

        XCTAssertNotNil(summary.score)
        XCTAssertEqual(summary.confidence, .moderate)
        XCTAssertNotEqual(summary.state, .noData)
        XCTAssertTrue(summary.signals.contains { $0.id == "hrv" && $0.availability == .unavailable })
    }

    func testStressCategoriesUseSharedFourBandScale() {
        XCTAssertEqual(StressLevel.level(for: 24), .low)
        XCTAssertEqual(StressLevel.level(for: 25), .balanced)
        XCTAssertEqual(StressLevel.level(for: 49), .balanced)
        XCTAssertEqual(StressLevel.level(for: 50), .elevated)
        XCTAssertEqual(StressLevel.level(for: 74), .elevated)
        XCTAssertEqual(StressLevel.level(for: 75), .high)
        XCTAssertEqual(StressLevel.legacyLevel(named: "Very High"), .high)
        XCTAssertEqual(PulsarSharedMetricCalculator.stressLevelText(score: 86), "High")
    }

    func testStressTimelineBuilderKeepsBalancedDaysOutOfHighZone() {
        let calendar = MockHealthData.calendar
        let day = calendar.date(from: DateComponents(year: 2026, month: 5, day: 3))!
        let interval = DateInterval(start: day, end: calendar.date(bySettingHour: 13, minute: 0, second: 0, of: day)!)
        let baseline = StressBaselineBuilder().build(from: MockHealthData.stressBaselineSignals)
        var summary = MockHealthData.stressPreviewSummary(score: 45)
        summary.score = 45
        summary.level = .balanced
        summary.confidence = .high

        let heartSamples: [HeartRateSample] = [
            heartSample(day: day, hour: 1, minute: 0, bpm: 50, calendar: calendar),
            heartSample(day: day, hour: 2, minute: 0, bpm: 51, calendar: calendar),
            heartSample(day: day, hour: 3, minute: 0, bpm: 50, calendar: calendar),
            heartSample(day: day, hour: 4, minute: 0, bpm: 52, calendar: calendar),
            heartSample(day: day, hour: 5, minute: 0, bpm: 53, calendar: calendar),
            heartSample(day: day, hour: 6, minute: 0, bpm: 55, calendar: calendar),
            heartSample(day: day, hour: 7, minute: 30, bpm: 138, calendar: calendar),
            heartSample(day: day, hour: 8, minute: 30, bpm: 92, calendar: calendar),
            heartSample(day: day, hour: 9, minute: 30, bpm: 84, calendar: calendar),
            heartSample(day: day, hour: 10, minute: 30, bpm: 78, calendar: calendar),
            heartSample(day: day, hour: 11, minute: 30, bpm: 76, calendar: calendar),
            heartSample(day: day, hour: 12, minute: 30, bpm: 74, calendar: calendar)
        ]

        let samples = StressTimelinePointBuilder(maximumSampleCount: 16).samples(
            summary: summary,
            today: MockHealthData.stressTodaySignals,
            baseline: baseline,
            heartSamples: heartSamples,
            sleep: MockHealthData.sleepSummary,
            strain: MockHealthData.strainSummary,
            interval: interval,
            referenceDate: interval.end
        )
        let average = PulsarStressTimelineDistribution.weightedAverage(
            samples: samples.map { PulsarStressTimelineSample(timestamp: $0.timestamp, score: $0.score) },
            range: interval
        )

        XCTAssertGreaterThanOrEqual(samples.count, 2)
        XCTAssertTrue(samples.allSatisfy { (0...100).contains($0.score) })
        XCTAssertTrue(samples.filter { $0.context == .sleep }.allSatisfy { $0.score < PulsarStressScale.balancedUpperBound })
        XCTAssertLessThan(average ?? 100, PulsarStressScale.elevatedUpperBound)
    }

    func testStressDurationBucketsIgnoreSparseGaps() {
        let calendar = MockHealthData.calendar
        let day = calendar.date(from: DateComponents(year: 2026, month: 5, day: 3))!
        let samples = [
            PulsarStressTimelineSample(timestamp: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)!, score: 34),
            PulsarStressTimelineSample(timestamp: calendar.date(bySettingHour: 9, minute: 30, second: 0, of: day)!, score: 38),
            PulsarStressTimelineSample(timestamp: calendar.date(bySettingHour: 14, minute: 0, second: 0, of: day)!, score: 90)
        ]

        let buckets = PulsarStressTimelineDistribution.buckets(samples: samples)
        let total = buckets.reduce(0) { $0 + $1.duration }
        let balanced = buckets.first { $0.category == .balanced }?.duration ?? 0
        let high = buckets.first { $0.category == .high }?.duration ?? 0

        XCTAssertEqual(total, 30 * 60, accuracy: 0.5)
        XCTAssertEqual(balanced, 30 * 60, accuracy: 0.5)
        XCTAssertEqual(high, 0, accuracy: 0.5)
    }

    func testStressScoreIsDeterministicForSameInputs() {
        let engine = StressEngine()
        let first = engine.score(today: MockHealthData.stressTodaySignals, baselineDays: MockHealthData.stressBaselineSignals)
        let second = engine.score(today: MockHealthData.stressTodaySignals, baselineDays: MockHealthData.stressBaselineSignals)

        XCTAssertEqual(first.score, second.score)
        XCTAssertEqual(first.level, second.level)
        XCTAssertEqual(first.confidence, second.confidence)
        XCTAssertEqual(first.driverInsights, second.driverInsights)
        XCTAssertEqual(first.signals, second.signals)
    }

    func testStressSummaryCacheReturnsSameSummaryForSameInputHash() {
        let suiteName = "pulsar.tests.stress.cache.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cache = StressSummaryCache(defaults: defaults)
        let summary = StressEngine().score(today: MockHealthData.stressTodaySignals, baselineDays: MockHealthData.stressBaselineSignals)

        cache.save(summary, for: "2026-05-03", inputHash: "stable-input", calculatedAt: Date())

        XCTAssertEqual(cache.summary(for: "2026-05-03", inputHash: "stable-input"), summary)
        XCTAssertNil(cache.summary(for: "2026-05-03", inputHash: "changed-input"))
    }

    func testStressInputFingerprintIsStableForSameSourceData() {
        let day = MockHealthData.stressTodaySignals.date
        let queryStart = Calendar.current.startOfDay(for: day)
        let referenceDate = queryStart.addingTimeInterval(12 * 60 * 60)
        let heartSamples = MockHealthData.strainInput.workouts.flatMap(\.heartRateSamples)

        let first = StressInputFingerprint.make(
            dateKey: "2026-05-03",
            queryStart: queryStart,
            referenceDate: referenceDate,
            today: MockHealthData.stressTodaySignals,
            baselineDays: MockHealthData.stressBaselineSignals,
            heartSamples: heartSamples,
            sleep: MockHealthData.sleepSummary,
            strain: MockHealthData.strainSummary
        )
        let second = StressInputFingerprint.make(
            dateKey: "2026-05-03",
            queryStart: queryStart,
            referenceDate: referenceDate,
            today: MockHealthData.stressTodaySignals,
            baselineDays: MockHealthData.stressBaselineSignals,
            heartSamples: heartSamples,
            sleep: MockHealthData.sleepSummary,
            strain: MockHealthData.strainSummary
        )

        XCTAssertEqual(first, second)
    }

    func testStressInputFingerprintChangesWhenRealInputChanges() {
        let day = MockHealthData.stressTodaySignals.date
        let queryStart = Calendar.current.startOfDay(for: day)
        let referenceDate = queryStart.addingTimeInterval(12 * 60 * 60)
        var changedToday = MockHealthData.stressTodaySignals
        changedToday.currentHeartRate = (changedToday.currentHeartRate ?? 70) + 8

        let stable = StressInputFingerprint.make(
            dateKey: "2026-05-03",
            queryStart: queryStart,
            referenceDate: referenceDate,
            today: MockHealthData.stressTodaySignals,
            baselineDays: MockHealthData.stressBaselineSignals,
            heartSamples: MockHealthData.strainInput.workouts.flatMap(\.heartRateSamples),
            sleep: MockHealthData.sleepSummary,
            strain: MockHealthData.strainSummary
        )
        let changed = StressInputFingerprint.make(
            dateKey: "2026-05-03",
            queryStart: queryStart,
            referenceDate: referenceDate,
            today: changedToday,
            baselineDays: MockHealthData.stressBaselineSignals,
            heartSamples: MockHealthData.strainInput.workouts.flatMap(\.heartRateSamples),
            sleep: MockHealthData.sleepSummary,
            strain: MockHealthData.strainSummary
        )

        XCTAssertNotEqual(stable, changed)
    }

    func testStressScoreToleratesMissingTemperatureAndRenormalizes() {
        var today = MockHealthData.stressTodaySignals
        today.wristTemperatureDelta = nil
        let baselineDays = MockHealthData.stressBaselineSignals.map { day -> StressDailySignals in
            var copy = day
            copy.wristTemperatureDelta = nil
            return copy
        }

        let summary = StressEngine().score(today: today, baselineDays: baselineDays)

        XCTAssertNotNil(summary.score)
        XCTAssertGreaterThanOrEqual(summary.availableSignalCount, 4)
        XCTAssertTrue(summary.signals.contains { $0.id == "heart-rate" })
        XCTAssertTrue(summary.signals.contains { $0.id == "hrv" })
        XCTAssertNotEqual(summary.state, .buildingBaseline)
    }

    func testStressShowsBuildingBaselineWhenBaselineIsTooShort() {
        let summary = StressEngine().score(
            today: MockHealthData.stressTodaySignals,
            baselineDays: Array(MockHealthData.stressBaselineSignals.prefix(3))
        )

        XCTAssertNil(summary.score)
        XCTAssertEqual(summary.state, .buildingBaseline)
        XCTAssertEqual(summary.baselineWindowDays, 3)
    }

    func testStressBaselineRequiresHRorHRVCalibrationSignals() {
        let day = MockHealthData.calendar.date(from: DateComponents(year: 2026, month: 5, day: 7))!
        let baseline = (1...21).map { offset in
            StressDailySignals(
                date: MockHealthData.calendar.date(byAdding: .day, value: -offset, to: day)!,
                sleepRespiratoryRate: 15,
                sleepDurationHours: 7.5,
                currentMotionContext: .unknown,
                sourceBadges: [.sample]
            )
        }
        var today = MockHealthData.stressTodaySignals
        today.date = day

        let summary = StressEngine().score(today: today, baselineDays: baseline)

        XCTAssertNil(summary.score)
        XCTAssertEqual(summary.state, .buildingBaseline)
    }

    func testStressReturnsNoDataWhenCurrentSignalsAreMissing() {
        let today = StressDailySignals(date: MockHealthData.stressTodaySignals.date)

        let summary = StressEngine().score(today: today, baselineDays: MockHealthData.stressBaselineSignals)

        XCTAssertNil(summary.score)
        XCTAssertEqual(summary.state, .noData)
        XCTAssertEqual(summary.confidence, .missing)
    }

    func testConfidenceDowngradesForMotionArtifactAndPoorSignalQuality() {
        var today = MockHealthData.stressTodaySignals
        today.currentMotionContext = .highArtifact
        today.signalQuality = 0.20

        let summary = StressEngine().score(today: today, baselineDays: MockHealthData.stressBaselineSignals)

        XCTAssertNotNil(summary.score)
        XCTAssertEqual(summary.confidence, .low)
        XCTAssertEqual(summary.state, .lowConfidence)
        XCTAssertTrue(summary.driverInsights.contains { $0.contains("Low confidence") })
    }

    private func heartSample(day: Date, hour: Int, minute: Int, bpm: Double, calendar: Calendar) -> HeartRateSample {
        let end = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        return HeartRateSample(
            start: end.addingTimeInterval(-60),
            end: end,
            bpm: bpm,
            provenance: .sample
        )
    }

    private func stressBaseline(day: Date, hrv: Double, restingHeartRate: Double, walkingHeartRate: Double) -> [StressDailySignals] {
        (1...21).map { offset in
            let date = MockHealthData.calendar.date(byAdding: .day, value: -offset, to: day)!
            return StressDailySignals(
                date: date,
                heartRateVariabilitySDNN: hrv + Double(offset % 5 - 2),
                restingHeartRate: restingHeartRate + Double(offset % 3 - 1),
                walkingHeartRateAverage: walkingHeartRate + Double(offset % 5 - 2),
                sleepRespiratoryRate: 15,
                currentMotionContext: .unknown,
                sourceBadges: [.sample]
            )
        }
    }
}
