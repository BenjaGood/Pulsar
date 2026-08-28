//
//  NutritionActivityOutlineButton.swift
//  Pulsar
//

import SwiftUI

struct NutritionActivityOutlineButton: View {
    var title: String
    var symbolName: String
    var density: NutritionActivityLayoutDensity = .regular
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: density.isCompactHeight ? 10 : 13) {
                Image(systemName: symbolName)
                    .font(.system(size: 17, weight: .medium))

                Text(title)
                    .pulsarTextStyle(.bodyEmphasis)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NutritionDesign.secondaryText)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(NutritionDesign.primaryText)
            .padding(.horizontal, density.isCompactHeight ? 14 : 17)
            .frame(maxWidth: .infinity)
            .frame(height: density.secondaryButtonHeight)
            .contentShape(.rect(cornerRadius: 24))
            .nutritionCalculationGlassSurface(
                cornerRadius: 24,
                isInteractive: true,
                fillOpacity: 0.66,
                borderOpacity: 0.065,
                borderWidth: 0.6,
                shadowOpacity: 0.012,
                shadowRadius: 5,
                shadowY: 2
            )
        }
        .buttonStyle(NutritionCalculationPressButtonStyle(pressedScale: 0.988))
    }
}
