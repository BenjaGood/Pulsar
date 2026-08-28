//
//  NutritionCalculationActivityLoadingView.swift
//  Pulsar
//

import SwiftUI

struct NutritionCalculationActivityLoadingView: View {
    var density = NutritionActivityLayoutDensity.regular

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            ZStack {
                NutritionActivityRippleField()
                    .frame(maxWidth: density.loadingRippleWidth)

                NutritionActivityLoadingOrb(
                    proposedDiameter: density.loadingOrbDiameter
                )
            }
            .frame(maxWidth: .infinity)
            .frame(height: density.loadingAnimationHeight)

            VStack(spacing: density.isVeryCompactHeight ? 6 : 8) {
                Text("Summarizing your activity")
                    .font(
                        .system(
                            density.isVeryCompactHeight ? .title3 : .title2,
                            design: .serif,
                            weight: .medium
                        )
                    )
                    .foregroundStyle(NutritionDesign.primaryText)
                    .multilineTextAlignment(.center)

                Text("We’re reviewing your workouts, steps, and movement patterns.")
                    .pulsarTextStyle(.metadata)
                    .foregroundStyle(NutritionDesign.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Label("Up to 28 days of activity", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NutritionDesign.secondaryText)
                    .padding(.horizontal, 14)
                    .frame(minHeight: density.isCompactHeight ? 30 : 34)
                    .background(.black.opacity(0.025), in: .capsule)
                    .padding(.top, density.isCompactHeight ? 4 : 7)
            }
            .padding(.horizontal, 22)

            Spacer(minLength: 0)
        }
        .padding(.vertical, density.isCompactHeight ? 6 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .nutritionCalculationGlassSurface(
            cornerRadius: 34,
            fillOpacity: 0.90,
            borderOpacity: 0.042,
            borderWidth: 0.55,
            shadowOpacity: 0.026,
            shadowRadius: 18,
            shadowY: 8
        )
        .clipShape(.rect(cornerRadius: 34, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Summarizing your activity")
        .accessibilityValue("Reviewing up to 28 days of workouts, steps, and movement patterns")
    }
}

#Preview(
    "Activity Summary Loading — Compact",
    traits: .fixedLayout(width: 375, height: 667)
) {
    ZStack {
        Color.white
            .ignoresSafeArea()

        GeometryReader { geometry in
            let density = NutritionActivityLayoutDensity(availableHeight: geometry.size.height)

            PulsarGlassEffectGroup(spacing: density.sectionSpacing) {
                VStack(spacing: density.sectionSpacing) {
                    NutritionCalculationScreenHeader(
                        title: "Activity Summary",
                        subtitle: "Track your progress. Build your best self.",
                        canMoveBack: true,
                        usesCompactSpacing: density.isCompactHeight,
                        onBack: {},
                        onClose: {}
                    )

                    NutritionCalculationFlowHeader(
                        currentStep: 3,
                        totalSteps: 7,
                        progress: 3.0 / 7.0,
                        showsCompletionPercentage: true,
                        usesCompactSpacing: density.isCompactHeight,
                        usesVeryCompactSpacing: density.isVeryCompactHeight
                    )

                    NutritionCalculationActivityLoadingView(density: density)
                        .frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal, NutritionCalculationDesign.screenHorizontalPadding)
            .padding(.top, density.topPadding)
            .padding(.bottom, density.bottomPadding)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
    }
    .safeAreaInset(edge: .bottom) {
        NutritionCalculationContinueBar(
            title: "Continue",
            isDisabled: false,
            showsTrailingChevron: true,
            usesNeutralBackdrop: true,
            action: {}
        )
    }
    .pulsarFitnessMonochromeAppearance()
}
