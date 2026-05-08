import UserNotifications
import XCTest
@testable import Pulsar

@MainActor
final class IntelligentNotificationTests: XCTestCase {
    func testSameWorkoutDoesNotTriggerDuplicateNotification() async {
        let harness = makeHarness()
        let event = workoutEvent(id: "workout-1", now: harness.now)

        let first = await harness.manager.handleCompletedWorkout(event, dashboard: harness.dashboard, now: harness.now)
        let second = await harness.manager.handleCompletedWorkout(event, dashboard: harness.dashboard, now: harness.now)

        XCTAssertTrue(first)
        XCTAssertFalse(second)
        XCTAssertEqual(harness.scheduler.requests.count, 1)
    }

    func testHighStressRespectsCooldown() async {
        let harness = makeHarness(now: fixedDate(hour: 12, minute: 0))
        let secondNow = harness.now.addingTimeInterval(60 * 60)
        let thirdNow = harness.now.addingTimeInterval(6 * 60 * 60)
        let first = await harness.manager.evaluateHighStress(profile: harness.profile, stress: highStressSummary(now: harness.now), now: harness.now)
        let second = await harness.manager.evaluateHighStress(profile: harness.profile, stress: highStressSummary(now: secondNow), now: secondNow)
        let third = await harness.manager.evaluateHighStress(profile: harness.profile, stress: highStressSummary(now: thirdNow), now: thirdNow)

        XCTAssertTrue(first)
        XCTAssertFalse(second)
        XCTAssertTrue(third)
        XCTAssertEqual(harness.scheduler.requests.filter { $0.identifier == "pulsar.notification.highStress" }.count, 2)
    }

    func testHighStressDoesNotSendWhenConfidenceIsLow() async {
        let harness = makeHarness()
        var stress = harness.highStress
        stress.confidence = .low

        let sent = await harness.manager.evaluateHighStress(profile: harness.profile, stress: stress, now: harness.now)

        XCTAssertFalse(sent)
        XCTAssertTrue(harness.scheduler.requests.isEmpty)
    }

    func testWindDownSendsOncePerDay() async {
        let harness = makeHarness(now: fixedDate(hour: 20, minute: 0))

        let first = await harness.manager.scheduleWindDownIfNeeded(profile: harness.profile, dashboard: harness.dashboard, now: harness.now)
        let second = await harness.manager.scheduleWindDownIfNeeded(profile: harness.profile, dashboard: harness.dashboard, now: harness.now.addingTimeInterval(30 * 60))

        XCTAssertTrue(first)
        XCTAssertFalse(second)
        XCTAssertEqual(harness.scheduler.requests.filter { $0.identifier.contains("pulsar.notification.windDown") }.count, 1)
    }

    func testSleepSummarySendsOncePerSleepDay() async {
        let harness = makeHarness(now: fixedDate(hour: 8, minute: 0))
        let sleep = sleepSummary(wakeTime: fixedDate(hour: 6, minute: 30))

        let first = await harness.manager.evaluateSleepSummary(sleep: sleep, recovery: harness.dashboard.recovery, now: harness.now)
        let second = await harness.manager.evaluateSleepSummary(sleep: sleep, recovery: harness.dashboard.recovery, now: harness.now.addingTimeInterval(15 * 60))

        XCTAssertTrue(first)
        XCTAssertFalse(second)
        XCTAssertEqual(harness.scheduler.requests.filter { $0.identifier.contains("pulsar.notification.sleepSummary") }.count, 1)
    }

    func testNotificationsAreNotSentIfPermissionIsDenied() async {
        let harness = makeHarness(authorizationStatus: .denied)
        let event = workoutEvent(id: "workout-denied", now: harness.now)

        let sent = await harness.manager.handleCompletedWorkout(event, dashboard: harness.dashboard, now: harness.now)

        XCTAssertFalse(sent)
        XCTAssertTrue(harness.scheduler.requests.isEmpty)
    }

    func testDisabledTogglesPreventNotifications() async {
        let harness = makeHarness(configurePreferences: { preferences in
            preferences.postWorkoutSummaryEnabled = false
        })
        let event = workoutEvent(id: "workout-disabled", now: harness.now)

        let sent = await harness.manager.handleCompletedWorkout(event, dashboard: harness.dashboard, now: harness.now)

        XCTAssertFalse(sent)
        XCTAssertTrue(harness.scheduler.requests.isEmpty)
    }

    func testAppRefreshDoesNotDuplicateSleepSummary() async {
        let harness = makeHarness(now: fixedDate(hour: 8, minute: 0))
        var dashboard = harness.dashboard
        dashboard.sleep = sleepSummary(wakeTime: fixedDate(hour: 6, minute: 30))

        await harness.manager.evaluateDashboard(profile: harness.profile, dashboard: dashboard, now: harness.now)
        await harness.manager.evaluateDashboard(profile: harness.profile, dashboard: dashboard, now: harness.now.addingTimeInterval(10 * 60))

        XCTAssertEqual(harness.scheduler.requests.filter { $0.identifier.contains("pulsar.notification.sleepSummary") }.count, 1)
    }

