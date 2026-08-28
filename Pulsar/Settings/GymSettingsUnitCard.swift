//
//  GymSettingsUnitCard.swift
//  Pulsar
//

import SwiftUI

struct GymSettingsUnitCard: View {
    var selection: GymWeightUnitPreference
    var resolvedAppUnit: PulsarWeightUnit
    var select: (GymWeightUnitPreference) -> Void

    private let explicitUnits: [GymWeightUnitPreference] = [.kilograms, .pounds]

    var body: some View {
        VStack(spacing: 0) {
            Button(action: selectFollowApp) {
                GymSettingsFollowAppRow(
                    resolvedUnit: resolvedAppUnit,
                    isSelected: selection == .followApp
                )
                .background {
                    RoundedRectangle(cornerRadius: GymSettingsDesign.rowCornerRadius)
                        .fill(
                            Color.black.opacity(
                                selection == .followApp ? 0.075 : 0
                            )
                        )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(selection == .followApp ? "Selected" : "Not selected")

            Divider()
                .padding(.horizontal, 18)
                .opacity(0.45)

            VStack(spacing: 4) {
                ForEach(explicitUnits) { preference in
                    Button {
                        select(preference)
                    } label: {
                        GymSettingsUnitOptionRow(
                            title: preference.title,
                            isSelected: selection == preference
                        )
                        .background {
                            RoundedRectangle(cornerRadius: GymSettingsDesign.rowCornerRadius)
                                .fill(
                                    Color.black.opacity(
                                        selection == preference ? 0.075 : 0
                                    )
                                )
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(selection == preference ? "Selected" : "Not selected")
                }
            }
            .padding(.vertical, 7)
        }
        .padding(6)
        .gymSettingsCardSurface()
    }

    private func selectFollowApp() {
        select(.followApp)
    }
}
