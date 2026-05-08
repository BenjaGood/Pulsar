import Foundation

enum IntelligentNotificationCategory: String, CaseIterable {
    case postWorkout = "pulsar.notification.postWorkout"
    case highStress = "pulsar.notification.highStress"
    case windDown = "pulsar.notification.windDown"
    case sleepSummary = "pulsar.notification.sleepSummary"
}

struct IntelligentNotificationPreferences: Codable, Equatable {
    var intelligentNotificationsEnabled: Bool
    var postWorkoutSummaryEnabled: Bool
    var highStressAlertsEnabled: Bool
    var windDownRemindersEnabled: Bool
    var sleepSummaryEnabled: Bool
    var respectQuietHoursPlaceholder: Bool

    static let `default` = IntelligentNotificationPreferences(
        intelligentNotificationsEnabled: false,
        postWorkoutSummaryEnabled: true,
        highStressAlertsEnabled: true,
        windDownRemindersEnabled: true,
        sleepSummaryEnabled: true,
        respectQuietHoursPlaceholder: true
    )
}

struct WorkoutNotificationEvent: Identifiable, Equatable {
    var id: String
    var workoutType: String
    var startDate: Date
    var endDate: Date
    var activeEnergyKilocalories: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var sourceName: String

    var durationMinutes: Double {
        max(0, endDate.timeIntervalSince(startDate) / 60)
    }
}

struct PulsarNotificationPayload: Equatable {
    var identifier: String
    var category: IntelligentNotificationCategory
    var title: String
    var body: String
    var deliveryDate: Date?

    static func immediate(
        identifier: String,
        category: IntelligentNotificationCategory,
        title: String,
        body: String
    ) -> PulsarNotificationPayload {
        PulsarNotificationPayload(
            identifier: identifier,
            category: category,
            title: title,
            body: body,
            deliveryDate: nil
        )
    }
}
