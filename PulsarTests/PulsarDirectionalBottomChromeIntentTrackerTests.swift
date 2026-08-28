//
//  PulsarDirectionalBottomChromeIntentTrackerTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

struct PulsarDirectionalBottomChromeIntentTrackerTests {
    @Test func lessThanTwentyTwoPointsOfUpwardTravelDoesNothing() {
        var tracker = PulsarDirectionalBottomChromeIntentTracker()

        #expect(tracker.drive(translations: [0, -80, -70, -59]) == .none)
        #expect(!tracker.hasLatchedExpansion)
    }

    @Test func tinyJitterNeverExpands() {
        var tracker = PulsarDirectionalBottomChromeIntentTracker()
        var lastIntent = PulsarDirectionalBottomChromeIntent.none

        lastIntent = tracker.update(
            translationY: 0,
            phase: .began,
            context: .eligibleCompactHomeOrion
        )
        #expect(lastIntent == .none)

        for translation in [0, -1, 0, 1, 0, -1, 1, -1] {
            lastIntent = tracker.update(
                translationY: CGFloat(translation),
                phase: .changed,
                context: .eligibleCompactHomeOrion
            )
            #expect(lastIntent == .none)
        }
        #expect(!tracker.hasLatchedExpansion)
    }

    @Test func longDownwardGestureThenTwentyTwoPointReversalExpandsOnce() {
        var tracker = PulsarDirectionalBottomChromeIntentTracker()

        #expect(tracker.drive(translations: [0, -40, -120, -180]) == .none)
        #expect(
            tracker.update(
                translationY: -159,
                phase: .changed,
                context: .eligibleCompactHomeOrion
            ) == .none
        )

        let firstCrossing = tracker.update(
            translationY: -158,
            phase: .changed,
            context: .eligibleCompactHomeOrion
        )
        #expect(firstCrossing == .expand)
        #expect(tracker.hasLatchedExpansion)

        #expect(
            tracker.update(
                translationY: -140,
                phase: .changed,
                context: .eligibleCompactHomeOrion
            ) == .none
        )
        #expect(
            tracker.update(
                translationY: -100,
                phase: .changed,
                context: .eligibleCompactHomeOrion
            ) == .none
        )
    }

    @Test func fiftyToOneHundredPointUpwardReversalExpandsFarFromTheTop() {
        var tracker = PulsarDirectionalBottomChromeIntentTracker()

        #expect(tracker.drive(translations: [0, -220, -410]) == .none)
        #expect(
            tracker.update(
                translationY: -330,
                phase: .changed,
                context: .eligibleCompactHomeOrion
            ) == .expand
        )
    }

    @Test func pureUpwardGestureFarFromTheTopStillExpands() {
        var tracker = PulsarDirectionalBottomChromeIntentTracker()

        #expect(tracker.drive(translations: [0, 12, 21]) == .none)
        #expect(
            tracker.update(
                translationY: 50,
                phase: .changed,
                context: .eligibleCompactHomeOrion
            ) == .expand
        )
    }

    @Test func ineligibleTabsAndAccessoriesDoNotTrigger() {
        var fitnessTracker = PulsarDirectionalBottomChromeIntentTracker()
        #expect(
            fitnessTracker.drive(
                translations: [0, -80, 40],
                context: PulsarDirectionalBottomChromeIntentContext(
                    isHomeSelected: false,
                    isOrionAccessory: true,
                    isCompact: true
                )
            ) == .none
        )

        var workoutTracker = PulsarDirectionalBottomChromeIntentTracker()
        #expect(
            workoutTracker.drive(
                translations: [0, -80, 40],
                context: PulsarDirectionalBottomChromeIntentContext(
                    isHomeSelected: true,
                    isOrionAccessory: false,
                    isCompact: true
                )
            ) == .none
        )

        var expandedTracker = PulsarDirectionalBottomChromeIntentTracker()
        #expect(
            expandedTracker.drive(
                translations: [0, -80, 40],
                context: PulsarDirectionalBottomChromeIntentContext(
                    isHomeSelected: true,
                    isOrionAccessory: true,
                    isCompact: false
                )
            ) == .none
        )
    }

    @Test func resetGestureAllowsALaterExpansion() {
        var tracker = PulsarDirectionalBottomChromeIntentTracker()

        #expect(tracker.drive(translations: [0, -90, -60]) == .expand)
        #expect(
            tracker.update(
                translationY: -60,
                phase: .ended,
                context: .eligibleCompactHomeOrion
            ) == .none
        )
        #expect(!tracker.hasLatchedExpansion)

        #expect(tracker.drive(translations: [0, -40, 0]) == .expand)
    }

    @Test func cancelledGestureClearsLatchWithoutExpanding() {
        var tracker = PulsarDirectionalBottomChromeIntentTracker()

        #expect(tracker.drive(translations: [0, -30, -20]) == .none)
        #expect(
            tracker.update(
                translationY: -20,
                phase: .cancelled,
                context: .eligibleCompactHomeOrion
            ) == .none
        )
        #expect(!tracker.hasLatchedExpansion)
    }

    @Test func repeatedUpdatesAfterResetWithoutTravelDoNotTrigger() {
        var tracker = PulsarDirectionalBottomChromeIntentTracker()

        #expect(tracker.drive(translations: [0, -90, -60]) == .expand)
        tracker.reset()

        #expect(
            tracker.update(
                translationY: 0,
                phase: .began,
                context: .eligibleCompactHomeOrion
            ) == .none
        )
        #expect(
            tracker.update(
                translationY: 0,
                phase: .changed,
                context: .eligibleCompactHomeOrion
            ) == .none
        )
        #expect(
            tracker.update(
                translationY: 1,
                phase: .changed,
                context: .eligibleCompactHomeOrion
            ) == .none
        )
    }
}

private extension PulsarDirectionalBottomChromeIntentTracker {
    mutating func drive(
        translations: [CGFloat],
        context: PulsarDirectionalBottomChromeIntentContext = .eligibleCompactHomeOrion
    ) -> PulsarDirectionalBottomChromeIntent {
        var lastIntent = PulsarDirectionalBottomChromeIntent.none
        for (index, translation) in translations.enumerated() {
            let phase: PulsarDirectionalPanPhase = index == 0 ? .began : .changed
            let intent = update(translationY: translation, phase: phase, context: context)
            if intent == .expand {
                lastIntent = .expand
            }
        }
        return lastIntent
    }
}
