//
//  RecoveryDetailsViewModelTests.swift
//  PulsarTests
//

import XCTest
@testable import Pulsar

@MainActor
final class RecoveryDetailsViewModelTests: XCTestCase {
    func testRecoveryScoreClampsBetweenZeroAndOneHundred() {
        let summary = makeSummary(hrv: 220, restingHeartRate: 35, sleepPerformance: 1, strain: 0)

        XCTAssertGreaterThanOrEqual(summary.score, 0)
        XCTAssertLessThanOrEqual(summary.score, 100)
    }

    func testInsufficientDataProducesMissingScore() {
        let summary = RecoveryScoringEngine().score(today: emptyBiometrics, baselineDays: [])

        XCTAssertEqual(summary.score, 0)
        XCTAssertEqual(summary.confidence, .missing)
    }

    func testHRVAboveBaselineSupportsRecovery() {
        let high = makeSummary(hrv: 68, restingHeartRate: 53, sleepPerformance: 0.8, strain: 0.4)
        let low = makeSummary(hrv: 44, restingHeartRate: 53, sleepPerformance: 0.8, strain: 0.4)

        XCTAssertGreaterThan(high.hrvReadiness, low.hrvReadiness)
        XCTAssertGreaterThan(high.score, low.score)
    }

    func testRestingHeartRateAboveBaselineReducesRecovery() {
        let normal = makeSummary(hrv: 58, restingHeartRate: 52, sleepPerformance: 0.8, strain: 0.4)
        let elevated = makeSummary(hrv: 58, restingHeartRate: 62, sleepPerformance: 0.8, strain: 0.4)

        XCTAssertGreaterThan(normal.restingHeartRateReadiness, elevated.restingHeartRateReadiness)
        XCTAssertGreaterThan(normal.score, elevated.score)
    }

    func testGoodSleepSupportsRecoveryAndHighStrainReducesRecovery() {
        let rested = makeSummary(hrv: 58, restingHeartRate: 52, sleepPerformance: 0.9, strain: 0.2)
        let strained = makeSummary(hrv: 58, restingHeartRate: 52, sleepPerformance: 0.5, strain: 0.9)

        XCTAssertGreaterThan(rested.sleepContribution, strained.sleepContribution)
        XCTAssertGreaterThan(rested.score, strained.score)
    }

    func testNoDataStateWorks() {
        let viewModel = makeViewModel(summary: .missing)

        XCTAssertEqual(viewModel.state, .noData)
    }

    func testPermissionRequiredStateWorks() {
        let viewModel = makeViewModel(summary: .missing, canRequestHealthData: false)

        XCTAssertEqual(viewModel.state, .permissionRequired)
    }

    func testPartialDataStillLoads() {
        var summary = RecoverySummary.missing
        summary.hrvSDNN = 48
        summary.analyzedSampleCount = 1
        let viewModel = makeViewModel(summary: summary)

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.hrvText, "48 ms")
    }

    func testTrendPointsAreSortedByDate() {
        let summary = makeAnalyzedSummary()

        XCTAssertEqual(summary.trend, summary.trend.sorted { $0.date < $1.date })
    }

    func testRepeatedLoadsWithSameDataAreStable() async {
        let summary = makeAnalyzedSummary()
        let viewModel = makeViewModel(summary: .missing, providerSummary: summary)

        await viewModel.load()
        let first = viewModel.summary
        await viewModel.load()
        let second = viewModel.summary

        XCTAssertEqual(first.score, second.score)
        XCTAssertEqual(first.hrvSDNN, second.hrvSDNN)
        XCTAssertEqual(first.restingHeartRate, second.restingHeartRate)
        XCTAssertEqual(first.components, second.components)
        XCTAssertEqual(first.trend, second.trend)
    }

    func testInsightsAreDeterministicAndWellnessWorded() {
        let summary = makeSummary(hrv: 44, restingHeartRate: 62, sleepPerformance: 0.7, strain: 0.8)
        let viewModel = makeViewModel(summary: summary)

        XCTAssertFalse(viewModel.insights.isEmpty)
        XCTAssertFalse(viewModel.insights.contains { $0.text.localizedCaseInsensitiveContains("sick") })
        XCTAssertEqual(viewModel.insights, makeViewModel(summary: summary).insights)
    }

    private func makeViewModel(summary: RecoverySummary, providerSummary: RecoverySummary? = nil, canRequestHealthData: Bool = true) -> RecoveryDetailsViewModel {
        RecoveryDetailsViewModel(
            initialSummary: summary,
            profile: MockHealthData.profile,
            date: date("2026-05-04 00:00"),
            provider: StaticRecoveryProvider(summary: providerSummary ?? summary),
            calendar: calendar,
            canRequestHealthData: canRequestHealthData
        )
    }

    private func makeSummary(hrv: Double, restingHeartRate: Double, sleepPerformance: Double, strain: Double) -> RecoverySummary {
        var today = DailyBiometrics(
            date: date("2026-05-04 00:00"),
            hrvSDNNMilliseconds: hrv,
            restingHeartRateBPM: restingHeartRate,
            respiratoryRate: 14.2,
            sleepPerformance: sleepPerformance,
            priorDayStrain: strain,
            provenance: ["hrv": .sample, "rhr": .sample, "respiratory": .sample]
        )
        today.oxygenSaturation = 0.98
        return RecoveryScoringEngine().score(today: today, baselineDays: baseline)
    }

    private func makeAnalyzedSummary() -> RecoverySummary {
        let sleep = MockHealthData.sleepSummary
        let strain = MockHealthData.strainSummary
        return RecoveryAnalyzer().analyze(
            RecoveryAnalysisInput(
                date: date("2026-05-04 00:00"),
                biometrics: MockHealthData.todayBiometrics,
                baselineDays: baseline,
                trendDays: Array(baseline.prefix(6).reversed()) + [MockHealthData.todayBiometrics],
                sleep: sleep,
                strain: strain,
                queryInterval: DateInterval(start: date("2026-05-04 00:00"), end: date("2026-05-04 12:00")),
                refreshedAt: date("2026-05-04 12:00")
            )
        )
    }

    private var emptyBiometrics: DailyBiometrics {
        DailyBiometrics(date: date("2026-05-04 00:00"), hrvSDNNMilliseconds: nil, restingHeartRateBPM: nil, respiratoryRate: nil, sleepPerformance: nil, priorDayStrain: nil, provenance: [:])
    }

    private var baseline: [DailyBiometrics] {
        (1...28).map { offset in
            DailyBiometrics(
                date: calendar.date(byAdding: .day, value: -offset, to: date("2026-05-04 00:00"))!,
                hrvSDNNMilliseconds: 58 + Double(offset % 3 - 1),
                restingHeartRateBPM: 53 + Double(offset % 2),
                respiratoryRate: 14.2,
                sleepPerformance: 0.78,
                priorDayStrain: 0.4,
                provenance: ["hrv": .sample, "rhr": .sample]
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

private struct StaticRecoveryProvider: RecoverySummaryProviding {
    var summary: RecoverySummary

    func recoverySummary(profile: UserProfile, date: Date, calendar: Calendar, refreshedAt: Date) async throws -> RecoverySummary {
        var copy = summary
        copy.lastUpdated = refreshedAt
        return copy
    }
}
