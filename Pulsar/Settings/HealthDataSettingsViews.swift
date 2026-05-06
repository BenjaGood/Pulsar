//
//  HealthDataSettingsViews.swift
//  Pulsar
//

import SwiftUI

struct DevicesView: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject var healthKitStore: HealthKitSettingsStore
    var onSave: (() -> Void)? = nil

    @State private var draft: UserProfile
    @State private var isShowingAddDevice = false

    init(store: ProfileStore, healthKitStore: HealthKitSettingsStore, onSave: (() -> Void)? = nil) {
        self.store = store
        self.healthKitStore = healthKitStore
        self.onSave = onSave
        _draft = State(initialValue: store.profile)
    }

    var body: some View {
        SettingsDetailScaffold(title: "Devices", hasChanges: draft != store.profile, save: save) {
            VStack(spacing: 18) {
                currentSourceCard
                SettingsSectionCard(title: "Preferred Source", footer: "Pulsar uses HealthKit as the central data layer. Devices are compatible when connected to Apple Health.") {
                    Picker("Preferred Data Source", selection: $draft.preferredDataSource) {
                        ForEach(PreferredDataSource.allCases) { source in Text(source.rawValue).tag(source) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                Button {
                    isShowingAddDevice = true
                } label: {
                    Label("Add Device", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                SettingsSectionCard(title: "Compatible Through Apple Health") {
                    ForEach(Array(compatibleSources.enumerated()), id: \.element.name) { index, source in
                        DeviceSourceRow(source: source)
                        if index < compatibleSources.count - 1 { SettingsDivider() }
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingAddDevice) {
            AddDeviceExplanationView()
                .presentationDetents([.medium, .large])
        }
    }

    private var currentSourceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                SettingsIcon(symbol: "heart.text.square.fill", tint: healthKitStore.permissionState.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Source")
                        .font(.headline)
                    Text(currentSourceLabel)
                        .font(.title2.weight(.semibold))
                    Text("Based on available HealthKit data and your preferred source setting.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HealthStatusBadge(text: healthKitStore.permissionState.title, tint: healthKitStore.permissionState.tint)
            }
        }
        .padding(18)
        .pulsarLiquidGlass(cornerRadius: 28)
    }

    private var currentSourceLabel: String {
        draft.preferredDataSource == .automatic ? "HealthKit Auto" : draft.preferredDataSource.rawValue
    }

    private var compatibleSources: [CompatibleSource] {
        [
            CompatibleSource(name: "Apple Watch", detail: "Workouts, heart rate, sleep, activity"),
            CompatibleSource(name: "iPhone Motion & Fitness", detail: "Steps and movement when available"),
            CompatibleSource(name: "Garmin", detail: "Compatible when connected to Apple Health"),
            CompatibleSource(name: "Oura Ring", detail: "Compatible when connected to Apple Health"),
            CompatibleSource(name: "WHOOP", detail: "Compatible when connected to Apple Health"),
            CompatibleSource(name: "Fitbit", detail: "Compatible through supported Apple Health integrations"),
            CompatibleSource(name: "Polar", detail: "Compatible when connected to Apple Health"),
            CompatibleSource(name: "Wahoo", detail: "Compatible when connected to Apple Health"),
            CompatibleSource(name: "Withings", detail: "Compatible when connected to Apple Health"),
            CompatibleSource(name: "Other Health Apps", detail: "Any app that writes compatible samples to HealthKit")
        ]
    }

    private func save() {
        store.save(draft)
        draft = store.profile
        onSave?()
    }
}

struct DataSourcesView: View {
    @ObservedObject var healthKitStore: HealthKitSettingsStore

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HelperCard(symbol: "list.bullet.rectangle", title: "HealthKit Sample Types", message: "Pulsar reads these data types when you grant access. Availability depends on your device and connected Apple Health sources.", tint: .teal)
                SettingsSectionCard(title: "Expected Data") {
                    ForEach(Array(healthKitStore.dataSources.enumerated()), id: \.element.id) { index, item in
                        HealthDataSourceRow(item: item)
                        if index < healthKitStore.dataSources.count - 1 { SettingsDivider() }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 30)
        }
        .background(PulsarSectionBackground())
        .navigationTitle("Data Sources")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { healthKitStore.refreshStatus() }
    }
}

struct HealthPermissionsView: View {
    @ObservedObject var healthKitStore: HealthKitSettingsStore
    @State private var isRequesting = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        SettingsIcon(symbol: "heart.text.square.fill", tint: healthKitStore.permissionState.tint)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Apple Health")
                                .font(.headline)
                            Text(healthKitStore.permissionState.title)
                                .font(.title2.weight(.semibold))
                        }
                        Spacer()
                        HealthStatusBadge(text: healthKitStore.permissionState.title, tint: healthKitStore.permissionState.tint)
                    }
                    Text("Pulsar reads compatible HealthKit data to estimate Sleep, Recovery, and Strain. You stay in control of what Apple Health shares.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        Task {
                            isRequesting = true
                            await healthKitStore.requestAuthorization()
                            isRequesting = false
                        }
                    } label: {
                        Label(isRequesting ? "Requesting..." : "Connect Apple Health", systemImage: "heart.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRequesting || healthKitStore.permissionState == .notAvailable)
                }
                .padding(18)
                .pulsarLiquidGlass(cornerRadius: 28)

                if let message = healthKitStore.lastErrorMessage {
                    HelperCard(symbol: "exclamationmark.triangle.fill", title: "Permission Note", message: message, tint: .orange)
                }

                HelperCard(symbol: "gearshape.fill", title: "Review Later", message: "To change access later, open the Health app, go to Sharing, then Apps and Services, and choose Pulsar.", tint: .gray)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 30)
        }
        .background(PulsarSectionBackground())
        .navigationTitle("Health Permissions")
        .navigationBarTitleDisplayMode(.large)
    }
}

