//
//  FitnessWeekCalculatorTests.swift
//  PulsarTests
//

import XCTest
@testable import Pulsar

final class FitnessWeekCalculatorTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        self.calendar = calendar
    }

    func testWeekOneAlwaysStartsOnJanuaryFirst() {
        XCTAssertEqual(FitnessWeekCalculator.getCustomWeekNumber(for: date(year: 2026, month: 1, day: 1), calendar: calendar), 1)
        XCTAssertEqual(FitnessWeekCalculator.getCustomWeekNumber(for: date(year: 2026, month: 1, day: 7), calendar: calendar), 1)
        XCTAssertEqual(FitnessWeekCalculator.getCustomWeekNumber(for: date(year: 2026, month: 1, day: 8), calendar: calendar), 2)
    }

    func testWeekPeriodUsesFixedSevenDayBlocks() {
        let period = FitnessWeekCalculator.getWeekPeriod(
            for: date(year: 2026, month: 5, day: 8),
            calendar: calendar,
            now: date(year: 2026, month: 5, day: 8)
        )

        XCTAssertEqual(period.weekNumber, 19)
        XCTAssertEqual(period.startDate, date(year: 2026, month: 5, day: 7))
        XCTAssertEqual(period.endDate, date(year: 2026, month: 5, day: 13))
        XCTAssertTrue(period.isCurrentWeek)
    }

    func testFinalWeekIsCappedAtDecemberThirtyFirst() {
        let period = FitnessWeekCalculator.getWeekPeriod(
            for: date(year: 2026, month: 12, day: 31),
            calendar: calendar,
            now: date(year: 2026, month: 12, day: 31)
        )

        XCTAssertEqual(period.endDate, date(year: 2026, month: 12, day: 31))
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
