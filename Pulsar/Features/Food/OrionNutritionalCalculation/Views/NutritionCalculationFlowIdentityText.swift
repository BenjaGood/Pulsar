//
//  NutritionCalculationFlowIdentityText.swift
//  Pulsar
//

import SwiftUI

struct NutritionCalculationFlowIdentityText: View {
    var keepsSubtitleOnOneLine = false
    var minimumScaleFactor = 0.82

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Orion Nutritional Calculation")
                .pulsarTextStyle(.label)
                .foregroundStyle(NutritionDesign.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(minimumScaleFactor)

            Text("Personalized nutrition targets")
                .pulsarTextStyle(.metadata)
                .foregroundStyle(NutritionDesign.secondaryText)
                .lineLimit(keepsSubtitleOnOneLine ? 1 : nil)
                .minimumScaleFactor(minimumScaleFactor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
