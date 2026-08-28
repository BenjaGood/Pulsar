//
//  MuscleOverlayPlacementTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

struct MuscleOverlayPlacementTests {
    @Test func frontChestFitsInsideThePectoralRegion() {
        let placement = MuscleOverlayPlacement.placement(for: .chest, isBack: false)

        #expect(placement.scale <= 0.60)
        #expect(placement.bilateralInward > 0.02)
        #expect(placement.offsetY <= -0.04)
    }

    @Test func frontCoreAndCalvesAreRegisteredToTheirAnatomy() {
        let core = MuscleOverlayPlacement.placement(for: .core, isBack: false)
        let placement = MuscleOverlayPlacement.placement(for: .calves, isBack: false)

        #expect(core.scale <= 0.55)
        #expect(core.offsetY <= -0.10)
        #expect(placement.scale <= 0.65)
        #expect(placement.offsetY >= 0.14)
    }

    @Test func backLegPassesAreScaledAndShiftedDown() {
        let placement = MuscleOverlayPlacement.placement(for: .hamstrings, isBack: true)
        let calves = MuscleOverlayPlacement.placement(for: .calves, isBack: true)

        #expect(placement.scale <= 0.60)
        #expect(placement.offsetY >= 0.10)
        #expect(calves.scale <= 0.65)
        #expect(calves.offsetY >= 0.06)
    }

    @Test func everyMappedMuscleHasExplicitPlacement() {
        let frontMuscles: [MuscleMatrixGroup] = [.chest, .shoulders, .biceps, .triceps, .core, .quads, .calves]
        let backMuscles: [MuscleMatrixGroup] = [.back, .shoulders, .triceps, .glutes, .hamstrings, .calves]

        for muscle in frontMuscles {
            let placement = MuscleOverlayPlacement.placement(for: muscle, isBack: false)
            #expect(placement.scale > 0.5)
            #expect(placement.scale <= 1.0)
        }

        for muscle in backMuscles {
            let placement = MuscleOverlayPlacement.placement(for: muscle, isBack: true)
            #expect(placement.scale > 0.5)
            #expect(placement.scale <= 1.0)
        }
    }
}
