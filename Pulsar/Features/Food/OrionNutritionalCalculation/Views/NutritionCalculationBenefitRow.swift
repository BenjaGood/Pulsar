//
//  NutritionCalculationBenefitRow.swift
//  Pulsar
//

import SwiftUI

struct NutritionCalculationBenefitRow: View {
    var title: String
    var subtitle: String
    var symbolName: String

    var body: some View {
        HStack(alignment: .center, spacing: NutritionCalculationDesign.rowSpacing) {
            NutritionCalculationSymbolBadge(symbolName: symbolName)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .pulsarTextStyle(.label)
                    .foregroundStyle(NutritionDesign.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .pulsarTextStyle(.metadata)
                    .foregroundStyle(NutritionDesign.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}
