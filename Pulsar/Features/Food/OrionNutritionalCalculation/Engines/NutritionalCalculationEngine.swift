//
//  NutritionalCalculationEngine.swift
//  Pulsar
//

import Foundation

protocol NutritionalCalculationEngineProtocol {
    func calculate(
        input: NutritionCalculationInput,
        now: Date,
        previousTargetCalories: Double?
    ) throws -> NutritionalCalculationResult
}

extension NutritionalCalculationEngineProtocol {
    func calculate(input: NutritionCalculationInput, now: Date = .now) throws -> NutritionalCalculationResult {
        try calculate(input: input, now: now, previousTargetCalories: nil)
    }
}

struct NutritionalCalculationEngine: NutritionalCalculationEngineProtocol {
    private let validator = NutritionInputValidator()
    private let bmrCalculator = BasalMetabolicRateCalculator()
    private let expenditureEstimator = TotalEnergyExpenditureEstimator()
    private let stabilityGuard = NutritionTargetStabilityGuard()

    func calculate(
        input: NutritionCalculationInput,
        now: Date = .now,
        previousTargetCalories: Double? = nil
    ) throws -> NutritionalCalculationResult {
        let validation = try validator.validate(input)
        let input = validation.input
        let bmr = bmrCalculator.calculate(input: input)
        let confidence = confidence(for: input.healthActivity)
        let maintenance = expenditureEstimator.estimate(
            restingEnergy: bmr.calories,
            input: input,
            confidence: confidence
        )
        let target = targetEnergy(
            maintenance: maintenance.calories,
            restingEnergy: bmr.calories,
            input: input
        )
        let roundedTarget = NutritionTargetStabilityGuard.roundToNearest25(target.calories)
        let changeAssessment = stabilityGuard.assessChange(
            proposedTarget: roundedTarget,
            previousTarget: previousTargetCalories,
            reasons: maintenance.primaryDrivers + target.appliedGuardrails
        )
        let macros = allocateMacros(targetCalories: roundedTarget, input: input)
        let hydration = hydrationTarget(input: input)
        let fiber = max(roundedTarget / 1_000 * 14, input.biologicalSex == .male ? 30 : 25)
        let energy = EnergyCalculationResult(
            basalMetabolicRate: NutritionTargetStabilityGuard.roundToNearest25(bmr.calories),
            maintenanceCalories: maintenance.calories,
            maintenanceRange: maintenance.range,
            targetCalories: roundedTarget,
            targetRange: NutritionTargetStabilityGuard.practicalTargetRange(for: roundedTarget).clampedRounded(),
            estimatedWeeklyWeightChangeKilograms: target.weeklyChange,
            formula: bmr.formula,
            usedMeasuredActivity: maintenance.usedMeasuredActivity,
            rationale: "\(bmr.rationale) \(maintenance.rationale) \(target.rationale)",
            modeledMaintenanceCalories: maintenance.modeledMaintenanceCalories,
            healthKitCalibrationWeight: maintenance.healthKitCalibrationWeight,
            combinedPAL: maintenance.combinedPAL,
            metTableVersion: NutritionMETCompendium.version,
            primaryDrivers: maintenance.primaryDrivers + target.primaryDrivers,
            appliedGuardrails: maintenance.appliedGuardrails + target.appliedGuardrails,
            requiresUserConfirmation: changeAssessment.requiresConfirmation,
            previousTargetCalories: previousTargetCalories,
            confirmationReasons: changeAssessment.requiresConfirmation ? changeAssessment.reasons : []
        )
        let bodyMassIndex = input.weightKilograms / pow(input.heightCentimeters / 100, 2)
        let activityFlags = input.healthActivity?.flags ?? ["No HealthKit activity summary was available."]
        let sexLimitation = input.biologicalSex == .other || input.biologicalSex == .notSet
            ? ["Published adult EER equations do not include separate non-binary coefficients; Pulsar uses the male and female equation span for the range and the midpoint for the provisional target."]
            : []
        return NutritionalCalculationResult(
            calculatedAt: now,
            energy: energy,
            bodyMassIndex: (bodyMassIndex * 10).rounded() / 10,
            bodyMassIndexCategory: bodyMassIndexCategory(bodyMassIndex),
            macros: macros,
            fiberGrams: fiber.rounded(),
            hydrationMilliliters: (hydration / 50).rounded() * 50,
            micronutrients: micronutrients(input: input),
            confidence: confidence,
            limitations: validation.warnings + activityFlags + sexLimitation + [
                "This estimate is informational and cannot account for every medical condition, medication, or metabolic adaptation.",
                "Reassess from weight trend, performance, hunger, and recovery after 2–4 weeks."
            ],
            healthDataCoverage: healthCoverage(from: input.healthActivity)
        )
    }

