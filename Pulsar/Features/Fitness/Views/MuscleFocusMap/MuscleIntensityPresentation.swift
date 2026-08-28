//
//  MuscleIntensityPresentation.swift
//  Pulsar
//

import CoreGraphics
import Foundation

/// Visual tuning for baked-color muscle overlays.
/// Keeps overlays integrated and anatomical instead of bright sticker layers.
struct MuscleIntensityPresentation: Hashable {
    var coreOpacity: Double
    var bloomOpacity: Double
    var bloomRadius: CGFloat

    static func presentation(
        for intensity: MuscleIntensity,
        muscle: MuscleMatrixGroup
    ) -> MuscleIntensityPresentation {
        guard intensity != .none else {
            return MuscleIntensityPresentation(coreOpacity: 0, bloomOpacity: 0, bloomRadius: 0)
        }

        if muscle == .cardio {
            return cardioPresentation(for: intensity)
        }

        return switch intensity {
        case .none:
            MuscleIntensityPresentation(coreOpacity: 0, bloomOpacity: 0, bloomRadius: 0)
        case .light:
            MuscleIntensityPresentation(coreOpacity: 0.34, bloomOpacity: 0.05, bloomRadius: 1.5)
        case .medium:
            MuscleIntensityPresentation(coreOpacity: 0.46, bloomOpacity: 0.08, bloomRadius: 2.5)
        case .high:
            MuscleIntensityPresentation(coreOpacity: 0.56, bloomOpacity: 0.10, bloomRadius: 3.5)
        }
    }

    private static func cardioPresentation(for intensity: MuscleIntensity) -> MuscleIntensityPresentation {
        switch intensity {
        case .none:
            MuscleIntensityPresentation(coreOpacity: 0, bloomOpacity: 0, bloomRadius: 0)
        case .light:
            MuscleIntensityPresentation(coreOpacity: 0.16, bloomOpacity: 0.05, bloomRadius: 1.5)
        case .medium:
            MuscleIntensityPresentation(coreOpacity: 0.22, bloomOpacity: 0.07, bloomRadius: 2)
        case .high:
            MuscleIntensityPresentation(coreOpacity: 0.28, bloomOpacity: 0.09, bloomRadius: 2.5)
        }
    }
}
