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

    func testWellnessAverageUsesAllEightSignalsAndInvertsStrainSignals() {
        let entry = PulsarDailyJournalEntry(
            date: date(year: 2026, month: 5, day: 23),
            valence: 1,
            energy: 0.8,
            stress: 0.2,
            gratitude: 0.6,
            anxiety: 0.1,
            socialConnection: 0.7,
            productivity: 0.5,
            sleepPerception: 0.4
        )

        XCTAssertEqual(entry.wellnessAverage, 0.7125, accuracy: 0.0001)
    }

    func testWeekSnapshotUsesMondayThroughSunday() {
        let referenceDate = date(year: 2026, month: 7, day: 1)
        let snapshot = PulsarMindfulnessWeekSnapshot(
            entries: [],
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.days.count, 7)
        XCTAssertTrue(
            calendar.isDate(
                snapshot.days[0].date,
                inSameDayAs: date(year: 2026, month: 6, day: 29)
            )
        )
        XCTAssertTrue(
            calendar.isDate(
                snapshot.days[6].date,
                inSameDayAs: date(year: 2026, month: 7, day: 5)
            )
        )
    }

    func testWeekSnapshotAverageUsesOnlyLoggedDays() {
        let monday = entry(date: date(year: 2026, month: 6, day: 29))
        let friday = PulsarDailyJournalEntry(
            date: date(year: 2026, month: 7, day: 3),
            valence: 1,
            energy: 1,
            stress: 0,
            gratitude: 1,
            anxiety: 0,
            socialConnection: 1,
            productivity: 1,
            sleepPerception: 1
        )
        let previousSunday = entry(date: date(year: 2026, month: 6, day: 28))

        let snapshot = PulsarMindfulnessWeekSnapshot(
            entries: [monday, friday, previousSunday],
            referenceDate: date(year: 2026, month: 7, day: 1),
            calendar: calendar
        )

        let expectedAverage = (monday.wellnessAverage + friday.wellnessAverage) / 2
        XCTAssertEqual(snapshot.wellnessAverage ?? 0, expectedAverage, accuracy: 0.0001)
        XCTAssertEqual(snapshot.days.compactMap(\.entry).count, 2)
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

    @MainActor
    func testConsecutiveMoodLogsProduceStableStreakWhenTodayIsUpdated() {
        let yesterday = date(year: 2026, month: 6, day: 28, hour: 20)
        let today = date(year: 2026, month: 6, day: 29, hour: 20)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pulsar-mindfulness-streak-tests-\(UUID().uuidString)", isDirectory: true)
        let fileStore = PulsarMindfulnessFileStore(directoryURL: directory)
        let store = PulsarMindfulnessStore(fileStore: fileStore, calendar: calendar, now: today)

        store.saveCheckIn(
            PulsarDailyJournalDraft(date: yesterday),
            now: yesterday,
            playsHaptic: false
        )
        store.saveCheckIn(
            PulsarDailyJournalDraft(date: today),
            now: today,
            playsHaptic: false
        )

        XCTAssertEqual(store.dashboard.streak.currentStreak, 2)
        XCTAssertEqual(store.state.entries.count, 2)

        var updatedToday = store.draft(for: today)
        updatedToday.valence = 1
        store.saveCheckIn(updatedToday, now: today, playsHaptic: false)

        XCTAssertEqual(store.dashboard.streak.currentStreak, 2)
        XCTAssertEqual(store.state.entries.count, 2)

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
