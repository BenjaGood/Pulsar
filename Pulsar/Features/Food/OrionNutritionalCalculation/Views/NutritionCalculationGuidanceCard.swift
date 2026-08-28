//
//  NutritionCalculationGuidanceCard.swift
//  Pulsar
//

import SwiftUI

struct NutritionCalculationGuidanceCard: View {
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            NutritionCalculationSymbolBadge(
                symbolName: "info",
                size: 36,
                symbolSize: 14
            )

            Text("These recommendations are intended as nutritional guidance and are not medical diagnosis or treatment.")
                .pulsarTextStyle(.metadata)
                .foregroundStyle(NutritionDesign.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nutritionCalculationGlassSurface(
            cornerRadius: 20,
            fillOpacity: 0.25,
            borderOpacity: 0.026,
            shadowOpacity: 0.006,
            shadowRadius: 3,
            shadowY: 1
        )
        .accessibilityElement(children: .combine)
    }
}
