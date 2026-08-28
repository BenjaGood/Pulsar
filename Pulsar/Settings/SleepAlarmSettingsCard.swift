import SwiftUI
import UserNotifications

struct SleepAlarmSettingsCard: View {
    @Binding var schedule: SleepSchedule
    var notificationStatus: UNAuthorizationStatus
    var isCheckingPermission: Bool
    var alarmTime: String
    var onToggleAlarm: (Bool) -> Void
    var onEditAlarmTime: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ALARM")
                .sleepSectionLabel()
                .padding(.leading, 4)

            VStack(spacing: 0) {
                SleepAlarmToggleRow(
                    symbol: "bell.fill",
                    tint: .black,
                    title: "Sleep Alarm",
                    description: "A minimal wellness wake reminder",
                    isOn: Binding(
                        get: { schedule.alarmEnabled },
                        set: onToggleAlarm
                    ),
                    isEnabled: true,
                    isBusy: isCheckingPermission
                )

                SleepAlarmRowDivider()

                SleepAlarmValueRow(
                    symbol: "clock.fill",
                    tint: .black,
                    title: "Alarm Time",
                    description: schedule.alarmUsesWakeTime
                        ? "Linked to your sleep schedule"
                        : "Custom alarm time",
                    value: alarmTime,
                    isEnabled: schedule.alarmEnabled,
                    action: onEditAlarmTime
                )

                SleepAlarmRowDivider()

                SleepAlarmValueRow(
                    symbol: "waveform",
                    tint: .black,
                    title: "Sound",
                    description: "Select your alarm sound",
                    value: schedule.alarmSoundName
                )

                SleepAlarmRowDivider()

                SleepAlarmToggleRow(
                    symbol: "waveform.path",
                    tint: .black,
                    title: "Haptics",
                    description: "Silent vibration",
                    isOn: Binding(
                        get: { schedule.alarmHapticsEnabled },
                        set: { schedule.alarmHapticsEnabled = $0 }
                    ),
                    isEnabled: schedule.alarmEnabled
                )

                SleepAlarmRowDivider()

                SleepAlarmToggleRow(
                    symbol: "alarm.waves.left.and.right.fill",
                    tint: .black,
                    title: "Snooze",
                    description: "9 min snooze",
                    isOn: Binding(
                        get: { schedule.snoozeEnabled },
                        set: { schedule.snoozeEnabled = $0 }
                    ),
                    isEnabled: schedule.alarmEnabled
                )
            }
            .sleepPreferencesCardSurface()

            if notificationStatus == .denied {
                Text("Allow notifications to use Pulsar alarms.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
            }
        }
    }
}

struct SleepAlarmToggleRow: View {
    var symbol: String
    var tint: Color
    var title: String
    var description: String
    @Binding var isOn: Bool
    var isEnabled: Bool
    var isBusy: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            SleepAlarmRowIcon(symbol: symbol, tint: tint)

            SleepAlarmRowLabel(title: title, description: description)

            Spacer(minLength: 10)

            if isBusy {
                ProgressView()
                    .controlSize(.small)
            }

            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .accessibilityLabel(title)
                .accessibilityValue(isOn ? "On" : "Off")
                .disabled(!isEnabled || isBusy)
        }
        .padding(.horizontal, SleepPreferencesDesign.rowHorizontalPadding)
        .padding(.vertical, SleepPreferencesDesign.rowVerticalPadding)
        .opacity(isEnabled ? 1 : 0.55)
        .animation(.easeInOut(duration: 0.2), value: isEnabled)
    }
}

struct SleepAlarmValueRow: View {
    var symbol: String
    var tint: Color
    var title: String
    var description: String
    var value: String
    var isEnabled: Bool = true
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    rowContent(showsDisclosure: true)
                }
                .buttonStyle(SleepSettingsPressButtonStyle())
                .disabled(!isEnabled)
            } else {
                rowContent(showsDisclosure: false)
            }
        }
        .padding(.horizontal, SleepPreferencesDesign.rowHorizontalPadding)
        .padding(.vertical, SleepPreferencesDesign.rowVerticalPadding)
        .opacity(isEnabled ? 1 : 0.55)
    }

    private func rowContent(showsDisclosure: Bool) -> some View {
        HStack(spacing: 14) {
            SleepAlarmRowIcon(symbol: symbol, tint: tint)

            SleepAlarmRowLabel(title: title, description: description)

            Spacer(minLength: 10)

            Text(value)
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .bold()
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(.rect)
    }
}

struct SleepAlarmRowLabel: View {
    var title: String
    var description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.body)
                .bold()
                .foregroundStyle(.primary)

            Text(description)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SleepAlarmRowIcon: View {
    var symbol: String
    var tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.body)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(SettingsMonochromeDesign.primary)
            .frame(
                width: SleepPreferencesDesign.iconSize,
                height: SleepPreferencesDesign.iconSize
            )
            .accessibilityHidden(true)
    }
}

struct SleepAlarmRowDivider: View {
    var body: some View {
        Divider()
            .opacity(0.55)
            .padding(.leading, SleepPreferencesDesign.rowHorizontalPadding + SleepPreferencesDesign.iconSize + 14)
    }
}

struct SleepNotificationPermissionCard: View {
    var openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Permission Needed", systemImage: "bell.badge.fill")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("Allow notifications in Settings to use the sleep alarm on iPhone and Apple Watch.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Open Settings", action: openSettings)
                .buttonStyle(.borderedProminent)
                .tint(SettingsMonochromeDesign.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SleepPreferencesDesign.cardPadding)
        .sleepPreferencesCardSurface()
    }
}

#Preview("Sleep Alarm Settings") {
    @Previewable @State var schedule = SleepSchedule(
        bedtimeMinutesFromMidnight: 23 * 60,
        wakeTimeMinutesFromMidnight: 7 * 60 + 20,
        alarmEnabled: true,
        alarmTimeMinutesFromMidnight: 3 * 60 + 25,
        alarmUsesWakeTime: false
    )

    SleepAlarmSettingsCard(
        schedule: $schedule,
        notificationStatus: .authorized,
        isCheckingPermission: false,
        alarmTime: "03:25",
        onToggleAlarm: { schedule.setAlarmEnabled($0) },
        onEditAlarmTime: { }
    )
    .padding()
    .background(PulsarSettingsBackground())
}
