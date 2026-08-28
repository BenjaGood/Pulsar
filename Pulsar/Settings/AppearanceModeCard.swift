//
//  AppearanceModeCard.swift
//  Pulsar
//

import SwiftUI

struct AppearanceModeCard: View {
    var mode: HomeBackgroundMode
    var isSelected: Bool
    var select: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: select) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            AppearanceModePreview(mode: mode)
                                .frame(width: 100, height: 74)

                            Spacer(minLength: 16)

                            AppearanceSelectionIndicator(isSelected: isSelected)
                        }

                        Text(mode.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                } else {
                    HStack(spacing: 18) {
                        AppearanceModePreview(mode: mode)
                            .frame(width: 124, height: 92)

                        Text(mode.title)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Spacer(minLength: 8)

                        AppearanceSelectionIndicator(isSelected: isSelected)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .contentShape(.rect(cornerRadius: 30))
            .pulsarSettingsCardSurface(cornerRadius: 30, interactive: true)
            .overlay {
                RoundedRectangle(cornerRadius: 30)
                    .stroke(Color.black.opacity(0.03), lineWidth: 0.6)
                    .allowsHitTesting(false)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
