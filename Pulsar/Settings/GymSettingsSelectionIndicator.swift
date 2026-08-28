//
//  GymSettingsSelectionIndicator.swift
//  Pulsar
//

import SwiftUI

struct GymSettingsSelectionIndicator: View {
    var isSelected: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary, lineWidth: 1.5)
                .opacity(isSelected ? 0 : 0.72)

            Circle()
                .fill(GymSettingsDesign.accent)
                .opacity(isSelected ? 1 : 0)

            Image(systemName: "checkmark")
                .font(.caption)
                .bold()
                .foregroundStyle(.white)
                .opacity(isSelected ? 1 : 0)
                .scaleEffect(isSelected ? 1 : 0.7)
        }
        .frame(width: 27, height: 27)
        .scaleEffect(isSelected ? 1 : 0.94)
        .animation(
            GymSettingsDesign.selectionAnimation(reduceMotion: reduceMotion),
            value: isSelected
        )
        .accessibilityHidden(true)
    }
}