struct DataPrivacyView: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject var healthKitStore: HealthKitSettingsStore
    var onReset: (() -> Void)? = nil

    @State private var isShowingResetProfile = false
    @State private var isShowingResetSources = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HelperCard(symbol: "lock.shield.fill", title: "Your Data", message: "Pulsar uses Apple Health as the central health data source. Local profile values are stored on this device for now.", tint: .gray)
                SettingsSectionCard(title: "Usage") {
                    SettingsValueRow(title: "HealthKit", value: "Read only", subtitle: "Used for Sleep, Recovery, and Strain insights")
                    SettingsDivider()
                    SettingsValueRow(title: "Local Profile", value: "On device", subtitle: "Name, preferences, measurements, and baselines")
                    SettingsDivider()
                    SettingsValueRow(title: "Medical Claims", value: "None", subtitle: "Pulsar helps estimate trends and is not diagnostic")
                }
                SettingsSectionCard(title: "Reset") {
                    Button(role: .destructive) { isShowingResetProfile = true } label: {
                        Label("Reset Local Profile Data", systemImage: "trash")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                    SettingsDivider()
                    Button(role: .destructive) { isShowingResetSources = true } label: {
                        Label("Reset Device & Source Preferences", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                    SettingsDivider()
                    SettingsValueRow(title: "Export / Delete Data", value: "Coming later", subtitle: "Placeholder for a full account data flow")
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 30)
        }
        .background(PulsarSectionBackground())
        .navigationTitle("Data & Privacy")
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog("Reset local profile data?", isPresented: $isShowingResetProfile, titleVisibility: .visible) {
            Button("Reset Profile", role: .destructive) {
                store.resetLocalProfile()
                onReset?()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This clears locally saved profile and preference values. It does not delete Apple Health data.")
        }
        .confirmationDialog("Reset source preferences?", isPresented: $isShowingResetSources, titleVisibility: .visible) {
            Button("Reset Sources", role: .destructive) {
                store.update { profile in
                    profile.preferredDataSource = .automatic
                    profile.primarySleepSource = .automatic
                }
                healthKitStore.resetPermissionIntroduction()
                onReset?()
            }
            Button("Cancel", role: .cancel) { }
        }
    }
}

private struct CompatibleSource: Hashable {
    var name: String
    var detail: String
}

private struct DeviceSourceRow: View {
    var source: CompatibleSource

    var body: some View {
        HStack(spacing: 14) {
            SettingsIcon(symbol: "checkmark.seal.fill", tint: .blue)
            VStack(alignment: .leading, spacing: 3) {
                Text(source.name)
                    .font(.body.weight(.medium))
                Text(source.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct HealthDataSourceRow: View {
    var item: HealthDataSourceItem

    var body: some View {
        HStack(spacing: 14) {
            SettingsIcon(symbol: item.symbol, tint: item.status.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.body.weight(.medium))
                Text(item.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 10)
            HealthStatusBadge(text: item.status.rawValue, tint: item.status.tint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct AddDeviceExplanationView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    HelperCard(symbol: "heart.text.square.fill", title: "Add Through Apple Health", message: "Pulsar reads compatible devices through Apple Health / HealthKit. Connect your device or app to Apple Health first, then grant Pulsar access.", tint: .pink)
                    SettingsSectionCard(title: "How It Works") {
                        SettingsValueRow(title: "1. Connect Device", value: "Apple Health", subtitle: "Use the device maker's app to share data with Health")
                        SettingsDivider()
                        SettingsValueRow(title: "2. Share Data", value: "HealthKit", subtitle: "Workouts, heart rate, sleep, steps, or body metrics")
                        SettingsDivider()
                        SettingsValueRow(title: "3. Pulsar Reads", value: "Compatible data", subtitle: "Pulsar does not directly pair Bluetooth devices yet")
                    }
                }
                .padding(18)
            }
            .background(PulsarSectionBackground())
            .navigationTitle("Add Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

#Preview("Devices") { NavigationStack { DevicesView(store: SettingsPreviewStore.make(), healthKitStore: HealthKitSettingsStore()) } }
#Preview("Data Sources") { NavigationStack { DataSourcesView(healthKitStore: HealthKitSettingsStore()) } }
#Preview("Health Permissions") { NavigationStack { HealthPermissionsView(healthKitStore: HealthKitSettingsStore()) } }
#Preview("Data Privacy") { NavigationStack { DataPrivacyView(store: SettingsPreviewStore.make(), healthKitStore: HealthKitSettingsStore()) } }
