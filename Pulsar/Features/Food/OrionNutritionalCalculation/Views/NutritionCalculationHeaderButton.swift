//
//  NutritionCalculationHeaderButton.swift
//  Pulsar
//

import SwiftUI

struct NutritionCalculationHeaderButton: View {
    var title: String
    var symbolName: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbolName)
                .labelStyle(.iconOnly)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(NutritionDesign.primaryText)
                .frame(width: 40, height: 40)
                .contentShape(.circle)
                .nutritionCalculationGlassSurface(
                    cornerRadius: 20,
                    isInteractive: true,
                    fillOpacity: 0.30,
                    borderOpacity: 0.038,
                    shadowOpacity: 0.016,
                    shadowRadius: 5,
                    shadowY: 2
                )
        }
        .frame(width: 44, height: 44)
        .buttonStyle(NutritionCalculationPressButtonStyle())
    }
}
