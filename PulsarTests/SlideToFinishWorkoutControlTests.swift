//
//  SlideToFinishWorkoutControlTests.swift
//  PulsarTests
//

import CoreGraphics
import Testing
@testable import Pulsar

@MainActor
struct SlideToFinishWorkoutControlTests {
    @Test func normalizedProgressClampsToTrackBounds() {
        #expect(SlideToFinishWorkoutControl.normalizedProgress(translation: -20, maximumTravel: 200) == 0)
        #expect(SlideToFinishWorkoutControl.normalizedProgress(translation: 100, maximumTravel: 200) == 0.5)
        #expect(SlideToFinishWorkoutControl.normalizedProgress(translation: 260, maximumTravel: 200) == 1)
    }

    @Test func normalizedProgressIsSafeBeforeLayout() {
        #expect(SlideToFinishWorkoutControl.normalizedProgress(translation: 80, maximumTravel: 0) == 0)
    }

    @Test func translationClampsWithoutResistanceOrOvershoot() {
        #expect(SlideToFinishWorkoutControl.clampedTranslation(-1, maximumTravel: 200) == 0)
        #expect(SlideToFinishWorkoutControl.clampedTranslation(88, maximumTravel: 200) == 88)
        #expect(SlideToFinishWorkoutControl.clampedTranslation(240, maximumTravel: 200) == 200)
    }

    @Test func completionRequiresAIntentionalNearEndDrag() {
        #expect(SlideToFinishWorkoutControl.completionThreshold >= 0.85)
        #expect(SlideToFinishWorkoutControl.completionThreshold <= 0.90)
    }
}
