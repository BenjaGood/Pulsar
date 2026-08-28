//
//  PulsarSettingsView.swift
//  Pulsar
//

import SwiftUI

struct PulsarSettingsView: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject var backgroundSettingsStore: HomeBackgroundSettingsStore
    var onProfileUpdated: (() -> Void)? = nil
    var onHealthAuthorizationUpdated: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @StateObject private var healthKitStore = HealthKitSettingsStore()
    @StateObject private var gymSettingsStore = GymSettingsStore()

    init(
        store: ProfileStore,
        backgroundSettingsStore: HomeBackgroundSettingsStore = HomeBackgroundSettingsStore(),
        onProfileUpdated: (() -> Void)? = nil,
        onHealthAuthorizationUpdated: (() -> Void)? = nil
    ) {
        self.store = store
        self.backgroundSettingsStore = backgroundSettingsStore
        self.onProfileUpdated = onProfileUpdated
        self.onHealthAuthorizationUpdated = onHealthAuthorizationUpdated
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                PulsarGlassEffectGroup(spacing: 18) {
                    VStack(alignment: .leading, spacing: 24) {
                        NavigationLink {
                            ProfileDetailsView(store: store, onSave: onProfileUpdated)
                        } label: {
                            SettingsProfileCard(profile: store.profile)
                        }
                        .buttonStyle(.plain)

                        SettingsSectionCard(title: "Personal") {
                            NavigationLink {
                                ProfileDetailsView(store: store, onSave: onProfileUpdated)
                            } label: {
                                SettingsNavigationRow(
                                    title: "Profile",
                                    subtitle: "Personal information",
                                    symbol: "person.fill",
                                    tint: .black
                                )
                            }
                            SettingsDivider()
                            NavigationLink {
                                MeasurementsView(store: store, onSave: onProfileUpdated)
                            } label: {
                                SettingsNavigationRow(
                                    title: "Measurements",
                                    subtitle: "Height, weight, units",
                                    symbol: "ruler",
                                    tint: .black,
                                    badge: store.profile.preferredUnits.rawValue
                                )
                            }
                            SettingsDivider()
                            NavigationLink {
                                PerformanceSettingsView(store: store, onSave: onProfileUpdated)
                            } label: {
                                SettingsNavigationRow(
                                    title: "Performance",
                                    subtitle: "Heart rate, HRV, training",
                                    symbol: "waveform.path.ecg",
                                    tint: .black
                                )
                            }
                            SettingsDivider()
                            NavigationLink {
                                SleepPreferencesView(store: store, onSave: onProfileUpdated)
                            } label: {
                                SettingsNavigationRow(
                                    title: "Sleep",
                                    subtitle: "Schedule, goal, and alarm",
                                    symbol: "moon.zzz.fill",
                                    tint: .black
                                )
                            }
                        }

                        SettingsSectionCard(title: "Devices & Data") {
                            NavigationLink {
                                HealthSettingsView(
                                    healthKitStore: healthKitStore,
                                    onAuthorizationUpdated: onHealthAuthorizationUpdated
                                )
                            } label: {
                                SettingsNavigationRow(
                                    title: "Health",
                                    subtitle: "Apple Health integration",
                                    symbol: "heart",
                                    tint: .black,
                                    status: connectionStatus
                                )
                            }
                            SettingsDivider()
                            NavigationLink {
                                DataPrivacyView(
                                    store: store,
                                    healthKitStore: healthKitStore,
                                    onReset: onProfileUpdated
                                )
                            } label: {
                                SettingsNavigationRow(
                                    title: "Data & Privacy",
                                    subtitle: "Storage, permissions, reset",
                                    symbol: "lock.fill",
                                    tint: .black
                                )
                            }
                            SettingsDivider()
                            NavigationLink {
                                HealthPermissionsView(
                                    healthKitStore: healthKitStore,
                                    onAuthorizationUpdated: onHealthAuthorizationUpdated
                                )
                            } label: {
                                SettingsNavigationRow(
                                    title: "Permissions",
                                    subtitle: "Manage health permissions",
                                    symbol: "shield.lefthalf.filled",
                                    tint: .black
                                )
                            }
                        }

                        SettingsSectionCard(title: "App") {
                            NavigationLink {
                                HomeBackgroundSettingsView(store: backgroundSettingsStore)
                            } label: {
                                SettingsNavigationRow(
                                    title: "Appearance",
                                    subtitle: "Home background and theme",
                                    symbol: "photo.on.rectangle.angled",
                                    tint: .black,
                                    badge: backgroundSettingsStore.mode.shortTitle
                                )
                            }
                            SettingsDivider()
                            NavigationLink {
                                NotificationsSettingsView()
                            } label: {
                                SettingsNavigationRow(
                                    title: "Notifications",
                                    subtitle: "Workouts, stress, sleep, and more",
                                    symbol: "bell",
                                    tint: .black
                                )
                            }
                            SettingsDivider()
                            NavigationLink {
                                GymSettingsView(
                                    gymSettingsStore: gymSettingsStore,
                                    appUnits: store.profile.preferredUnits
                                )
                            } label: {
                                SettingsNavigationRow(
                                    title: "Gym Unit",
                                    subtitle: "Weight unit for lifting",
                                    symbol: "dumbbell.fill",
                                    tint: .black,
                                    badge: gymUnitTitle
                                )
                            }
                            SettingsDivider()
                            NavigationLink {
                                MeasurementsView(store: store, onSave: onProfileUpdated)
                            } label: {
                                SettingsNavigationRow(
                                    title: "Units",
                                    subtitle: "App and measurement units",
                                    symbol: "scalemass.fill",
                                    tint: .black,
                                    badge: store.profile.preferredUnits.rawValue
                                )
                            }
                            SettingsDivider()
                            NavigationLink {
                                FoodDataSourcesView()
                            } label: {
                                SettingsNavigationRow(
                                    title: "Food Data Sources",
                                    subtitle: "Attribution and database licenses",
                                    symbol: "books.vertical.fill",
                                    tint: .black
                                )
                            }
                        }

                        PulsarSettingsFooter()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 22)
            }
            .scrollIndicators(.hidden)
            .background(PulsarSettingsBackground())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: dismissSettings) {
                        Text("Done")
                            .bold()
                            .foregroundStyle(SettingsMonochromeDesign.primary)
                    }
                    .buttonStyle(SettingsOutlineButtonStyle())
                }
            }
        }
        .tint(SettingsMonochromeDesign.primary)
        .toggleStyle(SettingsMonochromeToggleStyle())
        .preferredColorScheme(.light)
    }

    private var gymUnitTitle: String {
        gymSettingsStore
            .resolvedWeightUnit(appUnits: store.profile.preferredUnits)
            .displayName
    }

    private var connectionStatus: String? {
        healthKitStore.permissionState == .connected ? "Connected" : nil
    }

    private func dismissSettings() {
        dismiss()
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
