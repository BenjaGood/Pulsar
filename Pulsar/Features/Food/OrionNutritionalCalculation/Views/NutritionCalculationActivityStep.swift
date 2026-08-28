//
//  NutritionCalculationActivityStep.swift
//  Pulsar
//

import SwiftUI

struct NutritionCalculationActivityStep: View {
    @Bindable var viewModel: NutritionalCalculationViewModel
    var density = NutritionActivityLayoutDensity.regular

    var body: some View {
        VStack(spacing: density.healthContentSpacing) {
            if viewModel.isLoadingActivity {
                NutritionCalculationActivityLoadingView(density: density)
            } else if let summary = viewModel.input.healthActivity {
                NutritionCalculationActivitySummaryView(
                    summary: summary,
                    healthKitWeightKilograms: viewModel.healthKitWeightKilograms,
                    profileWeightKilograms: viewModel.input.weightKilograms,
                    density: density,
                    onUseHealthKitWeight: viewModel.useHealthKitWeight,
                    onRefresh: refreshActivity
                )
            }

            if let errorMessage = viewModel.errorMessage {
                NutritionActivityInformationRow(
                    message: errorMessage,
                    density: density
                )
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func refreshActivity() {
        Task {
            await viewModel.reloadActivity()
        }
    }
}