    private struct TargetEnergyResult {
        var calories: Double
        var weeklyChange: Double
        var rationale: String
        var primaryDrivers: [String]
        var appliedGuardrails: [String]
    }

    private func targetEnergy(
        maintenance: Double,
        restingEnergy: Double,
        input: NutritionCalculationInput
    ) -> TargetEnergyResult {
        let percentageAdjustment: Double
        let maxAbsoluteAdjustment: Double?
        let rationale: String
        switch (input.goal, input.pace) {
        case (.fatLoss, .gentle):
            percentageAdjustment = -0.10
            maxAbsoluteAdjustment = 500
            rationale = "Fat loss uses a gentle 10% deficit capped at 500 kcal/day."
        case (.fatLoss, .standard):
            percentageAdjustment = -0.15
            maxAbsoluteAdjustment = 500
            rationale = "Fat loss uses a standard 15% deficit capped at 500 kcal/day."
        case (.fatLoss, .ambitious):
            percentageAdjustment = -0.20
            maxAbsoluteAdjustment = 500
            rationale = "Fat loss uses an ambitious 20% deficit capped at 500 kcal/day."
        case (.recomposition, _):
            percentageAdjustment = -0.05
            maxAbsoluteAdjustment = nil
            rationale = "Recomposition uses a modest 5% deficit while prioritizing protein."
        case (.muscleGain, .gentle):
            percentageAdjustment = 0.05
            maxAbsoluteAdjustment = 300
            rationale = "Muscle gain uses a gentle 5% surplus capped at 300 kcal/day."
        case (.muscleGain, .standard):
            percentageAdjustment = 0.08
            maxAbsoluteAdjustment = 300
            rationale = "Muscle gain uses a standard 8% surplus capped at 300 kcal/day."
        case (.muscleGain, .ambitious):
            percentageAdjustment = 0.10
            maxAbsoluteAdjustment = 300
            rationale = "Muscle gain uses an ambitious 10% surplus capped at 300 kcal/day."
        case (.maintenance, _):
            percentageAdjustment = 0
            maxAbsoluteAdjustment = nil
            rationale = "The target matches estimated maintenance."
        }

        var adjustment = maintenance * percentageAdjustment
        if let maxAbsoluteAdjustment {
            adjustment = adjustment > 0
                ? min(adjustment, maxAbsoluteAdjustment)
                : max(adjustment, -maxAbsoluteAdjustment)
        }

        var appliedGuardrails: [String] = []
        var calories = maintenance + adjustment
        let sexFloor = absoluteFloor(for: input.biologicalSex)
        let bodySizeAwareFloor = max(sexFloor, restingEnergy, maintenance * 0.80)
        if input.goal == .fatLoss, calories < bodySizeAwareFloor {
            calories = bodySizeAwareFloor
            appliedGuardrails.append("Fat-loss floor applied at the greater of 80% maintenance, resting energy, and sex-based minimum.")
        }

        let weeklyChange = adjustment * 7 / 7_700
        return TargetEnergyResult(
            calories: calories,
            weeklyChange: weeklyChange,
            rationale: rationale,
            primaryDrivers: [
                "Goal adjustment: \(Int((percentageAdjustment * 100).rounded()))% from maintenance."
            ],
            appliedGuardrails: appliedGuardrails
        )
    }

    private func absoluteFloor(for sex: BiologicalSex) -> Double {
        switch sex {
        case .female: 1_200
        case .male: 1_500
        case .other, .notSet: 1_350
        }
    }

