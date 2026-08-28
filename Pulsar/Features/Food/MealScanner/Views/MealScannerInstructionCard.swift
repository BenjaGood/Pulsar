//
//  MealScannerInstructionCard.swift
//  Pulsar
//

import SwiftUI

struct MealScannerInstructionCard: View {
    var guidance: MealScannerCameraOverlay.Guidance

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 10) {
            Image(systemName: guidance.symbolName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
                .shadow(color: .black.opacity(0.42), radius: 2, y: 1)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(guidance.title)
                    .pulsarTextStyle(.cardTitle)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.48), radius: 2, y: 1)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(guidance.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.62))
                    .shadow(color: .black.opacity(0.48), radius: 2, y: 1)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .id(guidance.id)
            .transition(
                reduceMotion
                    ? .opacity
                    : .opacity.combined(with: .offset(y: 6))
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .mealScannerGlassSurface(cornerRadius: 26)
        .animation(.smooth(duration: reduceMotion ? 0.14 : 0.24), value: guidance.id)
        .accessibilityElement(children: .combine)
    }
}
