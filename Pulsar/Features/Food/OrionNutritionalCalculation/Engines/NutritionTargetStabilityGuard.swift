//
//  NutritionTargetStabilityGuard.swift
//  Pulsar
//

import Foundation

struct NutritionTargetChangeAssessment: Equatable {
    var requiresConfirmation: Bool
    var previousTargetCalories: Double?
    var proposedTargetCalories: Double
    var deltaCalories: Double
    var deltaPercent: Double
    var reasons: [String]
}

struct NutritionTargetStabilityGuard {
    static func roundToNearest25(_ value: Double) -> Double {
        (value / 25).rounded() * 25
    }

    static func maintenanceConfidenceRange(
        maintenance: Double,
        confidence: NutritionDataConfidence
    ) -> ClosedRange<Double> {
        let fraction: Double
        switch confidence {
        case .high: fraction = 0.10
        case .moderate: fraction = 0.15
        case .low: fraction = 0.20
        }
        return (maintenance * (1 - fraction))...(maintenance * (1 + fraction))
    }

    static func practicalTargetRange(for target: Double) -> ClosedRange<Double> {
        let margin = max(100, target * 0.05)
        return (target - margin)...(target + margin)
    }

    func assessChange(
        proposedTarget: Double,
        previousTarget: Double?,
        reasons: [String]
    ) -> NutritionTargetChangeAssessment {
        guard let previousTarget, previousTarget > 0 else {
            return NutritionTargetChangeAssessment(
                requiresConfirmation: false,
                previousTargetCalories: previousTarget,
                proposedTargetCalories: proposedTarget,
                deltaCalories: 0,
                deltaPercent: 0,
                reasons: reasons
            )
        }
        let delta = proposedTarget - previousTarget
        let deltaPercent = abs(delta) / previousTarget
        let threshold = min(250, previousTarget * 0.10)
        let requiresConfirmation = abs(delta) > threshold
        return NutritionTargetChangeAssessment(
            requiresConfirmation: requiresConfirmation,
            previousTargetCalories: previousTarget,
            proposedTargetCalories: proposedTarget,
            deltaCalories: delta,
            deltaPercent: deltaPercent,
            reasons: reasons
        )
    }
}
