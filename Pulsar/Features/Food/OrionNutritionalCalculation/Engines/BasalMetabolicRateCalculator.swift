//
//  BasalMetabolicRateCalculator.swift
//  Pulsar
//

import Foundation

struct BasalMetabolicRateEstimate: Equatable {
    var calories: Double
    var formula: BasalMetabolicFormula
    var rationale: String
}

struct BasalMetabolicRateCalculator {
    func calculate(input: NutritionCalculationInput) -> BasalMetabolicRateEstimate {
        if let bodyFat = input.bodyFatPercentage, (5...60).contains(bodyFat) {
            let leanMassKilograms = input.weightKilograms * (1 - bodyFat / 100)
            return BasalMetabolicRateEstimate(
                calories: 370 + 21.6 * leanMassKilograms,
                formula: .katchMcArdle,
                rationale: "Katch–McArdle uses the validated body-fat value to estimate lean mass."
            )
        }

        let sexConstant: Double
        switch input.biologicalSex {
        case .male: sexConstant = 5
        case .female: sexConstant = -161
        case .other, .notSet: sexConstant = -78
        }
        return BasalMetabolicRateEstimate(
            calories: 10 * input.weightKilograms
                + 6.25 * input.heightCentimeters
                - 5 * Double(input.age)
                + sexConstant,
            formula: .mifflinStJeor,
            rationale: input.biologicalSex == .other || input.biologicalSex == .notSet
                ? "Mifflin–St Jeor was used with a neutral midpoint because no binary metabolic constant was selected."
                : "Mifflin–St Jeor was used because a reliable body-fat value was not available."
        )
    }
}

