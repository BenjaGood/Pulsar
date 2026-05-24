import Foundation

enum IntelligentNotificationCategory: String, CaseIterable {
    case postWorkout = "pulsar.notification.postWorkout"
    case highStress = "pulsar.notification.highStress"
    case windDown = "pulsar.notification.windDown"
    case sleepSummary = "pulsar.notification.sleepSummary"
    case dailyRewind = "pulsar.notification.dailyRewind"
}

struct IntelligentNotificationPreferences: Codable, Equatable {
    var intelligentNotificationsEnabled: Bool
    var postWorkoutSummaryEnabled: Bool
    var highStressAlertsEnabled: Bool
    var windDownRemindersEnabled: Bool
    var sleepSummaryEnabled: Bool
    var dailyRewindRemindersEnabled: Bool
    var respectQuietHoursPlaceholder: Bool

    static let `default` = IntelligentNotificationPreferences(
        intelligentNotificationsEnabled: false,
        postWorkoutSummaryEnabled: true,
        highStressAlertsEnabled: true,
        windDownRemindersEnabled: true,
        sleepSummaryEnabled: true,
        dailyRewindRemindersEnabled: true,
        respectQuietHoursPlaceholder: true
    )

    init(
        intelligentNotificationsEnabled: Bool,
        postWorkoutSummaryEnabled: Bool,
        highStressAlertsEnabled: Bool,
        windDownRemindersEnabled: Bool,
        sleepSummaryEnabled: Bool,
        dailyRewindRemindersEnabled: Bool,
        respectQuietHoursPlaceholder: Bool
    ) {
        self.intelligentNotificationsEnabled = intelligentNotificationsEnabled
        self.postWorkoutSummaryEnabled = postWorkoutSummaryEnabled
        self.highStressAlertsEnabled = highStressAlertsEnabled
        self.windDownRemindersEnabled = windDownRemindersEnabled
        self.sleepSummaryEnabled = sleepSummaryEnabled
        self.dailyRewindRemindersEnabled = dailyRewindRemindersEnabled
        self.respectQuietHoursPlaceholder = respectQuietHoursPlaceholder
    }

    private enum CodingKeys: String, CodingKey {
        case intelligentNotificationsEnabled
        case postWorkoutSummaryEnabled
        case highStressAlertsEnabled
        case windDownRemindersEnabled
        case sleepSummaryEnabled
        case dailyRewindRemindersEnabled
        case respectQuietHoursPlaceholder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        intelligentNotificationsEnabled = try container.decode(Bool.self, forKey: .intelligentNotificationsEnabled)
        postWorkoutSummaryEnabled = try container.decode(Bool.self, forKey: .postWorkoutSummaryEnabled)
        highStressAlertsEnabled = try container.decode(Bool.self, forKey: .highStressAlertsEnabled)
        windDownRemindersEnabled = try container.decode(Bool.self, forKey: .windDownRemindersEnabled)
        sleepSummaryEnabled = try container.decode(Bool.self, forKey: .sleepSummaryEnabled)
        dailyRewindRemindersEnabled = try container.decodeIfPresent(Bool.self, forKey: .dailyRewindRemindersEnabled) ?? true
        respectQuietHoursPlaceholder = try container.decode(Bool.self, forKey: .respectQuietHoursPlaceholder)
    }
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
