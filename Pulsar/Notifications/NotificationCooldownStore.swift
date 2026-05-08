import Foundation

final class NotificationCooldownStore {
    private enum Key {
        static let lastHighStressNotificationDate = "pulsar.notifications.highStress.lastDate.v1"
        static let lastWindDownNotificationDay = "pulsar.notifications.windDown.lastDay.v1"
        static let lastSleepSummaryNotificationDay = "pulsar.notifications.sleepSummary.lastDay.v1"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lastHighStressNotificationDate: Date? {
        defaults.object(forKey: Key.lastHighStressNotificationDate) as? Date
    }

    var lastWindDownNotificationDay: String? {
        defaults.string(forKey: Key.lastWindDownNotificationDay)
    }

    var lastSleepSummaryNotificationDay: String? {
        defaults.string(forKey: Key.lastSleepSummaryNotificationDay)
    }

    func markHighStressNotificationSent(at date: Date) {
        defaults.set(date, forKey: Key.lastHighStressNotificationDate)
    }

    func markWindDownNotificationScheduled(for dayKey: String) {
        defaults.set(dayKey, forKey: Key.lastWindDownNotificationDay)
    }

    func markSleepSummaryNotificationSent(for dayKey: String) {
        defaults.set(dayKey, forKey: Key.lastSleepSummaryNotificationDay)
    }

    func reset() {
        defaults.removeObject(forKey: Key.lastHighStressNotificationDate)
        defaults.removeObject(forKey: Key.lastWindDownNotificationDay)
        defaults.removeObject(forKey: Key.lastSleepSummaryNotificationDay)
    }
}
