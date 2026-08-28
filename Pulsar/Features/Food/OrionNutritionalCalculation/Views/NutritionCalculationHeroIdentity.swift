//
//  NutritionCalculationHeroIdentity.swift
//  Pulsar
//

import SwiftUI

struct NutritionCalculationHeroIdentity: View {
    var currentStep: Int
    var totalSteps: Int
    var usesCompactSpacing = false
    var usesVeryCompactSpacing = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 14) {
                    OrionAnimatedLogo(
                        size: usesVeryCompactSpacing ? 64 : (usesCompactSpacing ? 72 : 80)
                    )

                    NutritionCalculationFlowIdentityText(
                        keepsSubtitleOnOneLine: true,
                        minimumScaleFactor: 0.82
                    )
                    .padding(.top, usesCompactSpacing ? 11 : 16)

                    Spacer(minLength: 0)

                    chevron
                        .padding(.top, usesCompactSpacing ? 24 : 30)
                }

                stepLabel
            }

            ZStack(alignment: .topTrailing) {
                HStack(spacing: 12) {
                    OrionAnimatedLogo(size: usesVeryCompactSpacing ? 54 : 62)

                    NutritionCalculationFlowIdentityText(
                        keepsSubtitleOnOneLine: true,
                        minimumScaleFactor: 0.70
                    )
                    .padding(.top, usesCompactSpacing ? 10 : 14)

                    Spacer(minLength: 0)

                    chevron
                        .padding(.top, usesCompactSpacing ? 21 : 26)
                }

                stepLabel
            }
        }
    }

    private var stepLabel: some View {
        Text("Step \(currentStep) of \(totalSteps)")
            .pulsarTextStyle(.metadata)
            .foregroundStyle(NutritionDesign.secondaryText)
            .monospacedDigit()
            .contentTransition(.numericText())
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(NutritionDesign.secondaryText)
            .accessibilityHidden(true)
    }
}
