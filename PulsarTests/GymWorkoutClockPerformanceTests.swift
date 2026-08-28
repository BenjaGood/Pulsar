//
//  GymWorkoutClockPerformanceTests.swift
//  PulsarTests
//

import Testing
@testable import Pulsar

@MainActor
struct GymWorkoutClockPerformanceTests {
    @Test func elapsedAndRestCadenceStayInTheDedicatedClock() {
        let clock = GymWorkoutSessionClock()

        clock.updateElapsedSeconds(42)
        clock.startRest(totalSeconds: 90)
        clock.updateRestCountdown(45)

        #expect(clock.elapsedSeconds == 42)
        #expect(clock.restCountdownSeconds == 45)
        #expect(clock.restTotalSeconds == 90)
        #expect(clock.restProgressFraction == 0.5)

        clock.clearRest()

        #expect(clock.elapsedSeconds == 42)
        #expect(clock.restCountdownSeconds == nil)
        #expect(clock.restTotalSeconds == nil)
    }
}
