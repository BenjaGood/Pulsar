//
//  DailyRewindNotificationScheduler.swift
//  Pulsar
//

import Foundation
import UserNotifications

struct DailyRewindReminderSchedule: Equatable {
    var hour: Int = 20
    var minute: Int = 0

    nonisolated init(hour: Int = 20, minute: Int = 0) {
        self.hour = hour
        self.minute = minute
    }
}

@MainActor
final class DailyRewindNotificationScheduler {
    static let shared = DailyRewindNotificationScheduler()

    static let requestIdentifier = "pulsar.notification.dailyRewind.next"
    static let categoryIdentifier = "pulsar.notification.dailyRewind"
    static let threadIdentifier = "pulsar.mindfulness.dailyRewind"
    static let targetContentIdentifier = "pulsar.route.mindfulness.dailyRewind"

    private let preferencesStore: IntelligentNotificationPreferencesStore
    private let scheduler: IntelligentNotificationScheduling
    private let calendar: Calendar
    private let schedule: DailyRewindReminderSchedule

    init(
        preferencesStore: IntelligentNotificationPreferencesStore? = nil,
        scheduler: IntelligentNotificationScheduling? = nil,
        calendar: Calendar = .current,
        schedule: DailyRewindReminderSchedule = DailyRewindReminderSchedule()
    ) {
        self.preferencesStore = preferencesStore ?? .shared
        self.scheduler = scheduler ?? UserNotificationIntelligentScheduler()
        self.calendar = calendar
        self.schedule = schedule
        self.scheduler.registerCategories()
    }

    @discardableResult
    func syncReminder(
        journalCompletedToday: Bool,
        now: Date = Date()
    ) async -> Bool {
        let preferences = preferencesStore.preferences
        guard preferences.intelligentNotificationsEnabled,
              preferences.dailyRewindRemindersEnabled else {
            cancelReminder()
            return false
        }

        let status = await scheduler.authorizationStatus()
        guard status.allowsPulsarNotifications else {
            cancelReminder()
            return false
        }

        let triggerDate = nextTriggerDate(now: now, journalCompletedToday: journalCompletedToday)
        let request = request(for: triggerDate)
        scheduler.removePendingNotificationRequests(withIdentifiers: [Self.requestIdentifier])

        do {
            try await scheduler.add(request)
            return true
        } catch {
            return false
        }
    }

    func cancelReminder() {
        scheduler.removePendingNotificationRequests(withIdentifiers: [Self.requestIdentifier])
    }

    func nextTriggerDate(now: Date = Date(), journalCompletedToday: Bool) -> Date {
        let todayTrigger = triggerDate(on: now) ?? now
        if !journalCompletedToday, now < todayTrigger {
            return todayTrigger
        }

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(24 * 60 * 60)
        return triggerDate(on: tomorrow) ?? tomorrow
    }

    private func request(for triggerDate: Date) -> UNNotificationRequest {
        let dateKey = DailyRewindDateKey.string(for: triggerDate, calendar: calendar)
        let content = UNMutableNotificationContent()
        content.title = "Time to rewind your day"
        content.body = "Review your movement, recovery, and mindfulness before closing the day."
        content.categoryIdentifier = IntelligentNotificationCategory.dailyRewind.rawValue
        content.threadIdentifier = Self.threadIdentifier
        content.targetContentIdentifier = Self.targetContentIdentifier
        content.sound = .default
        content.userInfo = [
            "pulsar.notification.kind": "dailyRewind",
            "pulsar.destination": "mindfulness.dailyRewind",
            "pulsar.rootTab": "mindfulness",
            "pulsar.presentation": "dailyRewind",
            "pulsar.dateKey": dateKey,
            "pulsar.deepLinkURL": "aetherial-pulsar://daily-rewind?date=\(dateKey)"
        ]

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: Self.requestIdentifier, content: content, trigger: trigger)
    }

    private func triggerDate(on date: Date) -> Date? {
        calendar.date(
            bySettingHour: schedule.hour,
            minute: schedule.minute,
            second: 0,
            of: date
        )
    }
}
