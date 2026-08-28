//
//  GymSettingsView.swift
//  Pulsar
//

import SwiftUI

struct GymSettingsView: View {
    @ObservedObject var gymSettingsStore: GymSettingsStore
    var appUnits: UnitPreference

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GymSettingsDesign.sectionSpacing) {
                GymSettingsHeader()

                PulsarGlassEffectGroup(spacing: GymSettingsDesign.sectionSpacing) {
                    VStack(alignment: .leading, spacing: GymSettingsDesign.sectionSpacing) {
                        GymSettingsInfoCard()

                        VStack(alignment: .leading, spacing: 10) {
                            Text("WEIGHTS")
                                .font(.footnote)
                                .bold()
                                .tracking(1.1)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 4)
                                .accessibilityAddTraits(.isHeader)

                            GymSettingsUnitCard(
                                selection: gymSettingsStore.weightUnitPreference,
                                resolvedAppUnit: GymWeightUnitPreference.followApp.resolvedUnit(appUnits: appUnits),
                                select: selectUnit
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: GymSettingsDesign.maximumContentWidth)
            .padding(.horizontal, GymSettingsDesign.horizontalPadding)
            .padding(.top, 24)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .background(PulsarSettingsBackground())
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                HealthSettingsBackButton(action: dismissGymSettings)
                Spacer()
            }
            .padding(.horizontal, GymSettingsDesign.horizontalPadding)
            .padding(.top, 8)
        }
        .navigationBarBackButtonHidden()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .tint(SettingsMonochromeDesign.primary)
        .preferredColorScheme(.light)
    }

    private func selectUnit(_ preference: GymWeightUnitPreference) {
        guard preference != gymSettingsStore.weightUnitPreference else { return }

        withAnimation(GymSettingsDesign.selectionAnimation(reduceMotion: reduceMotion)) {
            gymSettingsStore.setWeightUnitPreference(preference)
        }
    }

    private func dismissGymSettings() {
        dismiss()
    }
}

#Preview("Gym Settings — Follow App") {
    NavigationStack {
        GymSettingsView(
            gymSettingsStore: makeGymSettingsPreviewStore(.followApp),
            appUnits: .metric
        )
    }
}

#Preview("Gym Settings — Pounds") {
    NavigationStack {
        GymSettingsView(
            gymSettingsStore: makeGymSettingsPreviewStore(.pounds),
            appUnits: .metric
        )
    }
}

@MainActor
private func makeGymSettingsPreviewStore(
    _ preference: GymWeightUnitPreference
) -> GymSettingsStore {
    let suiteName = "pulsar.gym-settings.preview.\(preference.rawValue)"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    defaults.removeObject(forKey: "pulsar.gym.weightUnitPreference.v1")

    let store = GymSettingsStore(defaults: defaults)
    store.setWeightUnitPreference(preference)
    return store
}
