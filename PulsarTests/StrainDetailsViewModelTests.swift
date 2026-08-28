//
//  StrainDetailsViewModelTests.swift
//  PulsarTests
//

import XCTest
@testable import Pulsar

@MainActor
final class StrainDetailsViewModelTests: XCTestCase {
    func testWorkoutDurationTotalsAreCorrect() {
        let summary = makeSummary()

        XCTAssertEqual(summary.workoutMinutes, 60, accuracy: 0.001)
        XCTAssertEqual(summary.workouts.first?.durationMinutes ?? 0, 60, accuracy: 0.001)
    }

    func testExerciseMinutesFormattingIsCorrect() {
        let viewModel = makeViewModel(summary: makeSummary())

        XCTAssertEqual(viewModel.exerciseMinutesText, "45m")
    }

    func testStepGoalPercentageIsCorrect() {
        let viewModel = makeViewModel(summary: makeSummary())

        XCTAssertEqual(viewModel.stepProgress, 0.72, accuracy: 0.001)
        XCTAssertEqual(viewModel.stepProgressText, "72%")
    }

    func testActiveCaloriesFormattingIsCorrect() {
        let viewModel = makeViewModel(summary: makeSummary())

        XCTAssertEqual(viewModel.activeEnergyText, "520 kcal")
    }

