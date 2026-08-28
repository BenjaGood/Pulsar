//
//  NutritionalCalculationResult.swift
//  Pulsar
//

import Foundation

enum BasalMetabolicFormula: String, Codable, Hashable {
    case mifflinStJeor
    case katchMcArdle

    var title: String {
        switch self {
        case .mifflinStJeor: "Mifflin–St Jeor"
        case .katchMcArdle: "Katch–McArdle"
        }
    }
}

struct EnergyCalculationResult: Codable, Equatable, Hashable {
    var basalMetabolicRate: Double
    var maintenanceCalories: Double
    var maintenanceRange: ClosedRange<Double>
    var targetCalories: Double
    var targetRange: ClosedRange<Double>
    var estimatedWeeklyWeightChangeKilograms: Double
    var formula: BasalMetabolicFormula
    var usedMeasuredActivity: Bool
    var rationale: String
    var modeledMaintenanceCalories: Double = 0
    var healthKitCalibrationWeight: Double = 0
    var combinedPAL: Double = 1.5
    var metTableVersion: String = NutritionMETCompendium.version
    var primaryDrivers: [String] = []
    var appliedGuardrails: [String] = []
    var requiresUserConfirmation: Bool = false
    var previousTargetCalories: Double?
    var confirmationReasons: [String] = []
}

struct MacroRecommendation: Codable, Equatable, Hashable, Identifiable {
    enum Kind: String, Codable, Hashable {
        case protein
        case carbohydrates
        case fat

        var title: String { rawValue.capitalized }
    }

    var kind: Kind
    var grams: Double
    var range: ClosedRange<Double>
    var calories: Double
    var percentOfEnergy: Double
    var rationale: String

    var id: Kind { kind }
}

struct MicronutrientRecommendation: Codable, Equatable, Hashable, Identifiable {
    var nutrient: String
    var amount: Double
    var unit: String
    var basis: String
    var upperLimitNote: String?

    var id: String { nutrient }
}

struct NutritionalCalculationResult: Identifiable, Codable, Equatable, Hashable {
    static let guidelineVersion = "2026.07-v2"

    var id: UUID
    var calculatedAt: Date
    var guidelineVersion: String
    var methodologyVersion: String = EstimatedEnergyRequirementCalculator.methodologyVersion
    var energy: EnergyCalculationResult
    var bodyMassIndex: Double
    var bodyMassIndexCategory: String
    var macros: [MacroRecommendation]
    var fiberGrams: Double
    var hydrationMilliliters: Double
    var micronutrients: [MicronutrientRecommendation]
    var confidence: NutritionDataConfidence
    var limitations: [String]
    var healthDataCoverage: [String: Int] = [:]
    var cumulativeAdaptationCalories: Double = 0

    init(
        id: UUID = UUID(),
        calculatedAt: Date = .now,
        guidelineVersion: String = NutritionalCalculationResult.guidelineVersion,
        methodologyVersion: String = EstimatedEnergyRequirementCalculator.methodologyVersion,
        energy: EnergyCalculationResult,
        bodyMassIndex: Double,
        bodyMassIndexCategory: String,
        macros: [MacroRecommendation],
        fiberGrams: Double,
        hydrationMilliliters: Double,
        micronutrients: [MicronutrientRecommendation],
        confidence: NutritionDataConfidence,
        limitations: [String],
        healthDataCoverage: [String: Int] = [:],
        cumulativeAdaptationCalories: Double = 0
    ) {
        self.id = id
        self.calculatedAt = calculatedAt
        self.guidelineVersion = guidelineVersion
        self.methodologyVersion = methodologyVersion
        self.energy = energy
        self.bodyMassIndex = bodyMassIndex
        self.bodyMassIndexCategory = bodyMassIndexCategory
        self.macros = macros
        self.fiberGrams = fiberGrams
        self.hydrationMilliliters = hydrationMilliliters
        self.micronutrients = micronutrients
        self.confidence = confidence
        self.limitations = limitations
        self.healthDataCoverage = healthDataCoverage
        self.cumulativeAdaptationCalories = cumulativeAdaptationCalories
    }

    func macro(_ kind: MacroRecommendation.Kind) -> MacroRecommendation? {
        macros.first { $0.kind == kind }
    }
}
