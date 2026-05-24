//
//  DailyRewindTests.swift
//  PulsarTests
//

import UserNotifications
import XCTest
@testable import Pulsar

@MainActor
final class DailyRewindTests: XCTestCase {
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

    func testSchedulesDailyRewindOnceWithDeepLinkUserInfo() async {
        let harness = makeNotificationHarness()
        let now = date(year: 2026, month: 5, day: 23, hour: 18)

        let first = await harness.rewindScheduler.syncReminder(journalCompletedToday: false, now: now)
        let second = await harness.rewindScheduler.syncReminder(journalCompletedToday: false, now: now.addingTimeInterval(60))

        XCTAssertTrue(first)
        XCTAssertTrue(second)
        XCTAssertEqual(harness.notificationScheduler.requests.count, 1)

        let request = try! XCTUnwrap(harness.notificationScheduler.requests.first)
        XCTAssertEqual(request.identifier, DailyRewindNotificationScheduler.requestIdentifier)
        XCTAssertEqual(request.content.categoryIdentifier, IntelligentNotificationCategory.dailyRewind.rawValue)
        XCTAssertEqual(request.content.threadIdentifier, DailyRewindNotificationScheduler.threadIdentifier)
        XCTAssertEqual(request.content.userInfo["pulsar.destination"] as? String, "mindfulness.dailyRewind")
        XCTAssertEqual(request.content.userInfo["pulsar.deepLinkURL"] as? String, "aetherial-pulsar://daily-rewind?date=2026-05-23")

        let trigger = try! XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger.dateComponents.hour, 20)
        XCTAssertEqual(trigger.dateComponents.minute, 0)
        XCTAssertEqual(trigger.dateComponents.day, 23)
    }

    func testCompletedJournalSchedulesTomorrowInsteadOfTonight() async {
        let harness = makeNotificationHarness()
        let now = date(year: 2026, month: 5, day: 23, hour: 18)

        let scheduled = await harness.rewindScheduler.syncReminder(journalCompletedToday: true, now: now)

        XCTAssertTrue(scheduled)
        let request = try! XCTUnwrap(harness.notificationScheduler.requests.first)
        let trigger = try! XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger.dateComponents.day, 24)
        XCTAssertEqual(request.content.userInfo["pulsar.dateKey"] as? String, "2026-05-24")
    }

    func testNotificationPermissionDenialCancelsRewindReminder() async {
        let harness = makeNotificationHarness(status: .denied)
        let now = date(year: 2026, month: 5, day: 23, hour: 18)

        let scheduled = await harness.rewindScheduler.syncReminder(journalCompletedToday: false, now: now)

        XCTAssertFalse(scheduled)
        XCTAssertTrue(harness.notificationScheduler.requests.isEmpty)
        XCTAssertTrue(harness.notificationScheduler.removedIdentifiers.contains(DailyRewindNotificationScheduler.requestIdentifier))
    }

    func testDeepLinkRoutesToMindfulnessDailyRewind() {
        let url = URL(string: "aetherial-pulsar://daily-rewind?date=2026-05-23")!

        XCTAssertEqual(
            PulsarDeepLinkRoute(url: url),
            .mindfulnessDailyRewind(dateKey: "2026-05-23")
        )
    }

    func testNotificationUserInfoRoutesToMindfulnessDailyRewind() {
        let route = PulsarDeepLinkRoute(notificationUserInfo: [
            "pulsar.notification.kind": "dailyRewind",
            "pulsar.destination": "mindfulness.dailyRewind",
            "pulsar.dateKey": "2026-05-23"
        ])

        XCTAssertEqual(route, .mindfulnessDailyRewind(dateKey: "2026-05-23"))
    }

    func testMissingDataBuildsQuietPlaceholderRewind() {
        let rewind = DailyRewindBuilder(calendar: calendar).build(
            date: date(year: 2026, month: 5, day: 23),
            dashboard: .empty,
            mindfulness: .empty
        )

        XCTAssertEqual(rewind.availability, .noData)
        XCTAssertEqual(rewind.cards.first(where: { $0.kind == .reflection })?.state, .placeholder)
        XCTAssertEqual(rewind.insight.title, "A simple check-in is enough")
    }

    func testCompletedJournalBuildsCompletedRewind() {
        let today = date(year: 2026, month: 5, day: 23, hour: 21)
        let entry = journalEntry(date: today, valence: 0.42)
        let dashboard = PulsarMindfulnessInsightsEngine(calendar: calendar).dashboard(
            entries: [entry],
            sessions: [],
            now: today
        )
        let state = PulsarMindfulnessState(entries: [entry], sessions: [], dashboard: dashboard)

        let rewind = DailyRewindBuilder(calendar: calendar).build(
            date: today,
            dashboard: healthDashboard(date: today),
            mindfulness: state
        )

        XCTAssertEqual(rewind.cards.first(where: { $0.kind == .reflection })?.state, .ready)
        XCTAssertEqual(rewind.cards.first(where: { $0.kind == .reflection })?.value, entry.moodTitle)
        XCTAssertTrue(rewind.subtitle.contains("reflection"))
    }

    func testIncompleteJournalBuildsCheckInCTA() {
        let today = date(year: 2026, month: 5, day: 23, hour: 21)
        let session = PulsarMindfulnessSessionSummary(
            templateID: "breathing-relaxation",
            title: "Relaxation breathing",
            category: .breathing,
            startedAt: today.addingTimeInterval(-40 * 60),
            endedAt: today.addingTimeInterval(-34 * 60),
            duration: 6 * 60,
            completedCycles: 12
        )
        let dashboard = PulsarMindfulnessInsightsEngine(calendar: calendar).dashboard(
            entries: [],
            sessions: [session],
            now: today
        )
        let state = PulsarMindfulnessState(entries: [], sessions: [session], dashboard: dashboard)

        let rewind = DailyRewindBuilder(calendar: calendar).build(
            date: today,
            dashboard: healthDashboard(date: today),
            mindfulness: state
        )

        XCTAssertEqual(rewind.availability, .ready)
        XCTAssertEqual(rewind.cards.first(where: { $0.kind == .reflection })?.state, .placeholder)
        XCTAssertEqual(rewind.cards.first(where: { $0.kind == .mindfulness })?.value, "6 min")
    }

    func testLegacyNotificationPreferencesDefaultDailyRewindToEnabled() throws {
        let legacyJSON = """
        {
          "intelligentNotificationsEnabled": true,
          "postWorkoutSummaryEnabled": true,
          "highStressAlertsEnabled": true,
          "windDownRemindersEnabled": true,
          "sleepSummaryEnabled": true,
          "respectQuietHoursPlaceholder": true
        }
        """

        let preferences = try JSONDecoder().decode(
            IntelligentNotificationPreferences.self,
            from: Data(legacyJSON.utf8)
        )

        XCTAssertTrue(preferences.dailyRewindRemindersEnabled)
    }

    private func makeNotificationHarness(
        status: UNAuthorizationStatus = .authorized
    ) -> DailyRewindNotificationHarness {
        let suffix = UUID().uuidString
        let defaults = UserDefaults(suiteName: "pulsar.tests.dailyRewind.preferences.\(suffix)")!
        let notificationScheduler = RecordingDailyRewindNotificationScheduler(status: status)
        let preferencesStore = IntelligentNotificationPreferencesStore(
            defaults: defaults,
            scheduler: notificationScheduler,
            permissionStore: NotificationPermissionStore(defaults: defaults)
        )
        preferencesStore.update {
            $0.intelligentNotificationsEnabled = true
            $0.dailyRewindRemindersEnabled = true
        }

        let rewindScheduler = DailyRewindNotificationScheduler(
            preferencesStore: preferencesStore,
            scheduler: notificationScheduler,
            calendar: calendar
        )

        return DailyRewindNotificationHarness(
            notificationScheduler: notificationScheduler,
            rewindScheduler: rewindScheduler
        )
    }

    private func healthDashboard(date: Date) -> HomeDashboard {
        var dashboard = HomeDashboard.empty
        dashboard.generatedAt = date
        dashboard.strain.date = date
        dashboard.strain.steps = 8_420
        dashboard.strain.activeEnergyKilocalories = 486
        dashboard.strain.workoutMinutes = 42
        dashboard.strain.workouts = [
            StrainWorkoutSummary(
                workoutType: "Run",
                startDate: date.addingTimeInterval(-3 * 60 * 60),
                endDate: date.addingTimeInterval(-2.3 * 60 * 60),
                activeEnergyKilocalories: 320,
                averageHeartRate: 142,
                peakHeartRate: 168,
                sourceName: "Apple Watch"
            )
        ]
        dashboard.recovery.date = date
        dashboard.recovery.score = 78
        dashboard.recovery.analyzedSampleCount = 8
        dashboard.recovery.hrvSDNN = 54
        dashboard.sleep.totalSleepMinutes = 458
        dashboard.sleep.analyzedSampleCount = 10
        dashboard.stress.date = date
        dashboard.stress.score = 44
        dashboard.stress.dailyAverageScore = 48
        dashboard.stress.level = .balanced
        dashboard.stress.analyzedSampleCount = 6
        return dashboard
    }

    private func journalEntry(date: Date, valence: Double) -> PulsarDailyJournalEntry {
        PulsarDailyJournalEntry(
            date: date,
            valence: valence,
            energy: 0.62,
            stress: 0.31,
            gratitude: 0.68,
            anxiety: 0.18,
            socialConnection: 0.54,
            productivity: 0.58,
            sleepPerception: 0.66,
            emotionLabels: [.calm, .grateful],
            associations: [.movement, .recovery]
        )
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}

@MainActor
private final class RecordingDailyRewindNotificationScheduler: IntelligentNotificationScheduling {
    var status: UNAuthorizationStatus
    private var pending: [String: UNNotificationRequest] = [:]
    private(set) var removedIdentifiers: [String] = []

    init(status: UNAuthorizationStatus) {
        self.status = status
    }

    var requests: [UNNotificationRequest] {
        Array(pending.values)
    }

    func registerCategories() {}

    func authorizationStatus() async -> UNAuthorizationStatus {
        status
    }

    func requestAuthorization() async -> Bool {
        status = .authorized
        return true
    }

    func add(_ request: UNNotificationRequest) async throws {
        pending[request.identifier] = request
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(contentsOf: identifiers)
        for identifier in identifiers {
            pending.removeValue(forKey: identifier)
        }
    }
}

private struct DailyRewindNotificationHarness {
    var notificationScheduler: RecordingDailyRewindNotificationScheduler
    var rewindScheduler: DailyRewindNotificationScheduler
}