    private func makeHarness(
        now: Date = IntelligentNotificationTests.fixedDate(hour: 18, minute: 0),
        authorizationStatus: UNAuthorizationStatus = .authorized,
        configurePreferences: ((inout IntelligentNotificationPreferences) -> Void)? = nil
    ) -> NotificationTestHarness {
        let suffix = UUID().uuidString
        let preferencesDefaults = UserDefaults(suiteName: "pulsar.tests.notifications.preferences.\(suffix)")!
        let permissionDefaults = UserDefaults(suiteName: "pulsar.tests.notifications.permission.\(suffix)")!
        let cooldownDefaults = UserDefaults(suiteName: "pulsar.tests.notifications.cooldown.\(suffix)")!
        let processedDefaults = UserDefaults(suiteName: "pulsar.tests.notifications.processed.\(suffix)")!
        let scheduler = RecordingNotificationScheduler(status: authorizationStatus)
        let permissionStore = NotificationPermissionStore(defaults: permissionDefaults)
        let preferencesStore = IntelligentNotificationPreferencesStore(
            defaults: preferencesDefaults,
            scheduler: scheduler,
            permissionStore: permissionStore
        )
        preferencesStore.update { preferences in
            preferences.intelligentNotificationsEnabled = true
            configurePreferences?(&preferences)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let manager = IntelligentNotificationManager(
            preferencesStore: preferencesStore,
            cooldownStore: NotificationCooldownStore(defaults: cooldownDefaults),
            processedStore: ProcessedHealthEventStore(defaults: processedDefaults),
            scheduler: scheduler,
            decisionEngine: NotificationDecisionEngine(calendar: calendar),
            calendar: calendar
        )

        var profile = MockHealthData.profile
        profile.sleepSchedule = SleepSchedule(
            bedtimeMinutesFromMidnight: 22 * 60 + 30,
            wakeTimeMinutesFromMidnight: 6 * 60 + 30
        )
        profile.sleepGoalDays = .everyDay

        var dashboard = HomeDashboard.sample
        dashboard.profile = profile
        dashboard.stress = highStressSummary(now: now)

        return NotificationTestHarness(
            now: now,
            profile: profile,
            dashboard: dashboard,
            highStress: highStressSummary(now: now),
            scheduler: scheduler,
            manager: manager
        )
    }

    private func workoutEvent(id: String, now: Date) -> WorkoutNotificationEvent {
        WorkoutNotificationEvent(
            id: id,
            workoutType: "Strength",
            startDate: now.addingTimeInterval(-75 * 60),
            endDate: now.addingTimeInterval(-3 * 60),
            activeEnergyKilocalories: 420,
            averageHeartRate: 128,
            maxHeartRate: 164,
            sourceName: "Apple Watch"
        )
    }

    private func highStressSummary(now: Date) -> StressSummary {
        StressSummary(
            date: now,
            score: 82,
            level: .high,
            confidence: .moderate,
            state: .ready,
            driverInsights: ["HRV is below your usual range", "Recent training is contributing"],
            drivers: [
                StressDriver(
                    id: "hrv",
                    title: "HRV is below baseline",
                    detail: "HRV is below your usual range.",
                    severity: .high,
                    relatedMetric: "HRV"
                )
            ],
            signals: [],
            dailySamples: [
                StressSample(timestamp: now.addingTimeInterval(-65 * 60), score: 78, confidence: .moderate, context: .active),
                StressSample(timestamp: now.addingTimeInterval(-30 * 60), score: 82, confidence: .moderate, context: .active)
            ],
            analyzedSampleCount: 10,
            baselineWindowDays: 14,
            availableSignalCount: 4,
            queryStart: now.addingTimeInterval(-6 * 60 * 60),
            queryEnd: now,
            lastUpdated: now,
            sourceBadges: [],
            explanation: "Stress appears elevated from available wearable signals.",
            subtext: StressSummary.estimateSubtext
        )
    }

    private func sleepSummary(wakeTime: Date) -> SleepSummary {
        var sleep = MockHealthData.sleepSummary
        sleep.wakeUpDate = wakeTime
        sleep.wakeTime = wakeTime
        sleep.sleepStart = wakeTime.addingTimeInterval(-8 * 60 * 60)
        sleep.totalSleepMinutes = 7 * 60 + 42
        sleep.sleepEfficiency = 88
        sleep.analyzedSampleCount = 12
        sleep.confidence = .high
        return sleep
    }

    private nonisolated static func fixedDate(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 5
        components.day = 6
        components.hour = hour
        components.minute = minute
        return components.date!
    }

    private nonisolated func fixedDate(hour: Int, minute: Int) -> Date {
        Self.fixedDate(hour: hour, minute: minute)
    }
}

@MainActor
private final class RecordingNotificationScheduler: IntelligentNotificationScheduling {
    var status: UNAuthorizationStatus
    private(set) var requests: [UNNotificationRequest] = []
    private(set) var removedIdentifiers: [String] = []

    init(status: UNAuthorizationStatus) {
        self.status = status
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
        requests.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(contentsOf: identifiers)
    }
}

private struct NotificationTestHarness {
    var now: Date
    var profile: UserProfile
    var dashboard: HomeDashboard
    var highStress: StressSummary
    var scheduler: RecordingNotificationScheduler
    var manager: IntelligentNotificationManager
}
