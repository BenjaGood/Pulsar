import Foundation
import UserNotifications

@MainActor
protocol IntelligentNotificationScheduling: AnyObject {
    func registerCategories()
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

@MainActor
final class UserNotificationIntelligentScheduler: IntelligentNotificationScheduling {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func registerCategories() {
        let categories = Set(
            IntelligentNotificationCategory.allCases.map {
                UNNotificationCategory(
                    identifier: $0.rawValue,
                    actions: [],
                    intentIdentifiers: [],
                    options: []
                )
            }
        )
        center.setNotificationCategories(categories)
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { (continuation: CheckedContinuation<UNAuthorizationStatus, Never>) in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    func requestAuthorization() async -> Bool {
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

    func add(_ request: UNNotificationRequest) async throws {
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

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

extension UNAuthorizationStatus {
    var allowsPulsarNotifications: Bool {
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
