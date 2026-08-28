//
//  MuscleAssetNameResolver.swift
//  Pulsar
//

import UIKit

enum MuscleBodyAsset: Hashable {
    case base(isBack: Bool)
    case overlay(muscle: MuscleMatrixGroup, isBack: Bool)
}

enum MuscleAssetNameResolver {
    private static var availabilityByImageName: [String: Bool] = [:]

    static func imageName(for asset: MuscleBodyAsset) -> String? {
        switch asset {
        case .base(isBack: false):
            "body_front_base"
        case .base(isBack: true):
            "body_back_base"
        case .overlay(let muscle, isBack: false):
            switch muscle {
            case .chest: "body_front_chest_overlay"
            case .shoulders: "body_front_delts_overlay"
            case .biceps: "body_front_biceps_overlay"
            case .triceps: "body_front_triceps_overlay"
            case .core: "body_front_core_overlay"
            case .quads: "body_front_quads_overlay"
            case .calves: "body_front_calves_overlay"
            case .cardio: "body_front_cardio_overlay"
            case .back, .glutes, .hamstrings: nil
            }
        case .overlay(let muscle, isBack: true):
            switch muscle {
            case .back: "body_back_back_overlay"
            case .shoulders: "body_back_delts_overlay"
            case .triceps: "body_back_triceps_overlay"
            case .glutes: "body_back_glutes_overlay"
            case .hamstrings: "body_back_hamstrings_overlay"
            case .calves: "body_back_calves_overlay"
            case .cardio: "body_back_cardio_overlay"
            case .chest, .biceps, .core, .quads: nil
            }
        }
    }

    static func overlays(for isBack: Bool) -> [MuscleMatrixGroup] {
        MuscleMatrixGroup.allCases.filter {
            imageName(for: .overlay(muscle: $0, isBack: isBack)) != nil
        }
    }

    static func isAvailable(named imageName: String) -> Bool {
        if let cached = availabilityByImageName[imageName] {
            return cached
        }
        let isAvailable = UIImage(named: imageName) != nil
        availabilityByImageName[imageName] = isAvailable
        return isAvailable
    }

    static func missingOverlayAssets() -> [String] {
        overlays(for: false).compactMap { imageName(for: .overlay(muscle: $0, isBack: false)) }
            .filter { !isAvailable(named: $0) }
        + overlays(for: true).compactMap { imageName(for: .overlay(muscle: $0, isBack: true)) }
            .filter { !isAvailable(named: $0) }
    }
}
