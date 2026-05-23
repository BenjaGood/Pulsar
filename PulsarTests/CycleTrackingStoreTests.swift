//
//  CycleTrackingStoreTests.swift
//  PulsarTests
//

import XCTest
@testable import Pulsar

@MainActor
final class CycleTrackingStoreTests: XCTestCase {
    private var calendar: Calendar!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        self.calendar = calendar
        suiteName = "pulsar.tests.cycle.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        calendar = nil
        super.tearDown()
    }

    func testNoDataStartsInOnboardingState() {
        let store = CycleTrackingStore(defaults: defaults, calendar: calendar)

        XCTAssertFalse(store.hasCycleData)
        XCTAssertNil(store.summary.currentCycleDay)
        XCTAssertEqual(store.summary.predictionConfidence, .limited)
    }

    func testOnboardingPersistsAcrossStoreReload() {
        let store = CycleTrackingStore(defaults: defaults, calendar: calendar)
        store.completeOnboarding(
            lastPeriodStartDate: date(year: 2026, month: 5, day: 1),
            averagePeriodLength: 5,
            averageCycleLength: 29
        )

        let reloaded = CycleTrackingStore(defaults: defaults, calendar: calendar)

        XCTAssertTrue(reloaded.hasCycleData)
        XCTAssertEqual(reloaded.state.lastPeriodStartDate, date(year: 2026, month: 5, day: 1))
        XCTAssertEqual(reloaded.state.averageCycleLength, 29)
        XCTAssertEqual(reloaded.state.bleedingLogs.count, 5)
    }

    func testEditingLatestPeriodStartReplacesOldRangeAndPersists() {
        let store = CycleTrackingStore(defaults: defaults, calendar: calendar)
        store.completeOnboarding(
            lastPeriodStartDate: date(year: 2026, month: 5, day: 1),
            averagePeriodLength: 5,
            averageCycleLength: 28
        )

        store.saveCycleData(
            lastPeriodStartDate: date(year: 2026, month: 5, day: 8),
            averagePeriodLength: 4,
            averageCycleLength: 31,
            bleedingDates: Set(store.state.bleedingDates)
        )

        let reloaded = CycleTrackingStore(defaults: defaults, calendar: calendar)
        let expectedDates = Set((0..<4).map { dayOffset in
            CycleTrackingCalculator.addDays(dayOffset, to: date(year: 2026, month: 5, day: 8), calendar: calendar)
        })

        XCTAssertEqual(reloaded.state.lastPeriodStartDate, date(year: 2026, month: 5, day: 8))
        XCTAssertEqual(Set(reloaded.state.bleedingDates), expectedDates)
        XCTAssertEqual(reloaded.state.averageCycleLength, 31)
        XCTAssertEqual(reloaded.state.averagePeriodLength, 4)
    }

    func testEditedBleedingDurationPersistsAfterReload() {
        let store = CycleTrackingStore(defaults: defaults, calendar: calendar)
        store.completeOnboarding(
            lastPeriodStartDate: date(year: 2026, month: 5, day: 1),
            averagePeriodLength: 6,
            averageCycleLength: 28
        )

        store.saveCycleData(
            lastPeriodStartDate: date(year: 2026, month: 5, day: 1),
            averagePeriodLength: 3,
            averageCycleLength: 28,
            bleedingDates: Set(store.state.bleedingDates)
        )

        let reloaded = CycleTrackingStore(defaults: defaults, calendar: calendar)

        XCTAssertEqual(reloaded.state.averagePeriodLength, 3)
        XCTAssertEqual(reloaded.summary.periodGroups.last?.dayCount, 3)
    }

    func testDailyBleedingLogUpdatesCurrentPhase() {
        let today = date(year: 2026, month: 5, day: 19)
        let store = CycleTrackingStore(
            defaults: defaults,
            calendar: calendar,
            initialState: CycleTrackingState.empty
        )

        store.saveDailyLog(
            date: today,
            bleedingIntensity: .moderate,
            symptoms: [],
            symptomSeverity: 1,
            note: ""
        )

        let prediction = CycleTrackingCalculator.prediction(for: store.state, today: today, calendar: calendar)

        XCTAssertTrue(store.hasCycleData)
        XCTAssertEqual(prediction.cycleDay, 1)
        XCTAssertEqual(prediction.phase, .menstrual)
    }

    func testSymptomsPersistForLoggedDay() {
        let store = CycleTrackingStore(defaults: defaults, calendar: calendar)
        store.completeOnboarding(
            lastPeriodStartDate: date(year: 2026, month: 5, day: 1),
            averagePeriodLength: 5,
            averageCycleLength: 28
        )

        store.saveDailyLog(
            date: date(year: 2026, month: 5, day: 3),
            bleedingIntensity: .light,
            symptoms: [.cramps, .fatigue],
            symptomSeverity: 3,
            note: "Poor sleep"
        )

        let reloaded = CycleTrackingStore(defaults: defaults, calendar: calendar)

        XCTAssertEqual(Set(reloaded.symptoms(on: date(year: 2026, month: 5, day: 3)).map(\.kind)), [.cramps, .fatigue])
        XCTAssertEqual(reloaded.note(on: date(year: 2026, month: 5, day: 3)), "Poor sleep")
    }

    func testLimitedHistoryProducesLimitedConfidence() {
        let state = CycleTrackingState(
            bleedingDates: period(start: date(year: 2026, month: 5, day: 1), days: 5),
            lastPeriodStartDate: date(year: 2026, month: 5, day: 1),
            averageCycleLength: 28,
            averagePeriodLength: 5,
            onboardingCompleted: true
        )

        let summary = CycleTrackingCalculator.summary(
            for: state,
            today: date(year: 2026, month: 5, day: 10),
            calendar: calendar
        )

        XCTAssertEqual(summary.predictionConfidence, .limited)
        XCTAssertTrue(summary.usesFallbackCycleLength)
    }

    func testMultipleCyclesUseHistoryMedianInsteadOfBaselineOnly() {
        let starts = [
            date(year: 2026, month: 1, day: 1),
            date(year: 2026, month: 1, day: 29),
            date(year: 2026, month: 2, day: 28),
            date(year: 2026, month: 3, day: 27)
        ]
        let bleedingDates = starts.flatMap { period(start: $0, days: 4) }
        let state = CycleTrackingState(
            bleedingDates: bleedingDates,
            lastPeriodStartDate: starts.last,
            averageCycleLength: 40,
            averagePeriodLength: 6,
            onboardingCompleted: true
        )

        let summary = CycleTrackingCalculator.summary(
            for: state,
            today: date(year: 2026, month: 4, day: 2),
            calendar: calendar
        )

        XCTAssertEqual(summary.cycleLengthSamples, [28, 30, 27])
        XCTAssertEqual(summary.averageCycleLength, 28)
        XCTAssertFalse(summary.usesFallbackCycleLength)
    }

    private func period(start: Date, days: Int) -> [Date] {
        (0..<days).map {
            CycleTrackingCalculator.addDays($0, to: start, calendar: calendar)
        }
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
