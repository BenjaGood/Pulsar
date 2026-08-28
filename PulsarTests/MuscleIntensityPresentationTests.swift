//
//  MuscleIntensityPresentationTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

struct MuscleIntensityPresentationTests {
    @Test func muscleOpacityStaysRestrainedAtHighIntensity() {
        let presentation = MuscleIntensityPresentation.presentation(for: .high, muscle: .chest)

        #expect(presentation.coreOpacity <= 0.60)
        #expect(presentation.bloomOpacity <= 0.15)
        #expect(presentation.bloomRadius <= 5)
    }

    @Test func cardioOpacityIsMoreSubtleThanStrengthMuscles() {
        let chest = MuscleIntensityPresentation.presentation(for: .high, muscle: .chest)
        let cardio = MuscleIntensityPresentation.presentation(for: .high, muscle: .cardio)

        #expect(cardio.coreOpacity < chest.coreOpacity)
        #expect(cardio.bloomOpacity < chest.bloomOpacity)
    }

    @Test func noneIntensityHidesOverlayPasses() {
        let presentation = MuscleIntensityPresentation.presentation(for: .none, muscle: .quads)

        #expect(presentation.coreOpacity == 0)
        #expect(presentation.bloomOpacity == 0)
        #expect(presentation.bloomRadius == 0)
    }
}
