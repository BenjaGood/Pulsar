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
                SettingsSectionCard(title: "Data Source", footer: "Pulsar uses HealthKit as the central data layer. Devices are compatible when connected to Apple Health.") {
                    Picker("Current Data Source", selection: $draft.preferredDataSource) {
                        ForEach(PreferredDataSource.allCases) { source in Text(source.rawValue).tag(source) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                Button {
                    isShowingAddDevice = true
                } label: {
                    Label("Add Device", systemImage: "plus.circle.fill")
                        .pulsarTextStyle(.cardTitle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(SettingsMonochromeDesign.primary)
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
                        .pulsarTextStyle(.cardTitle)
                    Text(currentSourceLabel)
                        .pulsarTextStyle(.title)
                    Text("Based on available HealthKit data and your current source setting.")
                        .pulsarTextStyle(.metadata)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HealthStatusBadge(text: healthKitStore.permissionState.title, tint: healthKitStore.permissionState.tint)
            }
        }
        .padding(18)
        .pulsarSettingsCardSurface(cornerRadius: 28)
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

struct HealthPermissionsView: View {
    @ObservedObject var healthKitStore: HealthKitSettingsStore
    var onAuthorizationUpdated: (() -> Void)? = nil

    var body: some View {
        HealthSettingsView(
            healthKitStore: healthKitStore,
            onAuthorizationUpdated: onAuthorizationUpdated
        )
    }
}

struct DataPrivacyView: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject var healthKitStore: HealthKitSettingsStore
    var onReset: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingResetProfile = false
    @State private var isShowingResetSources = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DataPrivacyHeader()
                    .padding(.top, 4)

                PrivacySummaryCard()
                    .padding(.top, 16)

                PrivacySettingsSection(title: "Data Usage") {
                    PrivacySettingsRow(
                        title: "HealthKit",
                        subtitle: "Used for Sleep, Recovery, and Strain insights",
                        symbol: "heart",
                        tint: DataPrivacyDesign.violet,
                        trailingValue: "Read only"
                    )
                    PrivacySettingsDivider()
                    PrivacySettingsRow(
                        title: "Local Profile",
                        subtitle: "Name, preferences, measurements, and baselines",
                        symbol: "person",
                        tint: DataPrivacyDesign.violet,
                        trailingValue: "On device"
                    )
                    PrivacySettingsDivider()
                    PrivacySettingsRow(
                        title: "Medical Claims",
                        subtitle: "Pulsar helps estimate trends and is not diagnostic",
                        symbol: "cross.case",
                        tint: DataPrivacyDesign.violet,
                        trailingValue: "None"
                    )
                }
                .padding(.top, 22)

                PrivacySettingsSection(title: "Data Controls") {
                    Button(action: showResetProfileConfirmation) {
                        PrivacySettingsRow(
                            title: "Reset Local Profile Data",
                            subtitle: "Remove all locally stored profile data",
                            symbol: "trash",
                            tint: .black
                        )
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog(
                        "Reset local profile data?",
                        isPresented: $isShowingResetProfile,
                        titleVisibility: .visible
                    ) {
                        Button("Reset Profile", action: resetLocalProfile)
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("This clears locally saved profile and preference values. It does not delete Apple Health data.")
                    }

                    PrivacySettingsDivider()

                    Button(action: showResetSourcesConfirmation) {
                        PrivacySettingsRow(
                            title: "Reset Device & Source Preferences",
                            subtitle: "Restore default data source settings",
                            symbol: "arrow.counterclockwise",
                            tint: .black
                        )
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog(
                        "Reset source preferences?",
                        isPresented: $isShowingResetSources,
                        titleVisibility: .visible
                    ) {
                        Button("Reset Sources", action: resetSourcePreferences)
                        Button("Cancel", role: .cancel) { }
                    }

                    PrivacySettingsDivider()

                    PrivacySettingsRow(
                        title: "Export / Delete Data",
                        subtitle: "Coming soon",
                        symbol: "square.and.arrow.up",
                        tint: .black,
                        trailingValue: "Coming later",
                        usesStatusCapsule: true
                    )
                    .accessibilityLabel("Export or delete data")
                    .accessibilityValue("Coming later")
                }
                .padding(.top, 22)

                PrivacyFooter()
                    .padding(.top, 16)
            }
            .frame(maxWidth: DataPrivacyDesign.maximumContentWidth)
            .padding(.horizontal, DataPrivacyDesign.horizontalPadding)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .background(DataPrivacyDesign.pageBackground.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", systemImage: "chevron.left", action: dismissDataPrivacy)
                    .profileActionControl(tint: .primary)
            }
        }
        .tint(SettingsMonochromeDesign.primary)
        .preferredColorScheme(.light)
    }

    private func dismissDataPrivacy() {
        dismiss()
    }

    private func showResetProfileConfirmation() {
        isShowingResetProfile = true
    }

    private func showResetSourcesConfirmation() {
        isShowingResetSources = true
    }

    private func resetLocalProfile() {
        store.resetLocalProfile()
        onReset?()
    }

    private func resetSourcePreferences() {
        store.update { profile in
            profile.preferredDataSource = .automatic
            profile.primarySleepSource = .automatic
        }
        healthKitStore.resetPermissionIntroduction()
        onReset?()
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
            SettingsIcon(symbol: "checkmark.seal.fill", tint: .black)
            VStack(alignment: .leading, spacing: 3) {
                Text(source.name)
                    .pulsarTextStyle(.bodyEmphasis)
                Text(source.detail)
                    .pulsarTextStyle(.metadata)
                    .foregroundStyle(.secondary)
            }
            Spacer()
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
                    HelperCard(symbol: "heart.text.square.fill", title: "Add Through Apple Health", message: "Pulsar reads compatible devices through Apple Health / HealthKit. Connect your device or app to Apple Health first, then grant Pulsar access.", tint: .black)
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
            .background(PulsarSettingsBackground())
            .navigationTitle("Add Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .tint(SettingsMonochromeDesign.primary)
            .preferredColorScheme(.light)
        }
    }
}

#Preview("Devices") { NavigationStack { DevicesView(store: SettingsPreviewStore.make(), healthKitStore: HealthKitSettingsStore()) } }
#Preview("Health Permissions") { NavigationStack { HealthPermissionsView(healthKitStore: HealthKitSettingsStore()) } }
#Preview("Data Privacy") {
    NavigationStack {
        DataPrivacyView(
            store: SettingsPreviewStore.make(),
            healthKitStore: HealthKitSettingsStore()
        )
    }
    .id("data-privacy-compact")
}
