//
//  MindfulnessEngineTests.swift
//  PulsarTests
//

import XCTest
@testable import Pulsar

final class MindfulnessEngineTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        self.calendar = calendar
    }

    override func tearDown() {
        calendar = nil
        super.tearDown()
    }

    func testBreathingPatternReturnsExpectedPhaseSnapshot() {
        let pattern = PulsarMindfulnessContentLibrary.pattern(for: .relaxation)!

        let inhale = pattern.snapshot(at: 2)
        XCTAssertEqual(inhale?.phase.kind, .inhale)
        XCTAssertEqual(inhale?.phaseProgress ?? 0, 0.5, accuracy: 0.001)

        let exhale = pattern.snapshot(at: 5)
        XCTAssertEqual(exhale?.phase.kind, .exhale)
        XCTAssertEqual(exhale?.cycleIndex, 0)
        XCTAssertEqual(exhale?.phaseProgress ?? 0, 1.0 / 6.0, accuracy: 0.001)

        let nextCycle = pattern.snapshot(at: 10.2)
        XCTAssertEqual(nextCycle?.phase.kind, .inhale)
        XCTAssertEqual(nextCycle?.cycleIndex, 1)
    }

    func testStreakCountsConsecutiveCheckInDays() {
        let today = date(year: 2026, month: 5, day: 23)
        let engine = PulsarMindfulnessInsightsEngine(calendar: calendar)
        let entries = [
            entry(date: today),
            entry(date: date(year: 2026, month: 5, day: 22)),
            entry(date: date(year: 2026, month: 5, day: 20))
        ]

        let streak = engine.streakSummary(entries: entries, now: today)

        XCTAssertEqual(streak.currentStreak, 2)
        XCTAssertEqual(streak.longestStreak, 2)
        XCTAssertTrue(streak.hasToday)
    }

    @MainActor
    func testMindfulnessStorePersistsCheckIns() {
        let today = date(year: 2026, month: 5, day: 23, hour: 21)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pulsar-mindfulness-tests-\(UUID().uuidString)", isDirectory: true)
        let fileStore = PulsarMindfulnessFileStore(directoryURL: directory)
        var draft = PulsarDailyJournalDraft(date: today)
        draft.valence = 0.42
        draft.energy = 0.64
        draft.emotionLabels = [.calm, .grateful]

        let store = PulsarMindfulnessStore(fileStore: fileStore, calendar: calendar, now: today)
        store.saveCheckIn(draft, now: today)

        let reloaded = PulsarMindfulnessStore(fileStore: fileStore, calendar: calendar, now: today)

        XCTAssertEqual(reloaded.state.entries.count, 1)
        XCTAssertEqual(reloaded.state.entries.first?.valence ?? 0, 0.42, accuracy: 0.001)
        XCTAssertEqual(Set(reloaded.state.entries.first?.emotionLabels ?? []), [.calm, .grateful])
        XCTAssertTrue(reloaded.dashboard.streak.hasToday)

        try? FileManager.default.removeItem(at: directory)
    }

    private func entry(date: Date) -> PulsarDailyJournalEntry {
        PulsarDailyJournalEntry(
            date: date,
            valence: 0.25,
            energy: 0.5,
            stress: 0.3,
            gratitude: 0.5,
            anxiety: 0.2,
            socialConnection: 0.5,
            productivity: 0.5,
            sleepPerception: 0.5
        )
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
