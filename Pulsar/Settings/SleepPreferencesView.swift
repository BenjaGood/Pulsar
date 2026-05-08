import SwiftUI
import UIKit
import UserNotifications

struct SleepPreferencesView: View {
    @ObservedObject var store: ProfileStore
    var onSave: (() -> Void)? = nil

    @State private var draft: UserProfile
    @State private var activePicker: SleepTimePickerTarget?
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isCheckingAlarmPermission = false
    @State private var showPermissionCard = false

    private let alarmScheduler: AlarmScheduler
    private let calendar: Calendar

    init(
        store: ProfileStore,
        onSave: (() -> Void)? = nil,
        alarmScheduler: AlarmScheduler = .shared,
        calendar: Calendar = .current
    ) {
        self.store = store
        self.onSave = onSave
        self.alarmScheduler = alarmScheduler
        self.calendar = calendar
        _draft = State(initialValue: store.profile)
    }

    var body: some View {
        SettingsDetailScaffold(title: "Sleep", hasChanges: draft != store.profile, save: save) {
            VStack(spacing: 20) {
                SleepPersonalizationHeaderCard()

                SleepPreferenceSection(title: "Sleep Schedule") {
                    VStack(spacing: 18) {
                        HStack(spacing: 10) {
                            SleepScheduleSummaryPill(title: "Bedtime", value: formattedTime(draft.sleepSchedule.bedtimeMinutesFromMidnight), tint: .indigo)
                            SleepScheduleSummaryPill(title: "Wake", value: formattedTime(draft.sleepSchedule.wakeTimeMinutesFromMidnight), tint: .cyan)
                        }

                        SleepScheduleDialView(schedule: $draft.sleepSchedule)
                            .frame(maxWidth: 420)

                        Text("Drag the handles for a fast adjustment, or tap the rows below for exact times.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 10)

                        VStack(spacing: 0) {
                            SleepActionRow(
                                title: "Bedtime",
                                value: formattedTime(draft.sleepSchedule.bedtimeMinutesFromMidnight),
                                subtitle: "Used for sleep consistency and recovery context"
                            ) {
                                activePicker = .bedtime
                            }
                            Divider()
                                .padding(.leading, 16)
                            SleepActionRow(
                                title: "Wake Time",
                                value: formattedTime(draft.sleepSchedule.wakeTimeMinutesFromMidnight),
                                subtitle: draft.sleepSchedule.alarmUsesWakeTime ? "Linked to your sleep alarm" : "Used for sleep performance and wake context"
                            ) {
                                activePicker = .wake
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(.white.opacity(0.06))
                        )
                    }
                }

                SleepPreferenceSection(title: "Sleep Goal Days", footer: "Custom day selection is coming soon.") {
                    HStack(spacing: 10) {
                        SleepGoalDayChip(title: "Every day", isSelected: draft.sleepGoalDays == .everyDay, isDisabled: false) {
                            draft.sleepGoalDays = .everyDay
                        }
                        SleepGoalDayChip(title: "Weekdays", isSelected: draft.sleepGoalDays == .weekdays, isDisabled: false) {
                            draft.sleepGoalDays = .weekdays
                        }
                        SleepGoalDayChip(title: "Custom", isSelected: draft.sleepGoalDays == .custom, isDisabled: true, badge: "Soon") { }
                    }
                }

                if draft.sleepSchedule.alarmEnabled {
                    AlarmStatusCard(schedule: draft.sleepSchedule, sleepGoalDays: draft.sleepGoalDays, formattedTime: formattedTime)
                }

                AlarmSettingsCard(
                    schedule: $draft.sleepSchedule,
                    sleepGoalDays: draft.sleepGoalDays,
                    notificationStatus: notificationStatus,
                    isCheckingPermission: isCheckingAlarmPermission,
                    formattedTime: formattedTime,
                    onToggleAlarm: handleAlarmToggle(_:),
                    onEditAlarmTime: { activePicker = .alarm }
                )

                if showPermissionCard, notificationStatus == .denied {
                    NotificationPermissionCard(openSettings: openAppSettings)
                }
            }
        }
        .task {
            await refreshNotificationStatus()
        }
        .sheet(item: $activePicker) { target in
            SleepTimePickerSheet(
                title: target.title,
                selection: timeBinding(for: target),
                done: { activePicker = nil }
            )
            .presentationDetents([.height(330)])
        }
    }

    private func save() {
        store.save(draft)
        draft = store.profile
        onSave?()
    }

    private func refreshNotificationStatus() async {
        let status = await alarmScheduler.authorizationStatus()
        notificationStatus = status
        showPermissionCard = status == .denied && store.profile.sleepSchedule.alarmEnabled
    }

    private func handleAlarmToggle(_ isEnabled: Bool) {
        if !isEnabled {
            draft.sleepSchedule.setAlarmEnabled(false)
            return
        }

        isCheckingAlarmPermission = true
        Task {
            let result = await alarmScheduler.prepareForAlarmEnable()
            await MainActor.run {
                isCheckingAlarmPermission = false
                notificationStatus = result.status
                if result.granted {
                    draft.sleepSchedule.setAlarmEnabled(true)
                    showPermissionCard = false
                } else {
                    draft.sleepSchedule.setAlarmEnabled(false)
                    showPermissionCard = result.status == .denied
                }
            }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func timeBinding(for target: SleepTimePickerTarget) -> Binding<Date> {
        Binding(
            get: {
                let minutes: Int
                switch target {
                case .bedtime:
                    minutes = draft.sleepSchedule.bedtimeMinutesFromMidnight
                case .wake:
                    minutes = draft.sleepSchedule.wakeTimeMinutesFromMidnight
                case .alarm:
                    minutes = draft.sleepSchedule.resolvedAlarmTimeMinutesFromMidnight
                }
                return date(for: minutes)
            },
            set: { date in
                let minutes = minutes(from: date)
                switch target {
                case .bedtime:
                    draft.sleepSchedule.setBedtimeMinutes(minutes)
                case .wake:
                    draft.sleepSchedule.setWakeTimeMinutes(minutes)
                case .alarm:
                    draft.sleepSchedule.setAlarmTimeMinutes(minutes)
                }
            }
        )
    }

    private func date(for minutesFromMidnight: Int) -> Date {
        calendar.date(from: DateComponents(hour: minutesFromMidnight / 60, minute: minutesFromMidnight % 60)) ?? Date()
    }

    private func minutes(from date: Date) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func formattedTime(_ minutesFromMidnight: Int) -> String {
        let date = date(for: minutesFromMidnight)
        return date.formatted(date: .omitted, time: .shortened)
    }
}

private enum SleepTimePickerTarget: String, Identifiable {
    case bedtime
    case wake
    case alarm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bedtime: "Bedtime"
        case .wake: "Wake Time"
        case .alarm: "Alarm Time"
        }
    }
}

private struct SleepPersonalizationHeaderCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            SettingsIcon(symbol: "moon.zzz.fill", tint: .indigo)
            VStack(alignment: .leading, spacing: 5) {
                Text("Sleep Personalization")
                    .font(.title3.weight(.semibold))
                Text("Used for sleep consistency, sleep performance, and recovery insights.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .pulsarLiquidGlass(cornerRadius: 30)
    }
}

private struct SleepPreferenceSection<Content: View>: View {
    var title: String
    var footer: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pulsarLiquidGlass(cornerRadius: 30)

            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            }
        }
    }
}

