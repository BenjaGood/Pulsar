import Foundation

struct PulsarSleepPreferencesSyncPayload: nonisolated Codable, Equatable, Sendable {
    var syncedAt: Date
    var bedtimeMinutesFromMidnight: Int
    var wakeTimeMinutesFromMidnight: Int
    var targetSleepDurationMinutes: Int
    var sleepGoalDaysLabel: String
    var alarmEnabled: Bool
    var alarmTimeMinutesFromMidnight: Int
    var alarmUsesWakeTime: Bool
    var alarmSoundName: String
    var alarmHapticsEnabled: Bool
    var snoozeEnabled: Bool
    var smartWakeEnabled: Bool
    var wakeWindowMinutes: Int?

    var resolvedAlarmTimeMinutesFromMidnight: Int {
        alarmUsesWakeTime ? wakeTimeMinutesFromMidnight : alarmTimeMinutesFromMidnight
    }

    var isValid: Bool {
        (0..<24 * 60).contains(bedtimeMinutesFromMidnight) &&
        (0..<24 * 60).contains(wakeTimeMinutesFromMidnight) &&
        (0..<24 * 60).contains(alarmTimeMinutesFromMidnight) &&
        targetSleepDurationMinutes >= 0 &&
        targetSleepDurationMinutes <= 24 * 60 &&
        !sleepGoalDaysLabel.isEmpty &&
        !alarmSoundName.isEmpty &&
        syncedAt.timeIntervalSinceReferenceDate.isFinite
    }
}

#if os(iOS)
extension PulsarSleepPreferencesSyncPayload {
    init(profile: UserProfile) {
        let schedule = profile.sleepSchedule
        self.init(
            syncedAt: profile.lastUpdated ?? Date(),
            bedtimeMinutesFromMidnight: schedule.bedtimeMinutesFromMidnight,
            wakeTimeMinutesFromMidnight: schedule.wakeTimeMinutesFromMidnight,
            targetSleepDurationMinutes: schedule.targetSleepDurationMinutes,
            sleepGoalDaysLabel: profile.sleepGoalDays.rawValue,
            alarmEnabled: schedule.alarmEnabled,
            alarmTimeMinutesFromMidnight: schedule.resolvedAlarmTimeMinutesFromMidnight,
            alarmUsesWakeTime: schedule.alarmUsesWakeTime,
            alarmSoundName: schedule.alarmSoundName,
            alarmHapticsEnabled: schedule.alarmHapticsEnabled,
            snoozeEnabled: schedule.snoozeEnabled,
            smartWakeEnabled: schedule.smartWakeEnabled,
            wakeWindowMinutes: schedule.wakeWindowMinutes
        )
    }
}
#endif
