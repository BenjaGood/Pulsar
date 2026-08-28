//
//  NutritionCalculationIntroductionStep.swift
//  Pulsar
//

import SwiftUI

struct NutritionCalculationIntroductionStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: NutritionCalculationDesign.rowSpacing) {
                NutritionCalculationSymbolBadge(
                    symbolName: "sparkles",
                    size: 44,
                    symbolSize: 17
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("What we calculate")
                        .pulsarTextStyle(.sectionHeader)
                        .foregroundStyle(NutritionDesign.primaryText)
                        .accessibilityAddTraits(.isHeader)

                    Text("We create personalized calorie and nutrition targets using evidence-based formulas and your Health data, giving you a reliable starting point tailored to your body.")
                        .pulsarTextStyle(.metadata)
                        .foregroundStyle(NutritionDesign.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 14)

            separator

            NutritionCalculationBenefitRow(
                title: "Private & On-device",
                subtitle: "All calculations happen on your device.",
                symbolName: "iphone"
            )

            separator

            NutritionCalculationBenefitRow(
                title: "Health data only",
                subtitle: "Uses your aggregated HealthKit activity.",
                symbolName: "heart"
            )

            separator

            NutritionCalculationBenefitRow(
                title: "AI insights (optional)",
                subtitle: "Orion can explain the results if you choose.",
                symbolName: "sparkles"
            )

            separator

            NutritionCalculationBenefitRow(
                title: "100% private",
                subtitle: "No API keys. Your personal data never leaves your device.",
                symbolName: "lock.shield"
            )

            separator
                .padding(.bottom, 14)

            NutritionCalculationGuidanceCard()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nutritionCalculationGlassSurface(
            cornerRadius: NutritionCalculationDesign.cardCornerRadius,
            fillOpacity: 0.60,
            borderOpacity: 0.028,
            shadowOpacity: 0.022,
            shadowRadius: 10,
            shadowY: 5
        )
    }

    private var separator: some View {
        Rectangle()
            .fill(NutritionDesign.separator.opacity(0.42))
            .frame(height: 0.35)
            .padding(.leading, NutritionCalculationDesign.separatorInset)
    }
}