private struct SleepScheduleSummaryPill: View {
    var title: String
    var value: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tint.opacity(0.12))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        }
    }
}

private struct SleepActionRow: View {
    var title: String
    var value: String
    var subtitle: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Text(value)
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }
}

private struct SleepGoalDayChip: View {
    var title: String
    var isSelected: Bool
    var isDisabled: Bool
    var badge: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.10), in: Capsule())
                }
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(LinearGradient(colors: [Color.indigo, Color.cyan], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(.white.opacity(isDisabled ? 0.05 : 0.08)))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isSelected ? .white.opacity(0.18) : .white.opacity(0.10), lineWidth: 1)
            }
            .opacity(isDisabled ? 0.65 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

private struct AlarmStatusCard: View {
    var schedule: SleepSchedule
    var sleepGoalDays: SleepGoalDays
    var formattedTime: (Int) -> String

    var body: some View {
        SleepPreferenceSection(title: "Alarm Active") {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Alarm On")
                            .font(.title3.weight(.semibold))
                        Text(formattedTime(schedule.resolvedAlarmTimeMinutesFromMidnight))
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    Spacer(minLength: 10)
                    Image(systemName: "alarm.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .frame(width: 48, height: 48)
                        .background(.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                HStack(spacing: 10) {
                    AlarmDetailPill(title: "Sound", value: schedule.alarmSoundName)
                    AlarmDetailPill(title: "Haptics", value: schedule.alarmHapticsEnabled ? "On" : "Off")
                    AlarmDetailPill(title: "Days", value: sleepGoalDays.rawValue)
                }
            }
        }
    }
}

private struct AlarmDetailPill: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct AlarmSettingsCard: View {
    @Binding var schedule: SleepSchedule
    var sleepGoalDays: SleepGoalDays
    var notificationStatus: UNAuthorizationStatus
    var isCheckingPermission: Bool
    var formattedTime: (Int) -> String
    var onToggleAlarm: (Bool) -> Void
    var onEditAlarmTime: () -> Void

    var body: some View {
        SleepPreferenceSection(
            title: "Alarm",
            footer: notificationStatus == .denied ? "Allow notifications to use Pulsar alarms." : nil
        ) {
            VStack(spacing: 0) {
                toggleRow(
                    title: "Sleep Alarm",
                    subtitle: "A minimal wellness wake reminder for iPhone and Apple Watch"
                )
                Divider()
                    .padding(.leading, 16)
                SleepActionRow(
                    title: "Alarm Time",
                    value: formattedTime(schedule.resolvedAlarmTimeMinutesFromMidnight),
                    subtitle: schedule.alarmUsesWakeTime ? "Matches your wake time until you customize it" : "Custom alarm time"
                ) {
                    guard schedule.alarmEnabled else { return }
                    onEditAlarmTime()
                }
                .opacity(schedule.alarmEnabled ? 1 : 0.55)
                if schedule.alarmEnabled, !schedule.alarmUsesWakeTime {
                    HStack {
                        Button("Match Wake Time") {
                            schedule.resetAlarmToWakeTime()
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.cyan)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                Divider()
                    .padding(.leading, 16)
                SettingsValueRow(title: "Sound", value: schedule.alarmSoundName, subtitle: "More sound choices coming soon")
                Divider()
                    .padding(.leading, 16)
                toggleRow(
                    title: "Haptics",
                    subtitle: "Saved with your alarm profile for synced watch display",
                    binding: Binding(
                        get: { schedule.alarmHapticsEnabled },
                        set: { schedule.alarmHapticsEnabled = $0 }
                    ),
                    isEnabled: schedule.alarmEnabled
                )
                Divider()
                    .padding(.leading, 16)
                toggleRow(
                    title: "Snooze",
                    subtitle: "Keep a gentle backup reminder available",
                    binding: Binding(
                        get: { schedule.snoozeEnabled },
                        set: { schedule.snoozeEnabled = $0 }
                    ),
                    isEnabled: schedule.alarmEnabled
                )
                Divider()
                    .padding(.leading, 16)
                smartWakeRow
            }
        }
    }

    private func toggleRow(
        title: String,
        subtitle: String,
        binding: Binding<Bool>? = nil,
        isEnabled: Bool = true
    ) -> some View {
        let resolvedBinding = binding ?? Binding(
            get: { schedule.alarmEnabled },
            set: { onToggleAlarm($0) }
        )

        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if isCheckingPermission && title == "Sleep Alarm" {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 4)
            }
            Toggle("", isOn: resolvedBinding)
                .labelsHidden()
                .disabled(!isEnabled || isCheckingPermission)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .opacity(isEnabled ? 1 : 0.6)
    }

    private var smartWakeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Wake Window")
                        .font(.body.weight(.medium))
                    Text("Pulsar will use sleep data to help wake you at a better moment.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 10)
                Text("Coming soon")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.10), in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .opacity(schedule.alarmEnabled ? 1 : 0.65)
    }
}

private struct NotificationPermissionCard: View {
    var openSettings: () -> Void

    var body: some View {
        SleepPreferenceSection(title: "Permission Needed") {
            VStack(alignment: .leading, spacing: 12) {
                Label("Allow notifications to use Pulsar alarms.", systemImage: "bell.badge.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Pulsar only asks when you turn the alarm on. You can enable notifications in Settings whenever you’re ready.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Settings", action: openSettings)
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
            }
        }
    }
}

private struct SleepTimePickerSheet: View {
    var title: String
    @Binding var selection: Date
    var done: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DatePicker(title, selection: $selection, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .padding(.top, 16)
                Spacer()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: done)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview("Sleep Preferences Light") {
    NavigationStack {
        SleepPreferencesView(store: SettingsPreviewStore.make())
    }
}

#Preview("Sleep Preferences Dark") {
    NavigationStack {
        SleepPreferencesView(store: SettingsPreviewStore.make())
    }
    .preferredColorScheme(.dark)
}

#Preview("Alarm Active Card") {
    AlarmStatusCard(
        schedule: SleepSchedule(
            bedtimeMinutesFromMidnight: 22 * 60 + 30,
            wakeTimeMinutesFromMidnight: 6 * 60 + 30,
            alarmEnabled: true,
            alarmUsesWakeTime: true
        ),
        sleepGoalDays: .everyDay,
        formattedTime: { minutes in
            let date = Calendar.current.date(from: DateComponents(hour: minutes / 60, minute: minutes % 60)) ?? Date()
            return date.formatted(date: .omitted, time: .shortened)
        }
    )
    .padding()
    .background(PulsarSectionBackground())
}

private struct AlarmSettingsCardPreviewContainer: View {
    @State var schedule = SleepSchedule(
        bedtimeMinutesFromMidnight: 22 * 60 + 30,
        wakeTimeMinutesFromMidnight: 6 * 60 + 30,
        alarmEnabled: false,
        alarmUsesWakeTime: true
    )

    var body: some View {
        AlarmSettingsCard(
            schedule: $schedule,
            sleepGoalDays: .everyDay,
            notificationStatus: .authorized,
            isCheckingPermission: false,
            formattedTime: { minutes in
                let date = Calendar.current.date(from: DateComponents(hour: minutes / 60, minute: minutes % 60)) ?? Date()
                return date.formatted(date: .omitted, time: .shortened)
            },
            onToggleAlarm: { _ in },
            onEditAlarmTime: { }
        )
        .padding()
        .background(PulsarSectionBackground())
    }
}

#Preview("Alarm Disabled Card") {
    AlarmSettingsCardPreviewContainer()
}
