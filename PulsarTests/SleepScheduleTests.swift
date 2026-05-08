import XCTest
@testable import Pulsar

final class SleepScheduleTests: XCTestCase {
    func testOvernightDurationIsDerivedFromBedtimeAndWakeTime() {
        let schedule = SleepSchedule(
            bedtimeMinutesFromMidnight: 22 * 60 + 30,
            wakeTimeMinutesFromMidnight: 6 * 60 + 30
        )

        XCTAssertEqual(schedule.targetSleepDurationMinutes, 8 * 60)
        XCTAssertEqual(schedule.targetSleepHours, 8, accuracy: 0.001)
    }

    func testWakeTimeUpdatesAlarmWhenAlarmUsesWakeTime() {
        var schedule = SleepSchedule(
            bedtimeMinutesFromMidnight: 22 * 60 + 30,
            wakeTimeMinutesFromMidnight: 6 * 60 + 30,
            alarmEnabled: true,
            alarmUsesWakeTime: true
        )

        schedule.setWakeTimeMinutes(7 * 60)

        XCTAssertEqual(schedule.wakeTimeMinutesFromMidnight, 7 * 60)
        XCTAssertEqual(schedule.resolvedAlarmTimeMinutesFromMidnight, 7 * 60)
    }

    func testCustomAlarmTimeRemainsStableWhenWakeTimeChanges() {
        var schedule = SleepSchedule(
            bedtimeMinutesFromMidnight: 22 * 60 + 30,
            wakeTimeMinutesFromMidnight: 6 * 60 + 30,
            alarmEnabled: true,
            alarmUsesWakeTime: true
        )

        schedule.setAlarmTimeMinutes(6 * 60)
        schedule.setWakeTimeMinutes(7 * 60)

        XCTAssertFalse(schedule.alarmUsesWakeTime)
        XCTAssertEqual(schedule.resolvedAlarmTimeMinutesFromMidnight, 6 * 60)
    }

    func testLegacySleepScheduleDecodingDefaultsAlarmToWakeTime() throws {
        let data = """
        {
          "targetBedtimeHour": 22,
          "targetBedtimeMinute": 30,
          "targetWakeHour": 6,
          "targetWakeMinute": 30,
          "targetSleepHours": 8
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SleepSchedule.self, from: data)

        XCTAssertEqual(decoded.bedtimeMinutesFromMidnight, 22 * 60 + 30)
        XCTAssertEqual(decoded.wakeTimeMinutesFromMidnight, 6 * 60 + 30)
        XCTAssertTrue(decoded.alarmUsesWakeTime)
        XCTAssertEqual(decoded.resolvedAlarmTimeMinutesFromMidnight, 6 * 60 + 30)
    }
}
