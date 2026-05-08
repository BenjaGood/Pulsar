import Foundation
import UserNotifications

@MainActor
final class IntelligentNotificationManager {
    static let shared = IntelligentNotificationManager()

    private let preferencesStore: IntelligentNotificationPreferencesStore
    private let cooldownStore: NotificationCooldownStore
    private let processedStore: ProcessedHealthEventStore
    private let scheduler: IntelligentNotificationScheduling
    private let contentBuilder: NotificationContentBuilder
    private let decisionEngine: NotificationDecisionEngine
    private let calendar: Calendar

    init(
        preferencesStore: IntelligentNotificationPreferencesStore? = nil,
        cooldownStore: NotificationCooldownStore? = nil,
        processedStore: ProcessedHealthEventStore? = nil,
        scheduler: IntelligentNotificationScheduling? = nil,
        contentBuilder: NotificationContentBuilder? = nil,
        decisionEngine: NotificationDecisionEngine? = nil,
        calendar: Calendar = .current
    ) {
        self.preferencesStore = preferencesStore ?? .shared
        self.cooldownStore = cooldownStore ?? NotificationCooldownStore()
        self.processedStore = processedStore ?? ProcessedHealthEventStore()
        self.scheduler = scheduler ?? UserNotificationIntelligentScheduler()
        self.contentBuilder = contentBuilder ?? NotificationContentBuilder()
        self.decisionEngine = decisionEngine ?? NotificationDecisionEngine()
        self.calendar = calendar
        self.scheduler.registerCategories()
    }

    func evaluateDashboard(profile: UserProfile, dashboard: HomeDashboard, now: Date = Date()) async {
        await evaluateHighStress(profile: profile, stress: dashboard.stress, now: now)
        await scheduleWindDownIfNeeded(profile: profile, dashboard: dashboard, now: now)
        await evaluateSleepSummary(sleep: dashboard.sleep, recovery: dashboard.recovery, now: now)
    }

    @discardableResult
    func handleCompletedWorkout(
        _ event: WorkoutNotificationEvent,
        dashboard: HomeDashboard,
        now: Date = Date()
    ) async -> Bool {
        let preferences = preferencesStore.preferences
        guard await canDeliverNotifications(),
              decisionEngine.shouldSendPostWorkout(
                event: event,
                preferences: preferences,
                hasProcessed: processedStore.hasProcessedWorkout(id: event.id),
                now: now
              ) else {
            return false
        }

        let payload = contentBuilder.postWorkoutContent(event: event, dashboard: dashboard)
        guard await schedule(payload: payload, now: now) else { return false }
        processedStore.markWorkoutProcessed(id: event.id)
        return true
    }

    @discardableResult
    func evaluateHighStress(
        profile: UserProfile,
        stress: StressSummary,
        now: Date = Date()
    ) async -> Bool {
        let preferences = preferencesStore.preferences
        guard await canDeliverNotifications(),
              decisionEngine.shouldSendHighStress(
                stress: stress,
                schedule: profile.sleepSchedule,
                preferences: preferences,
                lastSent: cooldownStore.lastHighStressNotificationDate,
                now: now
              ) else {
            return false
        }

        let payload = contentBuilder.highStressContent(stress: stress)
        guard await schedule(payload: payload, now: now, replacing: [payload.identifier]) else { return false }
        cooldownStore.markHighStressNotificationSent(at: now)
        return true
    }

    @discardableResult
    func scheduleWindDownIfNeeded(
        profile: UserProfile,
        dashboard: HomeDashboard,
        now: Date = Date()
    ) async -> Bool {
        let preferences = preferencesStore.preferences
        guard await canDeliverNotifications(),
              let decision = decisionEngine.windDownDecision(
                profile: profile,
                preferences: preferences,
                lastScheduledDayKey: cooldownStore.lastWindDownNotificationDay,
                now: now
              ) else {
            return false
        }

        var payload = contentBuilder.windDownContent(profile: profile, dashboard: dashboard)
        payload.identifier = "pulsar.notification.windDown.\(decision.dayKey)"
        payload.deliveryDate = decision.triggerDate

        guard await schedule(payload: payload, now: now, replacing: [payload.identifier]) else { return false }
        cooldownStore.markWindDownNotificationScheduled(for: decision.dayKey)
        return true
    }

    @discardableResult
    func evaluateSleepSummary(
        sleep: SleepSummary,
        recovery: RecoverySummary,
        now: Date = Date()
    ) async -> Bool {
        let preferences = preferencesStore.preferences
        let dayKey = contentBuilder.sleepSessionIdentifier(for: sleep, calendar: calendar)
        guard await canDeliverNotifications(),
              decisionEngine.shouldSendSleepSummary(
                sleep: sleep,
                preferences: preferences,
                hasProcessed: processedStore.hasProcessedSleepSession(id: dayKey),
                lastNotificationDay: cooldownStore.lastSleepSummaryNotificationDay,
                dayKey: dayKey,
                now: now
              ) else {
            return false
        }

        var payload = contentBuilder.sleepSummaryContent(sleep: sleep, recovery: recovery)
        payload.identifier = "pulsar.notification.sleepSummary.\(dayKey)"

        guard await schedule(payload: payload, now: now, replacing: [payload.identifier]) else { return false }
        processedStore.markSleepSessionProcessed(id: dayKey)
        cooldownStore.markSleepSummaryNotificationSent(for: dayKey)
        return true
    }

    private func canDeliverNotifications() async -> Bool {
        guard preferencesStore.preferences.intelligentNotificationsEnabled else { return false }
        let status = await scheduler.authorizationStatus()
        return status.allowsPulsarNotifications
    }

    private func schedule(
        payload: PulsarNotificationPayload,
        now: Date,
        replacing identifiers: [String] = []
    ) async -> Bool {
        if !identifiers.isEmpty {
            scheduler.removePendingNotificationRequests(withIdentifiers: identifiers)
        }

        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.body
        content.categoryIdentifier = payload.category.rawValue
        content.threadIdentifier = "pulsar.intelligentNotifications"
        content.sound = .default

        let trigger: UNNotificationTrigger
        if let deliveryDate = payload.deliveryDate, deliveryDate.timeIntervalSince(now) > 10 {
            trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: deliveryDate),
                repeats: false
            )
        } else {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        }

        let request = UNNotificationRequest(identifier: payload.identifier, content: content, trigger: trigger)
        do {
            try await scheduler.add(request)
            return true
        } catch {
            return false
        }
    }
}
