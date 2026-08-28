//
//  HomeSelectedDateWindowTests.swift
//  PulsarTests
//

import XCTest
@testable import Pulsar

final class HomeSelectedDateWindowTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1
        self.calendar = calendar
    }

    func testEndDateIsStartOfToday() {
        let now = date(year: 2026, month: 8, day: 18, hour: 15)
        XCTAssertEqual(
            HomeSelectedDateWindow.validEndDate(now: now, calendar: calendar),
            date(year: 2026, month: 8, day: 18)
        )
    }

    func testStartDateUsesFirstLaunchWhenNoRecordsExist() {
        let firstLaunch = date(year: 2026, month: 8, day: 1)
        let today = date(year: 2026, month: 8, day: 18)

        let start = HomeSelectedDateWindow.validStartDate(
            records: [],
            firstLaunchDate: firstLaunch,
            firstStrainSyncDate: nil,
            now: today,
            calendar: calendar
        )

        XCTAssertEqual(start, firstLaunch)
    }

    func testStartDatePrefersEarliestRecordOverLaunchDate() {
        let firstLaunch = date(year: 2026, month: 8, day: 1)
        let recordDate = date(year: 2026, month: 8, day: 10)
        let today = date(year: 2026, month: 8, day: 18)

        let start = HomeSelectedDateWindow.validStartDate(
            records: [record(on: recordDate)],
            firstLaunchDate: firstLaunch,
            firstStrainSyncDate: nil,
            now: today,
            calendar: calendar
        )

        XCTAssertEqual(start, recordDate)
    }

    func testCannotMoveIntoTheFuture() {
        let today = date(year: 2026, month: 8, day: 18)
        let start = date(year: 2026, month: 8, day: 1)

        XCTAssertFalse(
            HomeSelectedDateWindow.canMove(
                offset: 1,
                from: today,
                start: start,
                end: today,
                calendar: calendar
            )
        )
        XCTAssertTrue(
            HomeSelectedDateWindow.canMove(
                offset: -1,
                from: today,
                start: start,
                end: today,
                calendar: calendar
            )
        )
    }

    func testCannotMoveBeforeStartDate() {
        let start = date(year: 2026, month: 8, day: 10)
        let today = date(year: 2026, month: 8, day: 18)

        XCTAssertFalse(
            HomeSelectedDateWindow.canMove(
                offset: -1,
                from: start,
                start: start,
                end: today,
                calendar: calendar
            )
        )
        XCTAssertTrue(
            HomeSelectedDateWindow.canMove(
                offset: 1,
                from: start,
                start: start,
                end: today,
                calendar: calendar
            )
        )
    }

    func testShiftedDateMovesByWholeDays() {
        let selected = date(year: 2026, month: 8, day: 18, hour: 9)

        XCTAssertEqual(
            HomeSelectedDateWindow.shiftedDate(offset: -1, from: selected, calendar: calendar),
            date(year: 2026, month: 8, day: 17)
        )
        XCTAssertEqual(
            HomeSelectedDateWindow.shiftedDate(offset: 1, from: selected, calendar: calendar),
            date(year: 2026, month: 8, day: 19)
        )
    }

    private func record(on date: Date) -> DailyStrainRecord {
        DailyStrainRecord(
            date: date,
            calendar: calendar,
            strainScore: 62,
            workoutMinutes: 38,
            steps: 8_400,
            activeEnergyKilocalories: 520,
            confidence: .high,
            sourceName: "Apple Watch",
            syncedAt: date
        )
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
