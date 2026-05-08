//
//  ProfileSettingsDetailViews.swift
//  Pulsar
//

import SwiftUI

struct ProfileDetailsView: View {
    @ObservedObject var store: ProfileStore
    var onSave: (() -> Void)? = nil

    @State private var draft: UserProfile
    private let calendar = Calendar.current

    init(store: ProfileStore, onSave: (() -> Void)? = nil) {
        self.store = store
        self.onSave = onSave
        _draft = State(initialValue: store.profile)
    }

    var body: some View {
        SettingsDetailScaffold(title: "Profile", hasChanges: hasChanges, save: save) {
            VStack(spacing: 18) {
                VStack(spacing: 12) {
                    AvatarView(profile: draft, size: 92)
                        .padding(6)
                        .pulsarLiquidGlass(cornerRadius: 58)
                    Button("Edit Photo") { }
                        .buttonStyle(.bordered)
                        .disabled(true)
                }
                .frame(maxWidth: .infinity)

                SettingsSectionCard(title: "Personal Details", footer: "These details help Pulsar personalize estimates. Pulsar is not a diagnostic medical device.") {
                    VStack(spacing: 0) {
                        TextField("Display Name", text: $draft.name)
                            .textInputAutocapitalization(.words)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                        SettingsDivider()
                        DatePicker("Date of Birth", selection: dateOfBirthBinding, displayedComponents: .date)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        SettingsDivider()
                        SettingsValueRow(title: "Derived Age", value: ageText, subtitle: "Calculated from date of birth")
                        SettingsDivider()
                        Picker("Biological Sex", selection: $draft.biologicalSex) {
                            ForEach(BiologicalSex.allCases) { sex in Text(sex.rawValue).tag(sex) }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
            }
        }
    }

    private var hasChanges: Bool { draft != store.profile }

    private var dateOfBirthBinding: Binding<Date> {
        Binding(get: { draft.dateOfBirth ?? draft.healthKitDateOfBirth ?? defaultDateOfBirth }, set: { draft.dateOfBirth = $0 })
    }

    private var defaultDateOfBirth: Date {
        calendar.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    }

    private var ageText: String {
        guard let age = draft.age(calendar: calendar) else { return "Not set" }
        return "\(age) years"
    }

    private func save() {
        store.save(draft)
        draft = store.profile
        onSave?()
    }
}

struct MeasurementsView: View {
    @ObservedObject var store: ProfileStore
    var onSave: (() -> Void)? = nil

    @State private var draft: UserProfile

    init(store: ProfileStore, onSave: (() -> Void)? = nil) {
        self.store = store
        self.onSave = onSave
        _draft = State(initialValue: store.profile)
    }

    var body: some View {
        SettingsDetailScaffold(title: "Measurements", hasChanges: hasChanges, save: save) {
            VStack(spacing: 18) {
                HelperCard(symbol: "ruler", title: "Body Metrics", message: "Height and weight help normalize strain estimates and future HealthKit body metrics.", tint: .green)

                SettingsSectionCard(title: "Body") {
                    VStack(spacing: 0) {
                        Stepper(value: heightBinding, in: 100...230, step: 1) {
                            SettingsValueRow(title: "Height", value: formattedHeight(heightBinding.wrappedValue), subtitle: "Stored internally in centimeters")
                        }
                        SettingsDivider()
                        Stepper(value: weightBinding, in: 35...220, step: 0.5) {
                            SettingsValueRow(title: "Weight", value: formattedWeight(weightBinding.wrappedValue), subtitle: "Stored internally in kilograms")
                        }
                        SettingsDivider()
                        Picker("Preferred Units", selection: $draft.preferredUnits) {
                            Text(UnitPreference.metric.rawValue).tag(UnitPreference.metric)
                            Text(UnitPreference.imperial.rawValue).tag(UnitPreference.imperial)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }

                SettingsSectionCard(title: "Sources") {
                    Picker("Body Mass Source", selection: $draft.bodyMassSource) {
                        ForEach(ProfileValueSource.allCases) { source in Text(source.rawValue).tag(source) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    SettingsDivider()
                    Picker("Height Source", selection: $draft.heightSource) {
                        ForEach(ProfileValueSource.allCases) { source in Text(source.rawValue).tag(source) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    SettingsDivider()
                    SettingsValueRow(title: "Last Updated", value: formattedDate(draft.lastUpdated), subtitle: "Updated when measurements are saved")
                }

                if let bmiText {
                    HelperCard(symbol: "scalemass.fill", title: "BMI", message: "\(bmiText). BMI is a simple body-size indicator and is not a complete health assessment.", tint: .teal)
                }
            }
        }
    }

    private var hasChanges: Bool { draft != store.profile }
    private var heightBinding: Binding<Double> { Binding(get: { draft.heightCentimeters ?? draft.healthKitHeightCentimeters ?? 175 }, set: { draft.heightCentimeters = $0 }) }
    private var weightBinding: Binding<Double> { Binding(get: { draft.weightKilograms ?? draft.healthKitWeightKilograms ?? 72 }, set: { draft.weightKilograms = $0 }) }
    private var bmiText: String? {
        guard let height = draft.resolvedHeightCentimeters, let weight = draft.resolvedWeightKilograms, height > 0 else { return nil }
        return String(format: "%.1f", weight / pow(height / 100, 2))
    }

    private func save() { store.save(draft); draft = store.profile; onSave?() }
    private func formattedDate(_ date: Date?) -> String { date?.formatted(date: .abbreviated, time: .shortened) ?? "Not saved yet" }
    private func formattedHeight(_ centimeters: Double) -> String {
        if draft.preferredUnits == .imperial {
            let inches = Int((centimeters / 2.54).rounded())
            return "\(inches / 12) ft \(inches % 12) in"
        }
        return "\(Int(centimeters.rounded())) cm"
    }
    private func formattedWeight(_ kilograms: Double) -> String {
        draft.preferredUnits == .imperial ? "\(Int((kilograms * 2.20462).rounded())) lb" : String(format: "%.1f kg", kilograms)
    }
}

struct PerformanceSettingsView: View {
    @ObservedObject var store: ProfileStore
    var onSave: (() -> Void)? = nil

    @State private var draft: UserProfile
    private let calendar = Calendar.current

    init(store: ProfileStore, onSave: (() -> Void)? = nil) {
        self.store = store
        self.onSave = onSave
        _draft = State(initialValue: store.profile)
    }

    var body: some View {
        SettingsDetailScaffold(title: "Performance", hasChanges: draft != store.profile, save: save) {
            VStack(spacing: 18) {
                HelperCard(symbol: "speedometer", title: "Training Context", message: "These values help Pulsar estimate heart-rate zones, strain, and recovery based on available data.", tint: .orange)
                SettingsSectionCard(title: "Heart Metrics") {
                    Stepper(value: maxHeartRateBinding, in: 120...230, step: 1) {
                        SettingsValueRow(title: "Max Heart Rate", value: "\(Int(maxHeartRateBinding.wrappedValue.rounded())) bpm", subtitle: maxHeartRateHelper)
                    }
                    SettingsDivider()
                    Stepper(value: restingHeartRateBinding, in: 35...90, step: 1) {
                        SettingsValueRow(title: "Resting HR Baseline", value: "\(Int(restingHeartRateBinding.wrappedValue.rounded())) bpm")
                    }
                    SettingsDivider()
                    Stepper(value: hrvBinding, in: 10...180, step: 1) {
                        SettingsValueRow(title: "HRV Baseline", value: "\(Int(hrvBinding.wrappedValue.rounded())) ms", subtitle: "SDNN baseline")
                    }
                }
                SettingsSectionCard(title: "Training") {
                    Picker("Training Level", selection: $draft.trainingLevel) {
                        ForEach(TrainingLevel.allCases) { level in Text(level.rawValue).tag(level) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    SettingsDivider()
                    Picker("Heart Rate Zone Method", selection: $draft.heartRateZoneMethod) {
                        ForEach(HeartRateZoneMethod.allCases) { method in Text(method.rawValue).tag(method) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private var maxHeartRateBinding: Binding<Double> { Binding(get: { draft.manualMaxHeartRate ?? draft.resolvedMaxHeartRate(calendar: calendar)?.value ?? 180 }, set: { draft.manualMaxHeartRate = $0 }) }
    private var restingHeartRateBinding: Binding<Double> { Binding(get: { draft.restingHeartRateBaselineBPM ?? 55 }, set: { draft.restingHeartRateBaselineBPM = $0 }) }
    private var hrvBinding: Binding<Double> { Binding(get: { draft.hrvBaselineMilliseconds ?? 50 }, set: { draft.hrvBaselineMilliseconds = $0 }) }
    private var maxHeartRateHelper: String { draft.manualMaxHeartRate == nil ? "Estimated until saved manually" : "Manual override" }
    private func save() { store.save(draft); draft = store.profile; onSave?() }
}

struct SettingsDetailScaffold<Content: View>: View {
    var title: String
    var hasChanges: Bool
    var save: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 30)
        }
        .background(PulsarSectionBackground())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save", action: save)
                    .fontWeight(.semibold)
                    .disabled(!hasChanges)
            }
        }
    }
}

#Preview("Profile Details") { NavigationStack { ProfileDetailsView(store: SettingsPreviewStore.make()) } }
#Preview("Measurements") { NavigationStack { MeasurementsView(store: SettingsPreviewStore.make()) } }
#Preview("Performance") { NavigationStack { PerformanceSettingsView(store: SettingsPreviewStore.make()) } }
