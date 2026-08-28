//
//  OutdoorWorkoutAudioCueTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

struct OutdoorWorkoutAudioCueTests {
    @Test func milestoneDetectionDoesNotCueBeforeFirstKilometer() {
        var tracker = OutdoorWorkoutAudioCueMilestoneTracker()
        let events = tracker.consume(distanceMeters: 999, shouldAnnounce: true)
        #expect(events.isEmpty)
        #expect(tracker.lastAnnouncedKilometer == 0)
    }

    @Test func milestoneDetectionCuesExactlyAtOneKilometer() {
        var tracker = OutdoorWorkoutAudioCueMilestoneTracker()
        let events = tracker.consume(distanceMeters: 1_000, shouldAnnounce: true)
        #expect(events == [1])
        #expect(tracker.lastAnnouncedKilometer == 1)
    }

    @Test func milestoneDetectionIgnoresDuplicatePastBoundary() {
        var tracker = OutdoorWorkoutAudioCueMilestoneTracker()
        _ = tracker.consume(distanceMeters: 1_000, shouldAnnounce: true)
        let duplicate = tracker.consume(distanceMeters: 1_001, shouldAnnounce: true)
        let stillFirst = tracker.consume(distanceMeters: 1_999, shouldAnnounce: true)
        #expect(duplicate.isEmpty)
        #expect(stillFirst.isEmpty)
        #expect(tracker.lastAnnouncedKilometer == 1)
    }

    @Test func milestoneDetectionCuesSecondKilometer() {
        var tracker = OutdoorWorkoutAudioCueMilestoneTracker()
        _ = tracker.consume(distanceMeters: 1_000, shouldAnnounce: true)
        let events = tracker.consume(distanceMeters: 2_000, shouldAnnounce: true)
        #expect(events == [2])
        #expect(tracker.lastAnnouncedKilometer == 2)
    }

    @Test func milestoneDetectionHandlesMultiKilometerJump() {
        var tracker = OutdoorWorkoutAudioCueMilestoneTracker()
        let events = tracker.consume(distanceMeters: 2_050, shouldAnnounce: true)
        #expect(events == [1, 2])
        #expect(tracker.lastAnnouncedKilometer == 2)

        var fromNearBoundary = OutdoorWorkoutAudioCueMilestoneTracker()
        _ = fromNearBoundary.consume(distanceMeters: 950, shouldAnnounce: true)
        let jumped = fromNearBoundary.consume(distanceMeters: 2_050, shouldAnnounce: true)
        #expect(jumped == [1, 2])
    }

    @Test func restoredWorkoutDoesNotReplayCompletedKilometers() {
        var tracker = OutdoorWorkoutAudioCueMilestoneTracker()
        tracker.restore(completedKilometerCount: 5)
        tracker.restore(distanceMeters: 5_400)
        let events = tracker.consume(distanceMeters: 5_400, shouldAnnounce: true)
        #expect(events.isEmpty)
        #expect(tracker.lastAnnouncedKilometer == 5)

        let next = tracker.consume(distanceMeters: 6_000, shouldAnnounce: true)
        #expect(next == [6])
    }

    @Test func disabledSettingProducesNoCueButStillAdvances() {
        var tracker = OutdoorWorkoutAudioCueMilestoneTracker()
        let events = tracker.consume(distanceMeters: 1_000, shouldAnnounce: false)
        #expect(events.isEmpty)
        #expect(tracker.lastAnnouncedKilometer == 1)

        let afterReenable = tracker.consume(distanceMeters: 2_000, shouldAnnounce: true)
        #expect(afterReenable == [2])
    }

    @Test func completedWorkoutProducesNoFurtherCuesAfterReset() {
        var tracker = OutdoorWorkoutAudioCueMilestoneTracker()
        _ = tracker.consume(distanceMeters: 3_000, shouldAnnounce: true)
        tracker.reset()
        #expect(tracker.lastAnnouncedKilometer == 0)
    }

