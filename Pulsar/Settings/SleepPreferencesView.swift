import SwiftUI
import UserNotifications

struct SleepPreferencesView: View {
    @ObservedObject var store: ProfileStore
    var onSave: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
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
        alarmScheduler: AlarmScheduler? = nil,
        calendar: Calendar = .current
    ) {
        self.store = store
        self.onSave = onSave
        self.alarmScheduler = alarmScheduler ?? .shared
        self.calendar = calendar
        _draft = State(initialValue: store.profile)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            SleepPreferencesContent(
                draft: $draft,
                notificationStatus: notificationStatus,
                isCheckingAlarmPermission: isCheckingAlarmPermission,
                showPermissionCard: showPermissionCard,
                formattedTime: { minutes in formattedTime(minutes) },
                onEditTime: { activePicker = $0 },
                onToggleAlarm: { isEnabled in handleAlarmToggle(isEnabled) },
                openSettings: { openAppSettings() }
            )
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(PulsarSettingsBackground())
        .navigationBarBackButtonHidden()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", systemImage: "chevron.left", action: dismissSleepSettings)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass(.clear))
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .tint(.primary)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(action: save) {
                    Text("Save")
                        .bold()
                        .foregroundStyle(
                            hasChanges
                                ? SettingsMonochromeDesign.primary
                                : SettingsMonochromeDesign.disabled
                        )
                        .animation(.easeInOut(duration: 0.2), value: hasChanges)
                }
                .buttonStyle(SettingsOutlineButtonStyle())
                .controlSize(.large)
                .disabled(!hasChanges)
            }
        }
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.34),
            value: draft.sleepSchedule.alarmEnabled
        )
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.34),
            value: showPermissionCard
        )
        .task {
            await refreshNotificationStatus()
        }
        .sheet(item: $activePicker) { target in
            SleepTimePickerSheet(
                title: target.title,
                selection: timeBinding(for: target),
                showsWakeTimeReset: target == .alarm && !draft.sleepSchedule.alarmUsesWakeTime,
                resetToWakeTime: { resetAlarmToWakeTime() },
                done: { activePicker = nil }
            )
            .presentationDetents([.height(360)])
        }
        .tint(SettingsMonochromeDesign.primary)
        .toggleStyle(SettingsMonochromeToggleStyle())
        .preferredColorScheme(.light)
    }

    private var hasChanges: Bool {
        draft != store.profile
    }

    private func dismissSleepSettings() {
        dismiss()
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

    private func resetAlarmToWakeTime() {
        draft.sleepSchedule.resetAlarmToWakeTime()
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
        calendar.date(
            from: DateComponents(
                hour: minutesFromMidnight / 60,
                minute: minutesFromMidnight % 60
            )
        ) ?? .now
    }

    private func minutes(from date: Date) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func formattedTime(_ minutesFromMidnight: Int) -> String {
        date(for: minutesFromMidnight).formatted(date: .omitted, time: .shortened)
    }
}

enum SleepTimePickerTarget: String, Identifiable {
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

struct SleepTimePickerSheet: View {
    var title: String
    @Binding var selection: Date
    var showsWakeTimeReset: Bool
    var resetToWakeTime: () -> Void
    var done: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                DatePicker(title, selection: $selection, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()

                if showsWakeTimeReset {
                    Button("Use Wake Time", action: resetToWakeTime)
                        .buttonStyle(.bordered)
                        .tint(SettingsMonochromeDesign.primary)
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: done)
                        .bold()
                }
            }
        }
        .tint(SettingsMonochromeDesign.primary)
        .preferredColorScheme(.light)
    }
}

#Preview("Sleep Preferences Light") {
    NavigationStack {
        SleepPreferencesView(store: SettingsPreviewStore.make())
    }
}
