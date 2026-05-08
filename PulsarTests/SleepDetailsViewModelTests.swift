//
//  SleepDetailsViewModelTests.swift
//  PulsarTests
//

import XCTest
@testable import Pulsar

@MainActor
final class SleepDetailsViewModelTests: XCTestCase {
    func testStagePercentagesAddUpForSleepStages() {
        let viewModel = makeViewModel(summary: makeSummary())

        let sleepStagePercent = viewModel.stageBreakdownRows
            .filter { $0.stage.isSleep }
            .reduce(0) { $0 + $1.percentOfSleep }

        XCTAssertEqual(sleepStagePercent, 1, accuracy: 0.001)
    }

    func testEfficiencyUsesActualSleepDividedByTimeInBed() {
        let viewModel = makeViewModel(summary: makeSummary())

        XCTAssertEqual(viewModel.summary.sleepEfficiency, 450.0 / 500.0, accuracy: 0.001)
        XCTAssertEqual(viewModel.efficiencyText, "90%")
    }

    func testInBedAndAwakeAreNotCountedAsActualSleep() {
        let viewModel = makeViewModel(summary: makeSummary())

        XCTAssertEqual(viewModel.summary.totalSleepMinutes, 450, accuracy: 0.001)
        XCTAssertEqual(viewModel.summary.timeInBedMinutes, 500, accuracy: 0.001)
        XCTAssertEqual(viewModel.summary.awakeMinutes, 20, accuracy: 0.001)
    }

    func testIntervalsRemainInTimelineOrder() {
        let intervals = makeSummary().intervals

        XCTAssertEqual(intervals.map(\.stage), [.inBed, .core, .awake, .deep, .rem, .core])
        XCTAssertEqual(intervals, intervals.sorted { $0.startDate < $1.startDate })
    }

    func testEmptyDataProducesNoDataState() {
        let viewModel = makeViewModel(summary: .missing)

        XCTAssertEqual(viewModel.state, .noData)
    }

    func testPermissionMissingProducesPermissionRequiredState() {
        let viewModel = makeViewModel(summary: .permissionRequired, canRequestHealthData: false)

        XCTAssertEqual(viewModel.state, .permissionRequired)
    }

    func testRepeatedLoadsWithSameSamplesKeepComputedValuesStable() async {
        let summary = makeSummary()
        let viewModel = makeViewModel(summary: .missing, providerSummary: summary)

        await viewModel.load()
        let first = viewModel.summary
        await viewModel.load()
        let second = viewModel.summary

        XCTAssertEqual(first.totalSleepMinutes, second.totalSleepMinutes)
        XCTAssertEqual(first.timeInBedMinutes, second.timeInBedMinutes)
        XCTAssertEqual(first.awakeMinutes, second.awakeMinutes)
        XCTAssertEqual(first.intervals, second.intervals)
    }

    private func makeViewModel(summary: SleepSummary, providerSummary: SleepSummary? = nil, canRequestHealthData: Bool = true) -> SleepDetailsViewModel {
        SleepDetailsViewModel(
            initialSummary: summary,
            profile: profile,
            wakeUpDate: date("2026-05-04 00:00"),
            provider: StaticSleepProvider(summary: providerSummary ?? summary),
            calendar: calendar,
            canRequestHealthData: canRequestHealthData
        )
    }

    private func makeSummary() -> SleepSummary {
        let intervals = [
            interval(.inBed, "2026-05-03 22:00", "2026-05-04 06:20"),
            interval(.core, "2026-05-03 22:20", "2026-05-04 01:20"),
            interval(.awake, "2026-05-04 01:20", "2026-05-04 01:40"),
            interval(.deep, "2026-05-04 01:40", "2026-05-04 02:40"),
            interval(.rem, "2026-05-04 02:40", "2026-05-04 04:10"),
            interval(.core, "2026-05-04 04:10", "2026-05-04 06:10")
        ]
        return SleepSummary(
            wakeUpDate: date("2026-05-04 00:00"),
            score: 82,
            confidence: .high,
            confidenceExplanation: "Test summary.",
            timeInBedMinutes: 500,
            totalSleepMinutes: 450,
            sleepEfficiency: 450.0 / 500.0,
            awakeMinutes: 20,
            wasoMinutes: 20,
            sleepConsistency: 0.8,
            sleepPerformance: 0.82,
            durationAdequacy: 450.0 / 480.0,
            regularity: 0.8,
            continuity: 0.78,
            stageBreakdown: [
                StageMetric(stage: .core, minutes: 300, percentOfSleep: 300.0 / 450.0),
                StageMetric(stage: .deep, minutes: 60, percentOfSleep: 60.0 / 450.0),
                StageMetric(stage: .rem, minutes: 90, percentOfSleep: 90.0 / 450.0),
                StageMetric(stage: .awake, minutes: 20, percentOfSleep: 20.0 / 470.0)
            ],
            intervals: intervals,
            sleepStart: date("2026-05-03 22:20"),
            wakeTime: date("2026-05-04 06:20"),
            awakenings: 1,
            analyzedSampleCount: 6,
            queryStart: date("2026-05-03 18:00"),
            queryEnd: date("2026-05-04 12:00"),
            lastUpdated: date("2026-05-04 08:00"),
            sourceBadges: [.sample],
            notes: []
        )
    }

    private var profile: UserProfile {
        MockHealthData.profile
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func interval(_ stage: SleepStage, _ start: String, _ end: String) -> SleepStageInterval {
        SleepStageInterval(stage: stage, startDate: date(start), endDate: date(end))
    }

    private func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }
}

private struct StaticSleepProvider: SleepSummaryProviding {
    var summary: SleepSummary

    func sleepSummary(profile: UserProfile, wakeUpDate: Date, calendar: Calendar, refreshedAt: Date) async throws -> SleepSummary {
        var copy = summary
        copy.lastUpdated = refreshedAt
        return copy
    }
}
