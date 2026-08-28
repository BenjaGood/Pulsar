//
//  EstimatedEnergyRequirementCalculator.swift
//  Pulsar
//

import Foundation

enum NutritionPhysicalActivityLevel: String, Codable, Hashable {
    case inactive
    case lowActive
    case active
    case veryActive
}

struct EEREquationCoefficients: Equatable {
    var intercept: Double
    var age: Double
    var height: Double
    var weight: Double
}

struct EERMaintenanceEstimate: Equatable {
    var midpoint: Double
    var lowerBound: Double?
    var upperBound: Double?
    var combinedPAL: Double
    var dailyLifePAL: Double
    var workoutPALContribution: Double
    var equationUsed: String
    var rationale: String
}

struct EstimatedEnergyRequirementCalculator {
    static let methodologyVersion = "2023-dri-eer"

    static let palAnchors: [(pal: Double, level: NutritionPhysicalActivityLevel)] = [
        (1.40, .inactive),
        (1.60, .lowActive),
        (1.75, .active),
        (2.05, .veryActive)
    ]

    private static let maleCoefficients: [NutritionPhysicalActivityLevel: EEREquationCoefficients] = [
        .inactive: .init(intercept: 753.07, age: -10.83, height: 6.50, weight: 14.10),
        .lowActive: .init(intercept: 581.47, age: -10.83, height: 8.30, weight: 14.94),
        .active: .init(intercept: 1_004.82, age: -10.83, height: 6.52, weight: 15.91),
        .veryActive: .init(intercept: -517.88, age: -10.83, height: 15.61, weight: 19.11)
    ]

    private static let femaleCoefficients: [NutritionPhysicalActivityLevel: EEREquationCoefficients] = [
        .inactive: .init(intercept: 584.90, age: -7.01, height: 5.72, weight: 11.71),
        .lowActive: .init(intercept: 575.77, age: -7.01, height: 6.60, weight: 12.14),
        .active: .init(intercept: 710.25, age: -7.01, height: 6.54, weight: 12.34),
        .veryActive: .init(intercept: 511.83, age: -7.01, height: 9.07, weight: 12.56)
    ]

    func eer(
        sex: BiologicalSex,
        level: NutritionPhysicalActivityLevel,
        age: Int,
        heightCentimeters: Double,
        weightKilograms: Double
    ) -> Double {
        switch sex {
        case .male:
            return evaluate(Self.maleCoefficients[level]!, age: age, heightCentimeters: heightCentimeters, weightKilograms: weightKilograms)
        case .female:
            return evaluate(Self.femaleCoefficients[level]!, age: age, heightCentimeters: heightCentimeters, weightKilograms: weightKilograms)
        case .other, .notSet:
            let male = evaluate(Self.maleCoefficients[level]!, age: age, heightCentimeters: heightCentimeters, weightKilograms: weightKilograms)
            let female = evaluate(Self.femaleCoefficients[level]!, age: age, heightCentimeters: heightCentimeters, weightKilograms: weightKilograms)
            return (male + female) / 2
        }
    }

    func interpolatedEER(
        sex: BiologicalSex,
        pal: Double,
        age: Int,
        heightCentimeters: Double,
        weightKilograms: Double
    ) -> Double {
        let clampedPAL = min(max(pal, Self.palAnchors.first!.pal), Self.palAnchors.last!.pal)
        if clampedPAL <= Self.palAnchors[0].pal {
            return eer(sex: sex, level: Self.palAnchors[0].level, age: age, heightCentimeters: heightCentimeters, weightKilograms: weightKilograms)
        }
        for index in 0..<(Self.palAnchors.count - 1) {
            let lower = Self.palAnchors[index]
            let upper = Self.palAnchors[index + 1]
            if clampedPAL <= upper.pal {
                let span = upper.pal - lower.pal
                let fraction = span > 0 ? (clampedPAL - lower.pal) / span : 0
                let lowerEER = eer(sex: sex, level: lower.level, age: age, heightCentimeters: heightCentimeters, weightKilograms: weightKilograms)
                let upperEER = eer(sex: sex, level: upper.level, age: age, heightCentimeters: heightCentimeters, weightKilograms: weightKilograms)
                return lowerEER + (upperEER - lowerEER) * fraction
            }
        }
        return eer(sex: sex, level: Self.palAnchors.last!.level, age: age, heightCentimeters: heightCentimeters, weightKilograms: weightKilograms)
    }

    func estimate(
        input: NutritionCalculationInput,
        restingEnergy: Double,
        workoutPALContribution: Double
    ) -> EERMaintenanceEstimate {
        let dailyLifePAL = input.workoutPlan.dailyActivityLevel.palAnchor
        let combinedPAL = min(max(dailyLifePAL + workoutPALContribution, 1.0), 2.20)

        switch input.biologicalSex {
        case .male:
            let midpoint = interpolatedEER(
                sex: .male,
                pal: combinedPAL,
                age: input.age,
                heightCentimeters: input.heightCentimeters,
                weightKilograms: input.weightKilograms
            )
            return EERMaintenanceEstimate(
                midpoint: midpoint,
                lowerBound: nil,
                upperBound: nil,
                combinedPAL: combinedPAL,
                dailyLifePAL: dailyLifePAL,
                workoutPALContribution: workoutPALContribution,
                equationUsed: "2023 DRI EER (male)",
                rationale: "Maintenance uses the 2023 DRI adult EER equation with continuous PAL interpolation."
            )
        case .female:
            let midpoint = interpolatedEER(
                sex: .female,
                pal: combinedPAL,
                age: input.age,
                heightCentimeters: input.heightCentimeters,
                weightKilograms: input.weightKilograms
            )
            return EERMaintenanceEstimate(
                midpoint: midpoint,
                lowerBound: nil,
                upperBound: nil,
                combinedPAL: combinedPAL,
                dailyLifePAL: dailyLifePAL,
                workoutPALContribution: workoutPALContribution,
                equationUsed: "2023 DRI EER (female)",
                rationale: "Maintenance uses the 2023 DRI adult EER equation with continuous PAL interpolation."
            )
        case .other, .notSet:
            let male = interpolatedEER(
                sex: .male,
                pal: combinedPAL,
                age: input.age,
                heightCentimeters: input.heightCentimeters,
                weightKilograms: input.weightKilograms
            )
            let female = interpolatedEER(
                sex: .female,
                pal: combinedPAL,
                age: input.age,
                heightCentimeters: input.heightCentimeters,
                weightKilograms: input.weightKilograms
            )
            return EERMaintenanceEstimate(
                midpoint: (male + female) / 2,
                lowerBound: min(male, female),
                upperBound: max(male, female),
                combinedPAL: combinedPAL,
                dailyLifePAL: dailyLifePAL,
                workoutPALContribution: workoutPALContribution,
                equationUsed: "2023 DRI EER (male and female span)",
                rationale: "Published adult EER equations do not include separate non-binary coefficients; Pulsar uses the male and female equation span for the range and the midpoint for the provisional target."
            )
        }
    }

    private func evaluate(
        _ coefficients: EEREquationCoefficients,
        age: Int,
        heightCentimeters: Double,
        weightKilograms: Double
    ) -> Double {
        coefficients.intercept
            + coefficients.age * Double(age)
            + coefficients.height * heightCentimeters
            + coefficients.weight * weightKilograms
    }
}