    private func allocateMacros(targetCalories: Double, input: NutritionCalculationInput) -> [MacroRecommendation] {
        let proteinFactor: Double
        switch input.goal {
        case .fatLoss, .recomposition: proteinFactor = 2.0
        case .muscleGain: proteinFactor = 1.8
        case .maintenance: proteinFactor = 1.6
        }
        var protein = input.weightKilograms * proteinFactor
        var fat = max(input.weightKilograms * 0.7, targetCalories * 0.22 / 9)
        var carbohydrates = (targetCalories - protein * 4 - fat * 9) / 4

        if carbohydrates < 0 {
            fat = max(input.weightKilograms * 0.6, targetCalories * 0.20 / 9)
            carbohydrates = max(0, (targetCalories - protein * 4 - fat * 9) / 4)
        }
        if carbohydrates < 0 {
            protein = max(input.weightKilograms * 1.4, (targetCalories - fat * 9) / 4)
            carbohydrates = 0
        }

        let enduranceHeavy = input.workoutPlan.sessions.contains {
            [.running, .cycling, .swimming, .rowing, .hiking].contains($0.workoutType)
        }
        let values: [(MacroRecommendation.Kind, Double, Double, String)] = [
            (.protein, protein, 4, "Goal-dependent grams per kilogram support training adaptation and lean-mass retention."),
            (.carbohydrates, carbohydrates, 4, enduranceHeavy
                ? "Carbohydrates receive the remaining energy, with endurance demand considered in the workout plan."
                : "Carbohydrates receive the energy remaining after protein and the fat floor."),
            (.fat, fat, 9, "Fat is protected with a body-weight and percentage-of-energy floor.")
        ]
        return values.map { kind, grams, caloriesPerGram, rationale in
            let roundedGrams = grams.rounded()
            let macroCalories = roundedGrams * caloriesPerGram
            return MacroRecommendation(
                kind: kind,
                grams: roundedGrams,
                range: max(0, roundedGrams * 0.90).rounded()...(roundedGrams * 1.10).rounded(),
                calories: macroCalories,
                percentOfEnergy: min(max(macroCalories / max(targetCalories, 1), 0), 1),
                rationale: rationale
            )
        }
    }

    private func hydrationTarget(input: NutritionCalculationInput) -> Double {
        let activityAllowance = Double(input.workoutPlan.totalMinutesPerWeek)
        return input.weightKilograms * 35 + activityAllowance
    }

