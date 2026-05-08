import Foundation
import UserNotifications

struct AlarmPermissionResult: Equatable {
    var granted: Bool
    var status: UNAuthorizationStatus
}

@MainActor
final class AlarmScheduler {
    static let shared = AlarmScheduler()

    private let center: UNUserNotificationCenter
    private let permissionStore: NotificationPermissionStore

    init(
        center: UNUserNotificationCenter = .current(),
        permissionStore: NotificationPermissionStore = .shared
    ) {
        self.center = center
        self.permissionStore = permissionStore
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { (continuation: CheckedContinuation<UNAuthorizationStatus, Never>) in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    func prepareForAlarmEnable() async -> AlarmPermissionResult {
        let status = await authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return AlarmPermissionResult(granted: true, status: status)
        case .notDetermined:
            permissionStore.markSleepAlarmPermissionRequested()
            let granted = await requestAuthorization()
            let resolvedStatus = await authorizationStatus()
            return AlarmPermissionResult(granted: granted || resolvedStatus.isAlarmAuthorized, status: resolvedStatus)
        case .denied:
            return AlarmPermissionResult(granted: false, status: .denied)
        @unknown default:
            return AlarmPermissionResult(granted: false, status: status)
        }
    }

    func sync(with profile: UserProfile) async {
        guard profile.sleepSchedule.alarmEnabled else {
            await cancelSleepAlarms()
            return
        }

        let status = await authorizationStatus()
        guard status.isAlarmAuthorized else {
            await cancelSleepAlarms()
            return
        }

        let scheduledDays = Self.scheduledDays(for: profile.sleepGoalDays)
        guard !scheduledDays.isEmpty else {
            await cancelSleepAlarms()
            return
        }

        await cancelSleepAlarms()
        for day in scheduledDays {
            let request = makeRequest(
                identifier: day.identifier,
                weekday: day.rawValue,
                schedule: profile.sleepSchedule
            )
            try? await add(request)
        }
    }

    func cancelSleepAlarms() async {
        let identifiers = Self.allScheduledDays.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func requestAuthorization() async -> Bool {
        do {
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        } catch {
            return false
        }
    }

    private func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func makeRequest(identifier: String, weekday: Int, schedule: SleepSchedule) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Wake up"
        content.body = "Your Pulsar sleep alarm is ready."
        content.sound = schedule.alarmSoundName == "Silent" ? nil : .default
        content.threadIdentifier = "pulsar.sleepAlarm"

        var components = DateComponents()
        components.weekday = weekday
        components.hour = schedule.resolvedAlarmTimeMinutesFromMidnight / 60
        components.minute = schedule.resolvedAlarmTimeMinutesFromMidnight % 60

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    private static func scheduledDays(for goalDays: SleepGoalDays) -> [ScheduledDay] {
        switch goalDays {
        case .everyDay:
            allScheduledDays
        case .weekdays:
            [.monday, .tuesday, .wednesday, .thursday, .friday]
        case .custom:
            []
        }
    }

    private static let allScheduledDays: [ScheduledDay] = [
        .sunday,
        .monday,
        .tuesday,
        .wednesday,
        .thursday,
        .friday,
        .saturday
    ]
}

private enum ScheduledDay: Int {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    var identifier: String {
        switch self {
        case .sunday: "pulsar.sleepAlarm.sunday"
        case .monday: "pulsar.sleepAlarm.monday"
        case .tuesday: "pulsar.sleepAlarm.tuesday"
        case .wednesday: "pulsar.sleepAlarm.wednesday"
        case .thursday: "pulsar.sleepAlarm.thursday"
        case .friday: "pulsar.sleepAlarm.friday"
        case .saturday: "pulsar.sleepAlarm.saturday"
        }
    }
}

private extension UNAuthorizationStatus {
    var isAlarmAuthorized: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            true
        case .notDetermined, .denied:
            false
        @unknown default:
            false
        }
    }
}
