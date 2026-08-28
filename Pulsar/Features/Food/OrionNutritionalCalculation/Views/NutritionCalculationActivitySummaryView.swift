//
//  NutritionCalculationActivitySummaryView.swift
//  Pulsar
//

import SwiftUI

struct NutritionCalculationActivitySummaryView: View {
    var summary: HealthActivitySummary
    var healthKitWeightKilograms: Double?
    var profileWeightKilograms: Double
    var density: NutritionActivityLayoutDensity = .regular
    var onUseHealthKitWeight: () -> Void
    var onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: density.healthContentSpacing) {
            Label {
                Text("HealthKit Summary")
                    .font(.system(density.isVeryCompactHeight ? .title3 : .title2, design: .serif, weight: .medium))
                    .foregroundStyle(NutritionDesign.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            } icon: {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(NutritionDesign.primaryText)
                    .frame(width: density.metricIconDiameter, height: density.metricIconDiameter)
                    .background(.black.opacity(0.025), in: .circle)
            }
            .accessibilityAddTraits(.isHeader)

            HStack(spacing: 10) {
                NutritionActivityMetricCard(
                    symbolName: "figure.walk",
                    value: Int(summary.averageSteps.rounded()).formatted(),
                    label: "Steps",
                    density: density
                )

                NutritionActivityMetricCard(
                    symbolName: "flame.fill",
                    value: Int(summary.averageActiveEnergyKilocalories.rounded()).formatted(),
                    unit: "kcal",
                    label: "Active Energy",
                    density: density
                )

                NutritionActivityMetricCard(
                    symbolName: "figure.run",
                    value: Int(summary.averageExerciseMinutes.rounded()).formatted(),
                    unit: "min",
                    label: "Exercise",
                    density: density
                )
            }

            Divider()
                .overlay(.black.opacity(0.035))

            NutritionActivitySummaryMetadata(
                validEnergyDayCount: summary.validEnergyDayCount,
                workoutCount: summary.workoutCount,
                density: density
            )

            if let informationMessage {
                NutritionActivityInformationRow(message: informationMessage, density: density)
            }

            if shouldOfferHealthKitWeight, let healthKitWeightKilograms {
                NutritionActivityOutlineButton(
                    title: "Use HealthKit weight (\(healthKitWeightKilograms.formatted(.number.precision(.fractionLength(1)))) kg)",
                    symbolName: "scalemass",
                    density: density,
                    action: onUseHealthKitWeight
                )
            }

            NutritionActivityOutlineButton(
                title: "Refresh HealthKit summary",
                symbolName: "arrow.clockwise",
                density: density,
                action: onRefresh
            )
        }
        .padding(density.healthCardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .nutritionCalculationGlassSurface(
            cornerRadius: 30,
            fillOpacity: 0.91,
            borderOpacity: 0.042,
            borderWidth: 0.55,
            shadowOpacity: 0.024,
            shadowRadius: 16,
            shadowY: 7
        )
    }

    private var shouldOfferHealthKitWeight: Bool {
        guard let healthKitWeightKilograms else { return false }
        return abs(healthKitWeightKilograms - profileWeightKilograms) > 0.1
    }

    private var informationMessage: String? {
        if summary.anomalyCodes.contains(.planWorkoutConflict) {
            return "Recent HealthKit workouts differ from your planned routine."
        }

        return summary.flags.first
    }
}

#Preview(
    "Activity Summary Loaded — Compact",
    traits: .fixedLayout(width: 375, height: 667)
) {
    let summary: HealthActivitySummary = {
        var summary = HealthActivitySummary.unavailable
        summary.validEnergyDayCount = 21
        summary.averageSteps = 6_964
        summary.averageActiveEnergyKilocalories = 766
        summary.averageExerciseMinutes = 61
        summary.workoutCount = 30
        summary.confidence = .high
        summary.flags = ["Recent HealthKit workouts differ from your planned routine."]
        summary.anomalyCodes = [.planWorkoutConflict]
        return summary
    }()

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

                    NutritionCalculationActivitySummaryView(
                        summary: summary,
                        healthKitWeightKilograms: nil,
                        profileWeightKilograms: 100,
                        density: density,
                        onUseHealthKitWeight: {},
                        onRefresh: {}
                    )
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
            usesNeutralBackdrop: true,
            emphasizesPrimaryAction: true,
            action: {}
        )
    }
    .pulsarFitnessMonochromeAppearance()
}
