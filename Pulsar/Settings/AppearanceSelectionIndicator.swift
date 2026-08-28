//
//  AppearanceSelectionIndicator.swift
//  Pulsar
//

import SwiftUI

struct AppearanceSelectionIndicator: View {
    var isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? selectionColor : .clear)

            Circle()
                .stroke(
                    isSelected ? .clear : Color.black.opacity(0.13),
                    lineWidth: 1.5
                )

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .bold()
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 26, height: 26)
        .accessibilityHidden(true)
    }

    private var selectionColor: Color {
        SettingsMonochromeDesign.primary
    }
}
