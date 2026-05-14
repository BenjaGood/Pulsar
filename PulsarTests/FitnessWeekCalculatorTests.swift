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
        calendar.firstWeekday = 1
        self.calendar = calendar
    }

    func testFitnessWeekRangeForcesMondayThroughSunday() {
        let sundayNight = date(year: 2026, month: 5, day: 17, hour: 23)
        let range = FitnessWeekCalculator.getFitnessWeekRange(for: sundayNight, calendar: calendar)

        XCTAssertEqual(range.startOfWeekMonday, date(year: 2026, month: 5, day: 11))
        XCTAssertEqual(range.endOfWeekSunday, date(year: 2026, month: 5, day: 17, hour: 23, minute: 59, second: 59))
        XCTAssertEqual(range.endExclusive, date(year: 2026, month: 5, day: 18))
        XCTAssertEqual(FitnessWeekCalculator.getCustomWeekNumber(for: sundayNight, calendar: calendar), 20)
    }

    func testCurrentWeekExcludesPreviousSundayAfterMondayStarts() {
        let now = date(year: 2026, month: 5, day: 18, hour: 0, minute: 1)
        let previousSunday = date(year: 2026, month: 5, day: 17, hour: 23)
        let mondayMorning = date(year: 2026, month: 5, day: 18, hour: 8)
        let nextMonday = date(year: 2026, month: 5, day: 25)

        XCTAssertFalse(FitnessWeekCalculator.isDateInCurrentFitnessWeek(previousSunday, now: now, calendar: calendar))
        XCTAssertTrue(FitnessWeekCalculator.isDateInCurrentFitnessWeek(mondayMorning, now: now, calendar: calendar))
        XCTAssertFalse(FitnessWeekCalculator.isDateInCurrentFitnessWeek(nextMonday, now: now, calendar: calendar))
    }

    func testWeekPeriodUsesExclusiveNextMondayFetchEnd() {
        let period = FitnessWeekCalculator.getWeekPeriod(
            for: date(year: 2026, month: 5, day: 8),
            calendar: calendar,
            now: date(year: 2026, month: 5, day: 8)
        )

        XCTAssertEqual(period.startDate, date(year: 2026, month: 5, day: 4))
        XCTAssertEqual(period.endDate, date(year: 2026, month: 5, day: 10, hour: 23, minute: 59, second: 59))
        XCTAssertEqual(FitnessWeekCalculator.fetchEnd(for: period, calendar: calendar), date(year: 2026, month: 5, day: 11))
        XCTAssertTrue(period.isCurrentWeek)
        XCTAssertTrue(FitnessWeekCalculator.contains(date(year: 2026, month: 5, day: 10, hour: 23, minute: 59, second: 59), in: period, calendar: calendar))
        XCTAssertFalse(FitnessWeekCalculator.contains(date(year: 2026, month: 5, day: 11), in: period, calendar: calendar))
    }

    func testWeekCanCrossYearBoundaryWithoutDroppingSunday() {
        let period = FitnessWeekCalculator.getWeekPeriod(
            for: date(year: 2026, month: 1, day: 1),
            calendar: calendar,
            now: date(year: 2026, month: 1, day: 1)
        )

        XCTAssertEqual(period.startDate, date(year: 2025, month: 12, day: 29))
        XCTAssertEqual(period.endDate, date(year: 2026, month: 1, day: 4, hour: 23, minute: 59, second: 59))
        XCTAssertTrue(FitnessWeekCalculator.contains(date(year: 2026, month: 1, day: 4, hour: 23), in: period, calendar: calendar))
        XCTAssertFalse(FitnessWeekCalculator.contains(date(year: 2026, month: 1, day: 5), in: period, calendar: calendar))
    }

    func testMatrixStartsCleanOnNewMondayUntilCurrentWeekWorkoutExists() {
        let previousSunday = date(year: 2026, month: 5, day: 17, hour: 23)
        let mondayMorning = date(year: 2026, month: 5, day: 18, hour: 8)
        let currentWeek = FitnessWeekCalculator.getWeekPeriod(for: mondayMorning, calendar: calendar, now: mondayMorning)
        let previousWeekActivity = strengthActivity(id: "sunday-gym", startDate: previousSunday)
        let currentWeekActivities = [previousWeekActivity].filter {
            FitnessWeekCalculator.contains($0.startDate, in: currentWeek, calendar: calendar)
        }

        let emptyMatrix = MuscleMatrixViewModel(
            week: currentWeek,
            activities: currentWeekActivities,
            calendar: FitnessWeekCalculator.fitnessCalendar(from: calendar),
            now: mondayMorning
        )

        XCTAssertEqual(emptyMatrix.weeklySummary.totalSessions, 0)
        XCTAssertTrue(emptyMatrix.cells.allSatisfy { !$0.isActive })

        let mondayActivity = strengthActivity(id: "monday-gym", startDate: mondayMorning)
        let updatedMatrix = MuscleMatrixViewModel(
            week: currentWeek,
            activities: [mondayActivity].filter { FitnessWeekCalculator.contains($0.startDate, in: currentWeek, calendar: calendar) },
            calendar: FitnessWeekCalculator.fitnessCalendar(from: calendar),
            now: mondayMorning
        )

        XCTAssertEqual(updatedMatrix.weeklySummary.totalSessions, 1)
        XCTAssertEqual(updatedMatrix.cell(for: .chest, day: .monday).sets, 3)
    }

    private func strengthActivity(id: String, startDate: Date) -> WeeklyActivity {
        WeeklyActivity(
            id: id,
            workoutUUID: nil,
            workoutType: "Gym",
            displayName: "Push Day",
            category: .gym,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(3_600),
            duration: 3_600,
            calories: nil,
            distanceMeters: nil,
            averageHeartRate: nil,
            maxHeartRate: nil,
            source: .localGym,
            sourceName: "Test",
            completedSets: 3,
            totalSets: 3,
            mainMuscleGroups: ["Chest"],
            muscleLoadByMatrixGroup: [.chest: 3],
            muscleExercisesByMatrixGroup: [.chest: ["Bench Press"]]
        )
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }
}
