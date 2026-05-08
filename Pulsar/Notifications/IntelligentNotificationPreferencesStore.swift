import Combine
import Foundation
import UserNotifications

@MainActor
final class IntelligentNotificationPreferencesStore: ObservableObject {
    static let shared = IntelligentNotificationPreferencesStore()

    @Published private(set) var preferences: IntelligentNotificationPreferences
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private enum Key {
        static let preferences = "pulsar.notifications.intelligent.preferences.v1"
    }

    private let defaults: UserDefaults
    private let scheduler: IntelligentNotificationScheduling
    private let permissionStore: NotificationPermissionStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        defaults: UserDefaults = .standard,
        scheduler: IntelligentNotificationScheduling? = nil,
        permissionStore: NotificationPermissionStore? = nil
    ) {
        self.defaults = defaults
        self.scheduler = scheduler ?? UserNotificationIntelligentScheduler()
        self.permissionStore = permissionStore ?? .shared
        if let data = defaults.data(forKey: Key.preferences),
           let decoded = try? decoder.decode(IntelligentNotificationPreferences.self, from: data) {
            self.preferences = decoded
        } else {
            self.preferences = .default
        }
        self.scheduler.registerCategories()
    }

    var permissionStatusTitle: String {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            "Allowed"
        case .denied:
            "Permission Needed"
        case .notDetermined:
            "Not Asked"
        @unknown default:
            "Unknown"
        }
    }

    func refreshAuthorizationStatus() async {
        authorizationStatus = await scheduler.authorizationStatus()
        if !authorizationStatus.allowsPulsarNotifications,
           preferences.intelligentNotificationsEnabled {
            update { $0.intelligentNotificationsEnabled = false }
        }
    }

    func setIntelligentNotificationsEnabled(_ enabled: Bool) async {
        guard enabled else {
            update { $0.intelligentNotificationsEnabled = false }
            return
        }

        let currentStatus = await scheduler.authorizationStatus()
        authorizationStatus = currentStatus

        if currentStatus.allowsPulsarNotifications {
            update { $0.intelligentNotificationsEnabled = true }
            return
        }

        guard currentStatus == .notDetermined,
              !permissionStore.hasRequestedIntelligentNotificationPermission else {
            update { $0.intelligentNotificationsEnabled = false }
            return
        }

        permissionStore.markIntelligentNotificationPermissionRequested()
        let granted = await scheduler.requestAuthorization()
        authorizationStatus = await scheduler.authorizationStatus()
        update { $0.intelligentNotificationsEnabled = granted || authorizationStatus.allowsPulsarNotifications }
    }

    func requestPermission() async {
        await setIntelligentNotificationsEnabled(true)
    }

    func update(_ edit: (inout IntelligentNotificationPreferences) -> Void) {
        var copy = preferences
        edit(&copy)
        preferences = copy
        save(copy)
    }

    private func save(_ preferences: IntelligentNotificationPreferences) {
        guard let data = try? encoder.encode(preferences) else { return }
        defaults.set(data, forKey: Key.preferences)
    }
}