    private func micronutrients(input: NutritionCalculationInput) -> [MicronutrientRecommendation] {
        let sodium: Double
        switch input.age {
        case ...50: sodium = 1_500
        case 51...70: sodium = 1_300
        default: sodium = 1_200
        }

        let potassium: Double
        switch input.lifeStage {
        case .pregnant: potassium = 2_900
        case .breastfeeding: potassium = 2_800
        case .none:
            potassium = input.biologicalSex == .male ? 3_400 : 2_600
        }

        let calcium: Double
        if input.age > 70 || (input.biologicalSex == .female && input.age >= 51) {
            calcium = 1_200
        } else {
            calcium = 1_000
        }

        let iron: Double
        switch input.lifeStage {
        case .pregnant: iron = 27
        case .breastfeeding: iron = 9
        case .none:
            if input.biologicalSex == .female && input.age < 51 {
                iron = 18
            } else if (input.biologicalSex == .other || input.biologicalSex == .notSet) && input.age < 51 {
                iron = 13
            } else {
                iron = 8
            }
        }

        let magnesium: Double
        switch input.lifeStage {
        case .pregnant:
            magnesium = input.age <= 30 ? 350 : 360
        case .breastfeeding:
            magnesium = input.age <= 30 ? 310 : 320
        case .none:
            switch input.biologicalSex {
            case .male: magnesium = input.age <= 30 ? 400 : 420
            case .female: magnesium = input.age <= 30 ? 310 : 320
            case .other, .notSet: magnesium = input.age <= 30 ? 355 : 370
            }
        }

        let vitaminD = input.age > 70 ? 20.0 : 15.0

        let vitaminB12: Double
        let folate: Double
        switch input.lifeStage {
        case .none:
            vitaminB12 = 2.4
            folate = 400
        case .pregnant:
            vitaminB12 = 2.6
            folate = 600
        case .breastfeeding:
            vitaminB12 = 2.8
            folate = 500
        }

        let vitaminB12Basis = input.dietaryPreference == .vegan
            ? "Daily reference intake; vegan patterns require a reliable source from fortified foods or clinician-guided supplementation."
            : "Daily reference intake from foods and fortified foods."

        return [
            MicronutrientRecommendation(
                nutrient: "Sodium",
                amount: sodium,
                unit: "mg",
                basis: "Daily adequate-intake food-pattern reference.",
                upperLimitNote: "Keep intake below 2,300 mg/day unless a clinician recommends otherwise."
            ),
            MicronutrientRecommendation(
                nutrient: "Potassium",
                amount: potassium,
                unit: "mg",
                basis: "Daily adequate-intake food-pattern reference.",
                upperLimitNote: "Kidney conditions and some medications can materially change potassium needs."
            ),
            MicronutrientRecommendation(
                nutrient: "Calcium",
                amount: calcium,
                unit: "mg",
                basis: "Daily recommended dietary allowance from foods and fortified foods.",
                upperLimitNote: nil
            ),
            MicronutrientRecommendation(
                nutrient: "Iron",
                amount: iron,
                unit: "mg",
                basis: "Daily recommended dietary allowance; plant-based patterns may require additional planning because nonheme iron is less bioavailable.",
                upperLimitNote: "Do not start high-dose iron supplements without clinician guidance or relevant lab results."
            ),
            MicronutrientRecommendation(
                nutrient: "Magnesium",
                amount: magnesium,
                unit: "mg",
                basis: "Daily recommended dietary allowance from foods.",
                upperLimitNote: "The adult 350 mg upper limit applies to supplemental magnesium, not magnesium naturally present in food."
            ),
            MicronutrientRecommendation(
                nutrient: "Vitamin D",
                amount: vitaminD,
                unit: "mcg",
                basis: "Daily recommended dietary allowance from foods, fortified foods, and appropriate sun exposure.",
                upperLimitNote: "The adult upper limit is 100 mcg/day unless intake is supervised by a clinician."
            ),
            MicronutrientRecommendation(
                nutrient: "Vitamin B12",
                amount: vitaminB12,
                unit: "mcg",
                basis: vitaminB12Basis,
                upperLimitNote: nil
            ),
            MicronutrientRecommendation(
                nutrient: "Folate",
                amount: folate,
                unit: "mcg DFE",
                basis: "Daily recommended dietary allowance expressed as dietary folate equivalents.",
                upperLimitNote: nil
            )
        ]
    }

    private func confidence(for summary: HealthActivitySummary?) -> NutritionDataConfidence {
        guard let summary else { return .low }
        if summary.validEnergyDayCount >= 21 { return .high }
        if summary.validEnergyDayCount >= 7 || summary.observedDayCount >= 7 { return .moderate }
        return .low
    }

    private func healthCoverage(from summary: HealthActivitySummary?) -> [String: Int] {
        guard let summary else { return [:] }
        return [
            "validEnergyDays": summary.validEnergyDayCount,
            "basalEnergyDays": summary.basalEnergyCoverageDays,
            "activeEnergyDays": summary.activeEnergyCoverageDays,
            "stepDays": summary.stepCoverageDays,
            "workoutDays": summary.workoutCoverageDays
        ]
    }

    private func bodyMassIndexCategory(_ value: Double) -> String {
        switch value {
        case ..<18.5: "Below reference range"
        case 18.5..<25: "Reference range"
        case 25..<30: "Above reference range"
        default: "Well above reference range"
        }
    }
}

private extension ClosedRange where Bound == Double {
    func clampedRounded() -> ClosedRange<Double> {
        let roundedLowerBound = NutritionTargetStabilityGuard.roundToNearest25(lowerBound)
        let roundedUpperBound = NutritionTargetStabilityGuard.roundToNearest25(upperBound)
        return roundedLowerBound...roundedUpperBound
    }
}
