//
//  NutritionCalculationSymbolBadge.swift
//  Pulsar
//

import SwiftUI

struct NutritionCalculationSymbolBadge: View {
    var symbolName: String
    var size: CGFloat = NutritionCalculationDesign.symbolSize
    var symbolSize: CGFloat = 16

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: symbolSize, weight: .regular))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(NutritionDesign.primaryText.opacity(0.78))
            .frame(width: size, height: size)
            .nutritionCalculationGlassSurface(
                cornerRadius: size / 2,
                fillOpacity: 0.27,
                borderOpacity: 0.032,
                shadowOpacity: 0.012,
                shadowRadius: 4,
                shadowY: 2
            )
            .accessibilityHidden(true)
    }
}