    func testPeakHeartRateChoosesMaximumObservedValue() {
        let summary = makeSummary()

        XCTAssertEqual(summary.peakHeartRate ?? 0, 168, accuracy: 0.001)
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
        var summary = StrainSummary.missing
        summary.steps = 2_200
        summary.stepGoal = 10_000
        let viewModel = makeViewModel(summary: summary)

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.stepsText, "2,200")
    }

    func testTimelineIntervalsAreSortedByStartDate() {
        let intervals = makeSummary().timeline

        XCTAssertFalse(intervals.isEmpty)
        XCTAssertEqual(intervals, intervals.sorted { $0.startDate < $1.startDate })
    }

    func testGraphIntensityMappingUsesZones() {
        let analyzer = StrainAnalyzer()

        XCTAssertEqual(analyzer.intensity(for: 80, maxHeartRate: 190), .rest)
        XCTAssertEqual(analyzer.intensity(for: 112, maxHeartRate: 190), .light)
        XCTAssertEqual(analyzer.intensity(for: 135, maxHeartRate: 190), .moderate)
        XCTAssertEqual(analyzer.intensity(for: 158, maxHeartRate: 190), .hard)
        XCTAssertEqual(analyzer.intensity(for: 176, maxHeartRate: 190), .peak)
    }

    func testRepeatedLoadsWithSameDataAreStable() async {
        let summary = makeSummary()
        let viewModel = makeViewModel(summary: .missing, providerSummary: summary)

        await viewModel.load()
        let first = viewModel.summary
        await viewModel.load()
        let second = viewModel.summary

        XCTAssertEqual(first.score, second.score)
        XCTAssertEqual(first.workoutMinutes, second.workoutMinutes)
        XCTAssertEqual(first.steps, second.steps)
        XCTAssertEqual(first.peakHeartRate, second.peakHeartRate)
        XCTAssertEqual(first.timeline, second.timeline)
    }

    func testHealthKitUUIDDeduplicatesOverlappingDayAndWorkoutHeartSamples() {
        let start = date("2026-05-04 07:00")
        let sampleID = UUID()
        let sample = HeartRateSample(
            id: sampleID,
            start: start,
            end: start.addingTimeInterval(30),
            bpm: 132,
            provenance: .sample
        )
        let workout = WorkoutLoadInput(
            id: UUID(),
            type: "Run",
            start: start,
            end: start.addingTimeInterval(60),
            heartRateSamples: [sample],
            activeEnergyKilocalories: nil,
            distanceMeters: nil,
            provenance: .sample
        )
        let activity = DailyActivityInput(
            date: start,
            steps: 0,
            activeEnergyKilocalories: 0,
            basalEnergyKilocalories: 0,
            distanceMeters: 0,
            exerciseMinutes: 0,
            provenance: []
        )
        let input = DailyStrainInput(
            date: start,
            maxHeartRate: 190,
            workouts: [workout],
            activity: activity,
            recentRawLoads: [],
            sevenDayRawLoad: 0,
            twentyEightDayRawLoad: 0
        )

        let summary = StrainAnalyzer().analyze(
            StrainAnalysisInput(
                strainInput: input,
                biometrics: DailyBiometrics(
                    date: start,
                    hrvSDNNMilliseconds: nil,
                    restingHeartRateBPM: 52,
                    respiratoryRate: nil,
                    sleepPerformance: nil,
                    priorDayStrain: nil,
                    provenance: [:]
                ),
                dayHeartRateSamples: [sample],
                queryInterval: DateInterval(start: start, duration: 3_600),
                refreshedAt: start
            )
        )

        XCTAssertEqual(summary.heartRatePoints.count, 1)
        XCTAssertEqual(summary.analyzedSampleCount, 2)
    }

    func testHeartLoadChartUsesSortedHeartRatePointsAndWorkoutBands() {
        let viewModel = makeViewModel(summary: makeSummary())
        let chart = viewModel.heartLoadChart

        XCTAssertFalse(chart.heartRatePoints.isEmpty)
        XCTAssertFalse(chart.workoutBands.isEmpty)
        XCTAssertEqual(chart.heartRatePoints, chart.heartRatePoints.sorted { $0.date < $1.date })
        XCTAssertEqual(chart.workoutBands, chart.workoutBands.sorted { $0.startDate < $1.startDate })
        XCTAssertEqual(chart.callouts.first?.title, "Peak HR")
    }

    func testHeartRatePointsAreDownsampledDeterministically() {
        let summary = makeHighSampleSummary()

        XCTAssertLessThanOrEqual(summary.heartRatePoints.count, 240)
        XCTAssertEqual(summary.heartRatePoints, summary.heartRatePoints.sorted { $0.date < $1.date })
        XCTAssertEqual(summary.heartRatePoints.first?.bpm ?? 0, 90, accuracy: 0.001)
        XCTAssertEqual(summary.heartRatePoints.last?.bpm ?? 0, 129, accuracy: 0.001)
    }

    func testHeartLoadChartSupportsWorkoutOnlyPartialData() {
        var summary = StrainSummary.missing
        let start = date("2026-05-04 07:00")
        let end = date("2026-05-04 07:45")
        summary.queryStart = date("2026-05-04 00:00")
        summary.queryEnd = date("2026-05-04 12:00")
        summary.workoutBands = [
            WorkoutTimelineBand(
                workoutType: "Strength",
                startDate: start,
                endDate: end,
                duration: end.timeIntervalSince(start),
                averageHeartRate: nil,
                peakHeartRate: nil
            )
        ]
        let chart = makeViewModel(summary: summary).heartLoadChart

        XCTAssertFalse(chart.hasHeartRate)
        XCTAssertTrue(chart.hasWorkouts)
        XCTAssertFalse(chart.hasMovement)
    }

    private func makeViewModel(summary: StrainSummary, providerSummary: StrainSummary? = nil, canRequestHealthData: Bool = true) -> StrainDetailsViewModel {
        StrainDetailsViewModel(
            initialSummary: summary,
            profile: profile,
            date: date("2026-05-04 00:00"),
            provider: StaticStrainProvider(summary: providerSummary ?? summary),
            calendar: calendar,
            canRequestHealthData: canRequestHealthData
        )
    }

    private func makeSummary() -> StrainSummary {
        let workoutStart = date("2026-05-04 07:00")
        let workoutEnd = date("2026-05-04 08:00")
        let heartRates = [118, 132, 146, 168].enumerated().map { index, bpm in
            HeartRateSample(
                start: workoutStart.addingTimeInterval(Double(index) * 15 * 60),
                end: workoutStart.addingTimeInterval(Double(index + 1) * 15 * 60),
                bpm: Double(bpm),
                provenance: .sample
            )
        }
        let workout = WorkoutLoadInput(
            type: "Run",
            start: workoutStart,
            end: workoutEnd,
            heartRateSamples: heartRates,
            activeEnergyKilocalories: 430,
            distanceMeters: 8_000,
            provenance: .sample
        )
        let activity = DailyActivityInput(
            date: date("2026-05-04 00:00"),
            steps: 7_200,
            activeEnergyKilocalories: 520,
            basalEnergyKilocalories: 1_400,
            distanceMeters: 8_600,
            exerciseMinutes: 45,
            provenance: [.sample]
        )
        let input = DailyStrainInput(
            date: date("2026-05-04 00:00"),
            maxHeartRate: 190,
            workouts: [workout],
            activity: activity,
            recentRawLoads: Array(repeating: 90, count: 28),
            sevenDayRawLoad: 630,
            twentyEightDayRawLoad: 2_520
        )
        let biometrics = DailyBiometrics(
            date: date("2026-05-04 00:00"),
            hrvSDNNMilliseconds: 62,
            restingHeartRateBPM: 52,
            respiratoryRate: nil,
            sleepPerformance: nil,
            priorDayStrain: nil,
            provenance: [:]
        )
        return StrainAnalyzer().analyze(
            StrainAnalysisInput(
                strainInput: input,
                biometrics: biometrics,
                dayHeartRateSamples: heartRates,
                queryInterval: DateInterval(start: date("2026-05-04 00:00"), end: date("2026-05-04 12:00")),
                refreshedAt: date("2026-05-04 12:00")
            )
        )
    }

    private func makeHighSampleSummary() -> StrainSummary {
        let start = date("2026-05-04 00:00")
        let heartRates = (0..<600).map { index in
            let sampleStart = start.addingTimeInterval(Double(index) * 60)
            return HeartRateSample(
                start: sampleStart,
                end: sampleStart.addingTimeInterval(30),
                bpm: Double(90 + index % 80),
                provenance: .sample
            )
        }
        let activity = DailyActivityInput(
            date: start,
            steps: 3_000,
            activeEnergyKilocalories: 180,
            basalEnergyKilocalories: 1_300,
            distanceMeters: 2_400,
            exerciseMinutes: 18,
            provenance: [.sample]
        )
        let input = DailyStrainInput(
            date: start,
            maxHeartRate: nil,
            workouts: [],
            activity: activity,
            recentRawLoads: Array(repeating: 40, count: 28),
            sevenDayRawLoad: 280,
            twentyEightDayRawLoad: 1_120
        )
        let biometrics = DailyBiometrics(
            date: start,
            hrvSDNNMilliseconds: nil,
            restingHeartRateBPM: 54,
            respiratoryRate: nil,
            sleepPerformance: nil,
            priorDayStrain: nil,
            provenance: [:]
        )
        return StrainAnalyzer().analyze(
            StrainAnalysisInput(
                strainInput: input,
                biometrics: biometrics,
                dayHeartRateSamples: heartRates,
                queryInterval: DateInterval(start: start, end: date("2026-05-04 12:00")),
                refreshedAt: date("2026-05-04 12:00")
            )
        )
    }

    private var profile: UserProfile {
        var profile = MockHealthData.profile
        profile.manualMaxHeartRate = 190
        return profile
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

private struct StaticStrainProvider: StrainSummaryProviding {
    var summary: StrainSummary

    func strainSummary(profile: UserProfile, date: Date, calendar: Calendar, refreshedAt: Date) async throws -> StrainSummary {
        var copy = summary
        copy.lastUpdated = refreshedAt
        return copy
    }
}
