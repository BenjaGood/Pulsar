import Combine
import Foundation

@MainActor
final class NotificationPermissionStore: ObservableObject {
    static let shared = NotificationPermissionStore()

    @Published private(set) var hasRequestedSleepAlarmPermission: Bool
    @Published private(set) var hasRequestedIntelligentNotificationPermission: Bool

    private let defaults: UserDefaults
    private let sleepAlarmKey = "pulsar.notifications.sleepAlarm.prompted.v1"
    private let intelligentNotificationKey = "pulsar.notifications.intelligent.prompted.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasRequestedSleepAlarmPermission = defaults.bool(forKey: sleepAlarmKey)
        self.hasRequestedIntelligentNotificationPermission = defaults.bool(forKey: intelligentNotificationKey)
    }

    func markSleepAlarmPermissionRequested() {
        guard !hasRequestedSleepAlarmPermission else { return }
        hasRequestedSleepAlarmPermission = true
        defaults.set(true, forKey: sleepAlarmKey)
    }

    func markIntelligentNotificationPermissionRequested() {
        guard !hasRequestedIntelligentNotificationPermission else { return }
        hasRequestedIntelligentNotificationPermission = true
        defaults.set(true, forKey: intelligentNotificationKey)
    }
}
