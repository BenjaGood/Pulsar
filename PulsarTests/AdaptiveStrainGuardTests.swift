//
//  AdaptiveStrainGuardTests.swift
//  PulsarTests
//

import XCTest
@testable import Pulsar

final class AdaptiveStrainGuardTests: XCTestCase {
    func testHighRecoveryDebtLowersTargetDespiteAcceptableRecovery() throws {
        let input = makeInput(
            sleepScore: 52,
            recoveryScore: 74,
            stressScore: 82,
            currentStrain: 18,
            recentStrainScores: [74, 77, 81, 76, 79, 82, 78]
        )

        let plan = try XCTUnwrap(AdaptiveStrainGuard().makePlan(input: input))

        XCTAssertEqual(plan.recoveryPriority, .protective)
        XCTAssertLessThan(plan.recommendedRange.upperBound, 50)
        XCTAssertGreaterThanOrEqual(plan.recoveryDebt.score, 70)
        XCTAssertTrue(plan.signals.contains { $0.id == "strainStack" })
    }

    func testPrimedRecoveryAllowsPerformanceRangeWhenDebtIsLow() throws {
        let input = makeInput(
            sleepScore: 92,
            recoveryScore: 91,
            stressScore: 24,
            currentStrain: 5,
            recentStrainScores: [28, 34, 42, 31, 38, 35, 30],
            hrvReadiness: 0.74,
            rhrReadiness: 0.72
        )

        let plan = try XCTUnwrap(AdaptiveStrainGuard().makePlan(input: input))

        XCTAssertEqual(plan.recoveryPriority, .primed)
        XCTAssertGreaterThanOrEqual(plan.recommendedRange.upperBound, 76)
        XCTAssertEqual(plan.optimalTrainingZone, .performance)
    }

    func testRealtimeWorkoutCoachingProtectsLowReadinessWorkout() throws {
        let plan = try XCTUnwrap(AdaptiveStrainGuard().makePlan(input: makeInput(
            sleepScore: 48,
            recoveryScore: 38,
            stressScore: 84,
            currentStrain: 22,
            recentStrainScores: [72, 78, 76, 80, 74, 79, 82]
        )))
        let start = date("2026-05-04 07:00")
        let samples = [
            AdaptiveHeartRateSample(timestamp: start, bpm: 78),
            AdaptiveHeartRateSample(timestamp: start.addingTimeInterval(180), bpm: 122),
            AdaptiveHeartRateSample(timestamp: start.addingTimeInterval(420), bpm: 166)
        ]

        let coaching = RealTimeWorkoutAdaptationEngine().evaluate(
            RealTimeWorkoutAdaptationInput(
                plan: plan,
                workoutKind: .running,
                elapsedTime: 420,
                currentHeartRate: 166,
                averageHeartRate: 142,
                maxObservedHeartRate: 166,
                recentHeartRates: samples,
                sampledAt: start.addingTimeInterval(420)
            )
        )

        XCTAssertNotNil(coaching)
        XCTAssertEqual(coaching?.severity, .protective)
    }

    private func makeInput(
        sleepScore: Int,
        recoveryScore: Int,
        stressScore: Int,
        currentStrain: Int,
        recentStrainScores: [Int],
        hrvReadiness: Double = 0.36,
        rhrReadiness: Double = 0.38
    ) -> AdaptiveStrainGuardInput {
        var sleep = SleepSummary.missing
        sleep.score = sleepScore
        sleep.totalSleepMinutes = Double(sleepScore >= 80 ? 500 : 320)
        sleep.sleepPerformance = Double(sleepScore) / 100
        sleep.lastUpdated = date("2026-05-04 06:30")

        var recovery = RecoverySummary.missing
        recovery.score = recoveryScore
        recovery.confidence = .high
        recovery.hrvSDNN = hrvReadiness >= 0.6 ? 66 : 44
        recovery.hrvBaseline = 58
        recovery.restingHeartRate = rhrReadiness >= 0.6 ? 51 : 61
        recovery.restingHeartRateBaseline = 53
        recovery.hrvReadiness = hrvReadiness
        recovery.restingHeartRateReadiness = rhrReadiness
        recovery.sleepContribution = Double(sleepScore) / 100
        recovery.lastUpdated = date("2026-05-04 06:45")

        var strain = StrainSummary.missing
        strain.score = currentStrain
        strain.sevenVsTwentyEightRatio = recentStrainScores.average / 50
        strain.restingHeartRate = recovery.restingHeartRate
        strain.lastUpdated = date("2026-05-04 12:00")

        var stress = StressSummary.missing
        stress.score = stressScore
        stress.confidence = .high
        stress.lastUpdated = date("2026-05-04 12:00")

        return AdaptiveStrainGuardInput(
            profile: MockHealthData.profile,
            sleep: sleep,
            recovery: recovery,
            strain: strain,
            stress: stress,
            recentRecords: recentRecords(scores: recentStrainScores, stressScore: stressScore, sleepScore: sleepScore),
            date: date("2026-05-04 00:00"),
            calendar: calendar,
            generatedAt: date("2026-05-04 12:00")
        )
    }

    private func recentRecords(scores: [Int], stressScore: Int, sleepScore: Int) -> [DailyStrainRecord] {
        scores.enumerated().map { index, score in
            DailyStrainRecord(
                date: calendar.date(byAdding: .day, value: -(scores.count - index), to: date("2026-05-04 00:00"))!,
                calendar: calendar,
                sleepScore: sleepScore,
                sleepMinutes: sleepScore >= 80 ? 490 : 320,
                recoveryScore: sleepScore >= 80 ? 86 : 48,
                stressScore: stressScore,
                strainScore: score,
                restingHeartRateStatus: stressScore >= 70 ? .higher : .normal,
                hrvStatus: sleepScore < 70 ? .lower : .normal,
                workoutMinutes: score >= 60 ? 55 : 18,
                steps: score >= 60 ? 9_500 : 5_000,
                activeEnergyKilocalories: score >= 60 ? 640 : 260,
                confidence: .high,
                sourceName: "Unit Test"
            )
        }
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }
}

private extension Array where Element == Int {
    var average: Double {
        guard !isEmpty else { return 0 }
        return Double(reduce(0, +)) / Double(count)
    }
}
