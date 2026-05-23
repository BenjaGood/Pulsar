//
//  PulsarSettingsView.swift
//  Pulsar
//

import SwiftUI

struct PulsarSettingsView: View {
    @ObservedObject var store: ProfileStore
    var onProfileUpdated: (() -> Void)? = nil
    var onHealthAuthorizationUpdated: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @StateObject private var healthKitStore = HealthKitSettingsStore()
    @StateObject private var gymSettingsStore = GymSettingsStore()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    NavigationLink { ProfileDetailsView(store: store, onSave: onProfileUpdated) } label: {
                        ProfileSummaryCard(profile: store.profile)
                    }
                    .buttonStyle(.plain)

                    SettingsSectionCard(title: "Personal") {
                        NavigationLink { ProfileDetailsView(store: store, onSave: onProfileUpdated) } label: {
                            SettingsNavigationRow(title: "Profile", subtitle: "Name, birthday, and biological sex", symbol: "person.crop.circle", tint: .blue)
                        }
                        SettingsDivider()
                        NavigationLink { MeasurementsView(store: store, onSave: onProfileUpdated) } label: {
                            SettingsNavigationRow(title: "Measurements", subtitle: "Height, weight, units, and sources", symbol: "ruler", tint: .green, badge: store.profile.preferredUnits.rawValue)
                        }
                        SettingsDivider()
                        NavigationLink { PerformanceSettingsView(store: store, onSave: onProfileUpdated) } label: {
                            SettingsNavigationRow(title: "Performance Settings", subtitle: "Heart-rate zones, HRV, and training level", symbol: "speedometer", tint: .orange)
                        }
                        SettingsDivider()
                        NavigationLink { SleepPreferencesView(store: store, onSave: onProfileUpdated) } label: {
                            SettingsNavigationRow(title: "Sleep Preferences", subtitle: "Sleep schedule, goal days, and alarm", symbol: "moon.zzz.fill", tint: .indigo)
                        }
                    }

                    SettingsSectionCard(title: "Devices & Data") {
                        NavigationLink { DevicesView(store: store, healthKitStore: healthKitStore, onSave: onProfileUpdated) } label: {
                            SettingsNavigationRow(title: "Devices", subtitle: "Compatible sources through Apple Health", symbol: "applewatch", tint: .purple, badge: healthKitStore.permissionState.title)
                        }
                        SettingsDivider()
                        NavigationLink { DataSourcesView(healthKitStore: healthKitStore) } label: {
                            SettingsNavigationRow(title: "Data Sources", subtitle: "HealthKit sample types Pulsar can read", symbol: "list.bullet.rectangle", tint: .teal)
                        }
                        SettingsDivider()
                        NavigationLink { HealthPermissionsView(healthKitStore: healthKitStore, onAuthorizationUpdated: onHealthAuthorizationUpdated) } label: {
                            SettingsNavigationRow(title: "Health Permissions", subtitle: "Connect Pulsar to Apple Health", symbol: "heart.text.square.fill", tint: .pink, badge: healthKitStore.permissionState.title)
                        }
                        SettingsDivider()
                        NavigationLink { DataPrivacyView(store: store, healthKitStore: healthKitStore, onReset: onProfileUpdated) } label: {
                            SettingsNavigationRow(title: "Data & Privacy", subtitle: "Local storage, HealthKit usage, and reset controls", symbol: "lock.shield.fill", tint: .gray)
                        }
                    }

                    SettingsSectionCard(title: "App") {
                        SettingsNavigationRow(title: "Appearance", subtitle: "Follows your system appearance", symbol: "circle.lefthalf.filled", tint: .cyan, badge: "Auto")
                        SettingsDivider()
                        NavigationLink { NotificationsSettingsView() } label: {
                            SettingsNavigationRow(title: "Notifications", subtitle: "Workout, stress, wind-down, and sleep insights", symbol: "bell.badge.fill", tint: .red)
                        }
                        SettingsDivider()
                        NavigationLink { GymSettingsView(gymSettingsStore: gymSettingsStore, appUnits: store.profile.preferredUnits) } label: {
                            SettingsNavigationRow(
                                title: "Gym Weight Unit",
                                subtitle: "Use pounds or kilograms for lifting, independent from your app units.",
                                symbol: "dumbbell.fill",
                                tint: .purple,
                                badge: gymSettingsStore.weightUnitPreference.shortTitle
                            )
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Units", subtitle: "Managed in Measurements", symbol: "slider.horizontal.3", tint: .mint, badge: store.profile.preferredUnits.rawValue)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
            .background(PulsarSectionBackground())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct GymSettingsView: View {
    @ObservedObject var gymSettingsStore: GymSettingsStore
    var appUnits: UnitPreference

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HelperCard(
                    symbol: "dumbbell.fill",
                    title: "Lifting Units",
                    message: "Gym weights can use pounds or kilograms without changing body weight, distance, or other app measurements.",
                    tint: .purple
                )

                SettingsSectionCard(title: "Weights") {
                    VStack(spacing: 0) {
                        ForEach(GymWeightUnitPreference.allCases) { preference in
                            Button {
                                gymSettingsStore.setWeightUnitPreference(preference)
                            } label: {
                                HStack(spacing: 14) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(preference.title)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(.primary)
                                        if preference == .followApp {
                                            Text("Currently resolves to \(preference.resolvedUnit(appUnits: appUnits).displayName)")
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer(minLength: 12)

                                    if gymSettingsStore.weightUnitPreference == preference {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.headline.weight(.semibold))
                                            .foregroundStyle(.purple)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 13)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if preference != GymWeightUnitPreference.allCases.last {
                                SettingsDivider()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 30)
        }
        .background(PulsarSectionBackground())
        .navigationTitle("Gym")
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct ProfileSummaryCard: View {
    var profile: UserProfile

    var body: some View {
        HStack(spacing: 16) {
            AvatarView(profile: profile, size: 64)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("Personal details for better insights")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Pulsar Profile")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .pulsarLiquidGlass(cornerRadius: 30)
    }

    private var displayName: String {
        let trimmed = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Set up your profile" : trimmed
    }
}

#Preview("Settings") {
    PulsarSettingsView(store: SettingsPreviewStore.make())
}

@MainActor
enum SettingsPreviewStore {
    static func make() -> ProfileStore {
        let defaults = UserDefaults(suiteName: "pulsar.settings.preview") ?? .standard
        defaults.removeObject(forKey: "pulsar.profile.v1")
        let store = ProfileStore(defaults: defaults, sideEffectsEnabled: false)
        var profile = MockHealthData.profile
        profile.restingHeartRateBaselineBPM = 52
        profile.hrvBaselineMilliseconds = 58
        profile.trainingLevel = .advanced
        profile.bodyMassSource = .manual
        profile.heightSource = .healthKit
        profile.primarySleepSource = .appleWatch
        profile.preferredDataSource = .appleWatch
        store.save(profile)
        return store
    }
}
