//
//  MeasurementUnitSelector.swift
//  Pulsar
//

import SwiftUI

struct MeasurementUnitSelector: View {
    @Binding var selection: UnitPreference

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace

    private let choices: [UnitPreference] = [.metric, .imperial]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(choices) { unit in
                Button(unit.rawValue) {
                    select(unit)
                }
                .font(.subheadline.bold())
                .foregroundStyle(selection == unit ? Color.white : SettingsMonochromeDesign.primary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background {
                    if selection == unit {
                        Capsule()
                            .fill(SettingsMonochromeDesign.selectedFill)
                            .matchedGeometryEffect(id: "selected-unit", in: selectionNamespace)
                    }
                }
                .contentShape(Capsule())
                .accessibilityValue(selection == unit ? "Selected" : "Not selected")
            }
        }
        .padding(3)
        .background(SettingsMonochromeDesign.surface, in: Capsule())
        .overlay {
            Capsule()
                .stroke(SettingsMonochromeDesign.border, lineWidth: 0.75)
        }
        .buttonStyle(MeasurementPressButtonStyle(pressedScale: 0.97))
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func select(_ unit: UnitPreference) {
        guard selection != unit else { return }

        withAnimation(reduceMotion ? .easeOut(duration: 0.16) : MeasurementsDesign.spring) {
            selection = unit
        }
    }
}
