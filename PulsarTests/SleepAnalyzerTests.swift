//
//  SleepAnalyzerTests.swift
//  PulsarTests
//

import XCTest
@testable import Pulsar

final class SleepAnalyzerTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testSimpleFullNightSleep() {
        let wakeDate = date(2026, 5, 4)
        let samples = [
            sample(.inBed, "2026-05-03 22:00", "2026-05-04 07:00"),
            sample(.asleepCore, "2026-05-03 22:30", "2026-05-04 02:00"),
            sample(.asleepDeep, "2026-05-04 02:00", "2026-05-04 03:00"),
            sample(.asleepREM, "2026-05-04 03:00", "2026-05-04 07:00")
        ]

        let summary = SleepAnalyzer().analyze(samples: samples, wakeUpDate: wakeDate, calendar: calendar)

        XCTAssertEqual(summary.totalSleepMinutes, 510, accuracy: 0.1)
        XCTAssertEqual(summary.timeInBedMinutes, 540, accuracy: 0.1)
        XCTAssertEqual(summary.deepMinutes, 60, accuracy: 0.1)
        XCTAssertEqual(summary.remMinutes, 240, accuracy: 0.1)
    }

    func testSleepCrossingMidnightBelongsToWakeUpDay() {
        let wakeDate = date(2026, 5, 4)
        let summary = SleepAnalyzer().analyze(
            samples: [sample(.asleepUnspecified, "2026-05-03 23:00", "2026-05-04 06:00")],
            wakeUpDate: wakeDate,
            calendar: calendar
        )

        XCTAssertEqual(summary.queryStart, dateTime("2026-05-03 18:00"))
        XCTAssertEqual(summary.queryEnd, dateTime("2026-05-04 12:00"))
        XCTAssertEqual(summary.totalSleepMinutes, 420, accuracy: 0.1)
    }

    func testInBedDoesNotCountAsActualSleep() {
        let summary = SleepAnalyzer().analyze(
            samples: [sample(.inBed, "2026-05-03 22:00", "2026-05-04 06:00")],
            wakeUpDate: date(2026, 5, 4),
            calendar: calendar
        )

        XCTAssertTrue(summary.hasSamples)
        XCTAssertEqual(summary.totalSleepMinutes, 0, accuracy: 0.1)
        XCTAssertEqual(summary.timeInBedMinutes, 480, accuracy: 0.1)
    }

    func testAwakeDuringSleepIsNotCountedAsSleep() {
        let samples = [
            sample(.asleepCore, "2026-05-03 22:00", "2026-05-04 02:00"),
            sample(.awake, "2026-05-04 02:00", "2026-05-04 02:30"),
            sample(.asleepREM, "2026-05-04 02:30", "2026-05-04 06:00")
        ]

        let summary = SleepAnalyzer().analyze(samples: samples, wakeUpDate: date(2026, 5, 4), calendar: calendar)

        XCTAssertEqual(summary.totalSleepMinutes, 450, accuracy: 0.1)
        XCTAssertEqual(summary.awakeMinutes, 30, accuracy: 0.1)
        XCTAssertEqual(summary.wasoMinutes, 30, accuracy: 0.1)
    }

    func testOverlappingAsleepSamplesDoNotDoubleCount() {
        let samples = [
            sample(.asleepUnspecified, "2026-05-03 22:00", "2026-05-04 06:00"),
            sample(.asleepDeep, "2026-05-04 01:00", "2026-05-04 03:00")
        ]

        let summary = SleepAnalyzer().analyze(samples: samples, wakeUpDate: date(2026, 5, 4), calendar: calendar)

        XCTAssertEqual(summary.totalSleepMinutes, 480, accuracy: 0.1)
        XCTAssertEqual(summary.deepMinutes, 120, accuracy: 0.1)
        XCTAssertEqual(summary.asleepUnspecifiedMinutes, 360, accuracy: 0.1)
    }

    func testMultipleSourcesDoNotDoubleCountSameNight() {
        let samples = [
            sample(.asleepCore, "2026-05-03 22:00", "2026-05-04 06:00", id: "watch", source: "Apple Watch"),
            sample(.asleepCore, "2026-05-03 22:00", "2026-05-04 06:00", id: "oura", source: "Oura")
        ]

        let summary = SleepAnalyzer().analyze(samples: samples, wakeUpDate: date(2026, 5, 4), calendar: calendar)

        XCTAssertEqual(summary.totalSleepMinutes, 480, accuracy: 0.1)
        XCTAssertEqual(summary.sourceNames, ["Apple Watch", "Oura"])
    }

    func testNoSamplesReturnsEmptySummary() {
        let summary = SleepAnalyzer().analyze(samples: [], wakeUpDate: date(2026, 5, 4), calendar: calendar)

        XCTAssertFalse(summary.hasSamples)
        XCTAssertEqual(summary.totalSleepMinutes, 0, accuracy: 0.1)
        XCTAssertTrue(summary.mergedIntervals.isEmpty)
    }

    private func sample(_ stage: SleepAnalysisStage, _ start: String, _ end: String, id: String = UUID().uuidString, source: String = "Apple Watch") -> SleepAnalysisSample {
        SleepAnalysisSample(
            id: id,
            stage: stage,
            start: dateTime(start),
            end: dateTime(end),
            sourceName: source,
            sourceBundleIdentifier: source == "Apple Watch" ? "com.apple.health" : "com.example.\(source.lowercased())",
            deviceName: source
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func dateTime(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }
}
