//
//  MuscleAssetNameResolverTests.swift
//  PulsarTests
//

import Testing
@testable import Pulsar

struct MuscleAssetNameResolverTests {
    @Test func baseAssetsResolveForBothOrientations() {
        #expect(MuscleAssetNameResolver.imageName(for: .base(isBack: false)) == "body_front_base")
        #expect(MuscleAssetNameResolver.imageName(for: .base(isBack: true)) == "body_back_base")
    }

    @Test func overlaysResolveToTheirAnatomicallyCorrectOrientation() {
        #expect(MuscleAssetNameResolver.imageName(for: .overlay(muscle: .chest, isBack: false)) == "body_front_chest_overlay")
        #expect(MuscleAssetNameResolver.imageName(for: .overlay(muscle: .chest, isBack: true)) == nil)
        #expect(MuscleAssetNameResolver.imageName(for: .overlay(muscle: .back, isBack: false)) == nil)
        #expect(MuscleAssetNameResolver.imageName(for: .overlay(muscle: .back, isBack: true)) == "body_back_back_overlay")
        #expect(MuscleAssetNameResolver.imageName(for: .overlay(muscle: .shoulders, isBack: false)) == "body_front_delts_overlay")
        #expect(MuscleAssetNameResolver.imageName(for: .overlay(muscle: .shoulders, isBack: true)) == "body_back_delts_overlay")
        #expect(MuscleAssetNameResolver.imageName(for: .overlay(muscle: .biceps, isBack: false)) == "body_front_biceps_overlay")
        #expect(MuscleAssetNameResolver.imageName(for: .overlay(muscle: .biceps, isBack: true)) == nil)
        #expect(MuscleAssetNameResolver.imageName(for: .overlay(muscle: .triceps, isBack: false)) == "body_front_triceps_overlay")
        #expect(MuscleAssetNameResolver.imageName(for: .overlay(muscle: .triceps, isBack: true)) == "body_back_triceps_overlay")
        #expect(MuscleAssetNameResolver.imageName(for: .overlay(muscle: .core, isBack: false)) == "body_front_core_overlay")
        #expect(MuscleAssetNameResolver.imageName(for: .overlay(muscle: .core, isBack: true)) == nil)
        #expect(MuscleAssetNameResolver.imageName(for: .overlay(muscle: .glutes, isBack: false)) == nil)
        #expect(MuscleAssetNameResolver.imageName(for: .overlay(muscle: .glutes, isBack: true)) == "body_back_glutes_overlay")
        #expect(MuscleAssetNameResolver.imageName(for: .overlay(muscle: .quads, isBack: false)) == "body_front_quads_overlay")
        #expect(MuscleAssetNameResolver.imageName(for: .overlay(muscle: .quads, isBack: true)) == nil)
        #expect(MuscleAssetNameResolver.imageName(for: .overlay(muscle: .hamstrings, isBack: false)) == nil)
        #expect(MuscleAssetNameResolver.imageName(for: .overlay(muscle: .hamstrings, isBack: true)) == "body_back_hamstrings_overlay")
        #expect(MuscleAssetNameResolver.imageName(for: .overlay(muscle: .calves, isBack: false)) == "body_front_calves_overlay")
        #expect(MuscleAssetNameResolver.imageName(for: .overlay(muscle: .calves, isBack: true)) == "body_back_calves_overlay")
        #expect(MuscleAssetNameResolver.imageName(for: .overlay(muscle: .cardio, isBack: false)) == "body_front_cardio_overlay")
        #expect(MuscleAssetNameResolver.imageName(for: .overlay(muscle: .cardio, isBack: true)) == "body_back_cardio_overlay")
    }

    @Test func declaredOverlaySetsMatchTheResolver() {
        #expect(MuscleAssetNameResolver.overlays(for: false) == [.chest, .shoulders, .biceps, .triceps, .core, .quads, .calves, .cardio])
        #expect(MuscleAssetNameResolver.overlays(for: true) == [.back, .shoulders, .triceps, .glutes, .hamstrings, .calves, .cardio])
    }
}
