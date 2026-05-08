import SwiftUI
#if os(iOS)
import UIKit
#endif

struct NotificationsSettingsView: View {
    @StateObject private var store: IntelligentNotificationPreferencesStore

    init(store: IntelligentNotificationPreferencesStore? = nil) {
        _store = StateObject(wrappedValue: store ?? .shared)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HelperCard(
                    symbol: "bell.badge.fill",
                    title: "Intelligent Notifications",
                    message: "Pulsar can send concise wellness summaries after meaningful health events. These are not medical alerts or diagnoses.",
                    tint: .red
                )

                permissionCard

                SettingsSectionCard(
                    title: "Insight Alerts",
                    footer: "Pulsar avoids duplicate notifications, applies cooldowns, and uses only available HealthKit and Pulsar summary data."
                ) {
                    ToggleSettingsRow(
                        title: "Intelligent Notifications",
                        subtitle: "Master switch for proactive Pulsar insights",
                        symbol: "sparkles",
                        tint: .red,
                        isOn: Binding(
                            get: { store.preferences.intelligentNotificationsEnabled },
                            set: { enabled in
                                Task { await store.setIntelligentNotificationsEnabled(enabled) }
                            }
                        )
                    )
                    SettingsDivider()
                    ToggleSettingsRow(
                        title: "Post-Workout Summary",
                        subtitle: "Workout complete summaries with strain and recovery context",
                        symbol: "figure.strengthtraining.traditional",
                        tint: .orange,
                        isOn: preferenceBinding(\.postWorkoutSummaryEnabled)
                    )
                    .disabled(!store.preferences.intelligentNotificationsEnabled)
                    SettingsDivider()
                    ToggleSettingsRow(
                        title: "High-Stress Alerts",
                        subtitle: "Cooldown-protected alerts when physiological load appears elevated",
                        symbol: "waveform.path.ecg",
                        tint: .pink,
                        isOn: preferenceBinding(\.highStressAlertsEnabled)
                    )
                    .disabled(!store.preferences.intelligentNotificationsEnabled)
                    SettingsDivider()
                    ToggleSettingsRow(
                        title: "Wind-Down Reminders",
                        subtitle: "A short pre-sleep readiness summary before bedtime",
                        symbol: "moon.zzz.fill",
                        tint: .indigo,
                        isOn: preferenceBinding(\.windDownRemindersEnabled)
                    )
                    .disabled(!store.preferences.intelligentNotificationsEnabled)
                    SettingsDivider()
                    ToggleSettingsRow(
                        title: "Sleep Summary",
                        subtitle: "A morning sleep summary when enough sleep data is available",
                        symbol: "bed.double.fill",
                        tint: .blue,
                        isOn: preferenceBinding(\.sleepSummaryEnabled)
                    )
                    .disabled(!store.preferences.intelligentNotificationsEnabled)
                }

                SettingsSectionCard(title: "Quiet Hours") {
                    SettingsValueRow(
                        title: "Respect Focus / Do Not Disturb",
                        value: "System Managed",
                        subtitle: "Pulsar lets iOS handle Focus and notification delivery rules."
                    )
                    SettingsDivider()
                    SettingsValueRow(
                        title: "Quiet Hours",
                        value: "Coming Soon",
                        subtitle: "A dedicated in-app quiet-hours window is planned."
                    )
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 30)
        }
        .background(PulsarSectionBackground())
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.large)
        .task { await store.refreshAuthorizationStatus() }
    }

    private var permissionCard: some View {
        HStack(alignment: .top, spacing: 14) {
            SettingsIcon(symbol: permissionSymbol, tint: permissionTint)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Permission")
                        .font(.headline)
                    Spacer()
                    HealthStatusBadge(text: store.permissionStatusTitle, tint: permissionTint)
                }

                Text(permissionMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if store.authorizationStatus == .notDetermined {
                    Button("Allow Notifications") {
                        Task { await store.requestPermission() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else if store.authorizationStatus == .denied {
                    Button("Open Settings", action: openSystemSettings)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(16)
        .pulsarLiquidGlass(cornerRadius: 24)
    }

    private var permissionSymbol: String {
        switch store.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            "checkmark.seal.fill"
        case .denied:
            "exclamationmark.triangle.fill"
        case .notDetermined:
            "bell.badge"
        @unknown default:
            "bell"
        }
    }

    private var permissionTint: Color {
        switch store.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            .green
        case .denied:
            .orange
        case .notDetermined:
            .red
        @unknown default:
            .gray
        }
    }

    private var permissionMessage: String {
        switch store.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            "Pulsar can send intelligent wellness summaries when your enabled notification types have something useful to say."
        case .denied:
            "Allow notifications in system Settings to use Pulsar intelligent notifications."
        case .notDetermined:
            "Pulsar will ask once when you enable intelligent notifications."
        @unknown default:
            "Notification permission status is unavailable."
        }
    }

    private func preferenceBinding(_ keyPath: WritableKeyPath<IntelligentNotificationPreferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.preferences[keyPath: keyPath] },
            set: { enabled in
                store.update { $0[keyPath: keyPath] = enabled }
            }
        )
    }

    private func openSystemSettings() {
        #if os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }
}

private struct ToggleSettingsRow: View {
    var title: String
    var subtitle: String
    var symbol: String
    var tint: Color
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            SettingsIcon(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview("Notifications Settings") {
    NavigationStack {
        NotificationsSettingsView()
    }
}
