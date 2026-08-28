//
//  NutritionInputValidator.swift
//  Pulsar
//

import Foundation

enum NutritionInputValidationError: LocalizedError, Equatable {
    case ageOutOfRange
    case heightOutOfRange
    case weightOutOfRange
    case acknowledgementRequired
    case lifeStageNeedsClinicalGuidance
    case bodyMassIndexTooLow
    case targetBodyMassIndexTooLow
    case workoutPlanRequired
    case workoutPlanExceedsLimits

    var errorDescription: String? {
        switch self {
        case .ageOutOfRange: "This calculator currently supports adults ages 18–100."
        case .heightOutOfRange: "Enter a height between 120 and 230 cm."
        case .weightOutOfRange: "Enter a weight between 35 and 300 kg."
        case .acknowledgementRequired: "Confirm that this is informational guidance, not medical care."
        case .lifeStageNeedsClinicalGuidance: "Pregnancy and breastfeeding targets need individualized clinical guidance; Pulsar will not generate or save a generic calorie target."
        case .bodyMassIndexTooLow: "Fat-loss targets are blocked when current BMI is below 18.5."
        case .targetBodyMassIndexTooLow: "The requested target weight would place BMI below 18.5."
        case .workoutPlanRequired: "Add at least one workout entry when you train regularly."
        case .workoutPlanExceedsLimits: "The workout plan exceeds the supported weekly session or duration limits."
        }
    }
}

struct NutritionInputValidation: Equatable {
    var input: NutritionCalculationInput
    var warnings: [String]
}

struct NutritionInputValidator {
    func validate(_ input: NutritionCalculationInput) throws -> NutritionInputValidation {
        guard (18...100).contains(input.age) else { throw NutritionInputValidationError.ageOutOfRange }
        guard (120...230).contains(input.heightCentimeters) else { throw NutritionInputValidationError.heightOutOfRange }
        guard (35...300).contains(input.weightKilograms) else { throw NutritionInputValidationError.weightOutOfRange }
        guard input.medicalAcknowledgementAccepted else { throw NutritionInputValidationError.acknowledgementRequired }
        guard input.lifeStage == .none else { throw NutritionInputValidationError.lifeStageNeedsClinicalGuidance }

        var normalized = input
        normalized.schemaVersion = NutritionCalculationInput.schemaVersion
        var warnings: [String] = []

        if let bodyFat = input.bodyFatPercentage, !(5...60).contains(bodyFat) {
            normalized.bodyFatPercentage = nil
            warnings.append("Body-fat percentage was outside the supported plausibility range, so Mifflin–St Jeor was used for the resting-energy display.")
        }
        if let targetWeight = input.targetWeightKilograms, !(35...300).contains(targetWeight) {
            normalized.targetWeightKilograms = nil
            warnings.append("Target weight was outside the supported range and was not used in the calculation.")
        }
        if normalized.biologicalSex != .female {
            normalized.lifeStage = .none
        }

        normalized.workoutPlan.sessions = normalized.workoutPlan.sessions.map { entry in
            var sanitized = entry
            sanitized.daysPerWeek = min(max(entry.daysPerWeek, 1), 7)
            sanitized.sessionsPerDay = min(max(entry.sessionsPerDay, 1), 3)
            sanitized.minutesPerSession = min(max((entry.minutesPerSession / 5) * 5, 5), 300)
            return sanitized
        }

        if normalized.trainsRegularly && normalized.workoutPlan.sessions.isEmpty {
            throw NutritionInputValidationError.workoutPlanRequired
        }
        if normalized.workoutPlan.totalSessionsPerWeek > 21 {
            throw NutritionInputValidationError.workoutPlanExceedsLimits
        }

        let currentBMI = bodyMassIndex(weight: normalized.weightKilograms, height: normalized.heightCentimeters)
        if normalized.goal == .fatLoss {
            if currentBMI < 18.5 {
                throw NutritionInputValidationError.bodyMassIndexTooLow
            }
            if let targetWeight = normalized.targetWeightKilograms,
               bodyMassIndex(weight: targetWeight, height: normalized.heightCentimeters) < 18.5 {
                throw NutritionInputValidationError.targetBodyMassIndexTooLow
            }
        }

        if let targetDate = normalized.targetDate {
            let weeks = max(targetDate.timeIntervalSinceNow / (7 * 86_400), 0.5)
            if let targetWeight = normalized.targetWeightKilograms {
                let weeklyChange = (targetWeight - normalized.weightKilograms) / weeks
                if abs(weeklyChange) > normalized.weightKilograms * 0.01 {
                    warnings.append("The requested target date implies a pace faster than the selected adjustment; Pulsar will flag this but will not force calories lower to meet the date.")
                }
            }
        }

        return NutritionInputValidation(input: normalized, warnings: warnings)
    }

    private func bodyMassIndex(weight: Double, height: Double) -> Double {
        weight / pow(height / 100, 2)
    }
}
