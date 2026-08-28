//
//  MeasurementGlassStepper.swift
//  Pulsar
//

import SwiftUI

struct MeasurementGlassStepper: View {
    var label: String
    var canDecrement: Bool
    var canIncrement: Bool
    var decrement: () -> Void
    var increment: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button("Decrease \(label)", systemImage: "minus", action: decrement)
                .labelStyle(.iconOnly)
                .disabled(!canDecrement)

            Divider()
                .frame(height: 24)

            Button("Increase \(label)", systemImage: "plus", action: increment)
                .labelStyle(.iconOnly)
                .disabled(!canIncrement)
        }
        .font(.body)
        .bold()
        .foregroundStyle(.primary)
        .frame(width: 112, height: 48)
        .background(SettingsMonochromeDesign.surface, in: Capsule())
        .overlay {
            Capsule()
                .stroke(SettingsMonochromeDesign.border, lineWidth: 0.75)
        }
        .shadow(color: SettingsMonochromeDesign.shadow, radius: 8, y: 3)
        .buttonStyle(MeasurementPressButtonStyle())
        .accessibilityElement(children: .contain)
    }
}
