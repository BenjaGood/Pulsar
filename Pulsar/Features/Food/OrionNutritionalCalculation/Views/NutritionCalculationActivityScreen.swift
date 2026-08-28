//
//  NutritionCalculationActivityScreen.swift
//  Pulsar
//

import SwiftUI

struct NutritionCalculationActivityScreen: View {
    @Bindable var viewModel: NutritionalCalculationViewModel
    var onClose: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let density = NutritionActivityLayoutDensity(
                availableHeight: geometry.size.height
            )

            PulsarGlassEffectGroup(spacing: density.sectionSpacing) {
                VStack(spacing: density.sectionSpacing) {
                    NutritionCalculationScreenHeader(
                        title: viewModel.step.title,
                        subtitle: "Track your progress. Build your best self.",
                        canMoveBack: viewModel.canMoveBack,
                        usesCompactSpacing: density.isCompactHeight,
                        onBack: viewModel.moveBack,
                        onClose: onClose
                    )

                    NutritionCalculationFlowHeader(
                        currentStep: viewModel.step.rawValue + 1,
                        totalSteps: NutritionalCalculationViewModel.Step.allCases.count,
                        progress: viewModel.progress,
                        showsCompletionPercentage: true,
                        usesCompactSpacing: density.isCompactHeight,
                        usesVeryCompactSpacing: density.isVeryCompactHeight
                    )

                    NutritionCalculationActivityStep(
                        viewModel: viewModel,
                        density: density
                    )
                    .frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal, NutritionCalculationDesign.screenHorizontalPadding)
            .padding(.top, density.topPadding)
            .padding(.bottom, density.bottomPadding)
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .top
            )
        }
    }
}