    @Test func splitConsumeUsesSplitPaceAndSkipsDuplicates() {
        var tracker = OutdoorWorkoutAudioCueMilestoneTracker()
        let first = PulsarRunSplit(
            index: 1,
            distanceMeters: 1_000,
            movingTime: 222,
            elevationGainMeters: 0,
            averageHeartRate: nil
        )
        let second = PulsarRunSplit(
            index: 2,
            distanceMeters: 1_000,
            movingTime: 210,
            elevationGainMeters: 0,
            averageHeartRate: nil
        )

        let firstEvents = tracker.consume(completedSplits: [first], shouldAnnounce: true)
        #expect(firstEvents.count == 1)
        #expect(firstEvents[0].kilometer == 1)
        #expect(firstEvents[0].paceSecondsPerKilometer == 222)

        let duplicate = tracker.consume(completedSplits: [first, second], shouldAnnounce: true)
        #expect(duplicate.count == 1)
        #expect(duplicate[0].kilometer == 2)
        #expect(duplicate[0].paceSecondsPerKilometer == 210)

        let again = tracker.consume(completedSplits: [first, second], shouldAnnounce: true)
        #expect(again.isEmpty)
    }

    @Test func splitPaceMatchesMovingTimeModel() {
        let split = PulsarRunSplit(
            index: 1,
            distanceMeters: 1_000,
            movingTime: 222,
            elevationGainMeters: 0,
            averageHeartRate: nil
        )
        #expect(split.paceSecondsPerKilometer == 222)

        let pausedSplit = PulsarRunSplit(
            index: 2,
            distanceMeters: 1_000,
            movingTime: 300,
            elevationGainMeters: 0,
            averageHeartRate: nil
        )
        #expect(pausedSplit.paceSecondsPerKilometer == 300)
    }

    @Test func invalidSplitPaceIsRejectedByPhraseBuilder() {
        #expect(OutdoorWorkoutAudioCuePhraseBuilder.paceDescription(secondsPerKilometer: 0) == nil)
        #expect(OutdoorWorkoutAudioCuePhraseBuilder.paceDescription(secondsPerKilometer: -10) == nil)
        #expect(OutdoorWorkoutAudioCuePhraseBuilder.kilometerSplitPhrase(kilometer: 1, paceSecondsPerKilometer: nil) == nil)
    }

    @Test func paceFormattingHandlesCarryAndLongDurations() {
        let almostMinute = OutdoorWorkoutAudioCuePhraseBuilder.paceDescription(secondsPerKilometer: 59.6)
        #expect(almostMinute == "1 minute 0 seconds per kilometer")

        let longPace = OutdoorWorkoutAudioCuePhraseBuilder.paceDescription(secondsPerKilometer: 642)
        #expect(longPace == "10 minutes 42 seconds per kilometer")

        let phrase = OutdoorWorkoutAudioCuePhraseBuilder.kilometerSplitPhrase(
            kilometer: 1,
            paceSecondsPerKilometer: 222
        )
        #expect(phrase == "Kilometer 1. Pace: 3 minutes 42 seconds per kilometer.")
    }

    @Test func multiSplitJumpProducesOrderedEvents() {
        var tracker = OutdoorWorkoutAudioCueMilestoneTracker()
        let splits = [
            PulsarRunSplit(index: 1, distanceMeters: 1_000, movingTime: 200, elevationGainMeters: 0, averageHeartRate: nil),
            PulsarRunSplit(index: 2, distanceMeters: 1_000, movingTime: 210, elevationGainMeters: 0, averageHeartRate: nil)
        ]
        let events = tracker.consume(completedSplits: splits, shouldAnnounce: true)
        #expect(events.map(\.kilometer) == [1, 2])
        #expect(events.map(\.paceSecondsPerKilometer) == [200, 210])
    }
}
