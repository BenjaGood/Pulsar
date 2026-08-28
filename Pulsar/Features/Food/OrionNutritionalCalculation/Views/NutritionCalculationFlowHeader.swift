//
//  NutritionCalculationFlowHeader.swift
//  Pulsar
//

import SwiftUI

struct NutritionCalculationFlowHeader: View {
    var currentStep: Int
    var totalSteps: Int
    var progress: Double
    var showsCompletionPercentage = false
    var usesCompactSpacing = false
    var usesVeryCompactSpacing = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: showsCompletionPercentage && usesCompactSpacing ? 10 : (showsCompletionPercentage ? 16 : 14)) {
            if showsCompletionPercentage {
                NutritionCalculationHeroIdentity(
                    currentStep: currentStep,
                    totalSteps: totalSteps,
                    usesCompactSpacing: usesCompactSpacing,
                    usesVeryCompactSpacing: usesVeryCompactSpacing
                )
            } else if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        OrionAnimatedLogo(size: 68)
                        Spacer(minLength: 12)
                        stepLabel
                    }
                    NutritionCalculationFlowIdentityText()
                }
            } else {
                ZStack(alignment: .topTrailing) {
                    HStack(spacing: 14) {
                        OrionAnimatedLogo(size: 72)
                        NutritionCalculationFlowIdentityText()
                            .padding(.trailing, 34)
                        Spacer(minLength: 0)
                    }

                    stepLabel
                }
            }

            NutritionCalculationProgressBar(
                progress: progress,
                currentStep: currentStep,
                totalSteps: totalSteps
            )

            if showsCompletionPercentage {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int((min(max(progress, 0), 1) * 100).rounded()))%")
                        .pulsarTextStyle(.bodyEmphasis)
                        .foregroundStyle(NutritionDesign.primaryText)
                        .monospacedDigit()

                    Text("complete")
                        .pulsarTextStyle(.metadata)
                        .foregroundStyle(NutritionDesign.secondaryText)
                }
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, showsCompletionPercentage && usesCompactSpacing ? 18 : (showsCompletionPercentage ? 20 : 18))
        .padding(
            .vertical,
            showsCompletionPercentage
                ? (usesVeryCompactSpacing ? 12 : (usesCompactSpacing ? 14 : 22))
                : 16
        )
        .frame(maxWidth: .infinity)
        .nutritionCalculationGlassSurface(
            cornerRadius: showsCompletionPercentage ? 32 : NutritionCalculationDesign.compactCardCornerRadius,
            fillOpacity: showsCompletionPercentage ? 0.92 : 0.58,
            borderOpacity: showsCompletionPercentage ? 0.045 : 0.03,
            shadowOpacity: showsCompletionPercentage ? 0.028 : 0.022,
            shadowRadius: showsCompletionPercentage ? 16 : 10,
            shadowY: showsCompletionPercentage ? 8 : 5
        )
    }

    private var stepLabel: some View {
        Text("\(currentStep)/\(totalSteps)")
            .pulsarTextStyle(.metadata)
            .foregroundStyle(NutritionDesign.secondaryText)
            .monospacedDigit()
            .contentTransition(.numericText())
    }
}
