//
//  StrainCalendarViewModelTests.swift
//  PulsarTests
//

import XCTest
@testable import Pulsar

@MainActor
final class StrainCalendarViewModelTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1
        self.calendar = calendar
    }

    func testDatesOutsideValidWindowAreDisabledAndTodayIsSelectable() {
        let start = date(year: 2026, month: 5, day: 10)
        let today = date(year: 2026, month: 5, day: 20)
        let viewModel = StrainCalendarViewModel(selectedDate: today, records: [], firstLaunchDate: start, today: today, calendar: calendar)

        XCTAssertFalse(viewModel.isDateSelectable(date(year: 2026, month: 5, day: 9)))
        XCTAssertFalse(viewModel.isDateSelectable(date(year: 2026, month: 5, day: 21)))
        XCTAssertTrue(viewModel.isDateSelectable(today))
    }

    func testPreviousMonthIsDisabledAtValidStartMonth() {
        let start = date(year: 2026, month: 5, day: 10)
        let today = date(year: 2026, month: 5, day: 20)
        let viewModel = StrainCalendarViewModel(selectedDate: today, records: [], firstLaunchDate: start, today: today, calendar: calendar)

        XCTAssertFalse(viewModel.canGoToPreviousMonth)
    }

    func testNextMonthIsDisabledAtCurrentMonth() {
        let start = date(year: 2026, month: 4, day: 10)
        let today = date(year: 2026, month: 5, day: 20)
        let viewModel = StrainCalendarViewModel(selectedDate: today, records: [], firstLaunchDate: start, today: today, calendar: calendar)

        XCTAssertFalse(viewModel.canGoToNextMonth)
    }

    func testRuntimePlaceholderRecordsAreBoundedToLaunchAndToday() {
        let start = date(year: 2026, month: 5, day: 10)
        let today = date(year: 2026, month: 5, day: 15)

        let records = MockStrainCalendarData.runtimePlaceholderRecords(firstLaunchDate: start, today: today, calendar: calendar)

        XCTAssertFalse(records.contains { calendar.startOfDay(for: $0.date) < start })
        XCTAssertFalse(records.contains { calendar.startOfDay(for: $0.date) > today })
    }

    func testSelectedDateIsClampedIntoValidRange() {
        let start = date(year: 2026, month: 5, day: 10)
        let today = date(year: 2026, month: 5, day: 20)

        let futureSelection = StrainCalendarViewModel(selectedDate: date(year: 2026, month: 5, day: 30), records: [], firstLaunchDate: start, today: today, calendar: calendar)
        let earlySelection = StrainCalendarViewModel(selectedDate: date(year: 2026, month: 5, day: 1), records: [], firstLaunchDate: start, today: today, calendar: calendar)

        XCTAssertEqual(futureSelection.selectedDate, today)
        XCTAssertEqual(earlySelection.selectedDate, start)
    }

    func testEarliestRecordDefinesStartWhenRecordsExist() {
        let firstLaunch = date(year: 2026, month: 5, day: 1)
        let recordDate = date(year: 2026, month: 5, day: 10)
        let today = date(year: 2026, month: 5, day: 20)
        let viewModel = StrainCalendarViewModel(
            selectedDate: today,
            records: [record(on: recordDate)],
            firstLaunchDate: firstLaunch,
            today: today,
            calendar: calendar
        )

        XCTAssertEqual(viewModel.validStartDate, recordDate)
        XCTAssertFalse(viewModel.isDateSelectable(date(year: 2026, month: 5, day: 5)))
    }

    private func record(on date: Date) -> DailyStrainRecord {
        DailyStrainRecord(
            date: date,
            strainScore: 62,
            workoutMinutes: 38,
            steps: 8_400,
            activeEnergyKilocalories: 520,
            confidence: .high,
            sourceName: "Apple Watch",
            syncedAt: date
        )
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
