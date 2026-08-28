import SwiftUI
import UserNotifications

struct SleepPreferencesContent: View {
    @Binding var draft: UserProfile
    var notificationStatus: UNAuthorizationStatus
    var isCheckingAlarmPermission: Bool
    var showPermissionCard: Bool
    var formattedTime: (Int) -> String
    var onEditTime: (SleepTimePickerTarget) -> Void
    var onToggleAlarm: (Bool) -> Void
    var openSettings: () -> Void

    var body: some View {
        PulsarGlassEffectGroup(spacing: 12) {
            VStack(spacing: SleepPreferencesDesign.sectionSpacing) {
                SleepPreferencesHeader()

                SleepScheduleCard(
                    schedule: $draft.sleepSchedule,
                    bedtimeText: formattedTime(draft.sleepSchedule.bedtimeMinutesFromMidnight),
                    wakeText: formattedTime(draft.sleepSchedule.wakeTimeMinutesFromMidnight),
                    onEditBedtime: { onEditTime(.bedtime) },
                    onEditWakeTime: { onEditTime(.wake) }
                )

                SleepGoalDaysCard(selection: $draft.sleepGoalDays)

                if draft.sleepSchedule.alarmEnabled {
                    SleepAlarmStatusCard(
                        schedule: draft.sleepSchedule,
                        sleepGoalDays: draft.sleepGoalDays,
                        alarmTime: formattedTime(draft.sleepSchedule.resolvedAlarmTimeMinutesFromMidnight)
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }

                SleepAlarmSettingsCard(
                    schedule: $draft.sleepSchedule,
                    notificationStatus: notificationStatus,
                    isCheckingPermission: isCheckingAlarmPermission,
                    alarmTime: formattedTime(draft.sleepSchedule.resolvedAlarmTimeMinutesFromMidnight),
                    onToggleAlarm: onToggleAlarm,
                    onEditAlarmTime: { onEditTime(.alarm) }
                )

                if showPermissionCard, notificationStatus == .denied {
                    SleepNotificationPermissionCard(openSettings: openSettings)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, SleepPreferencesDesign.horizontalPadding)
            .padding(.top, 8)
            .padding(.bottom, 36)
        }
    }
}
