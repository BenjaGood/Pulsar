//
//  PulsarRunDerivedMetricsTests.swift
//  PulsarTests
//

import Testing
@testable import Pulsar

struct PulsarRunDerivedMetricsTests {
    @Test func durationFormatterDistinguishesHours() {
        #expect(PulsarRunFormatters.duration(65) == "01:05")
        #expect(PulsarRunFormatters.duration(3_725) == "1:02:05")
    }

    @Test func paceFormatterUsesKilometerPace() {
        #expect(PulsarRunFormatters.pace(301) == "5:01 /km")
        #expect(PulsarRunFormatters.pace(nil) == "--")
    }

    @Test func autoPauseIgnoresPoorAccuracy() {
        #expect(PulsarRunDerivedMetrics.shouldAutoPause(speedMetersPerSecond: 0.2, horizontalAccuracy: 12))
        #expect(!PulsarRunDerivedMetrics.shouldAutoPause(speedMetersPerSecond: 0.2, horizontalAccuracy: 80))
        #expect(!PulsarRunDerivedMetrics.shouldAutoPause(speedMetersPerSecond: 1.4, horizontalAccuracy: 12))
    }

    @Test func elevationGainRequiresMeaningfulPositiveChange() {
        #expect(PulsarRunDerivedMetrics.elevationGain(previousAltitude: 100, nextAltitude: 101.0, verticalAccuracy: 4) == 0)
        #expect(PulsarRunDerivedMetrics.elevationGain(previousAltitude: 100, nextAltitude: 102.1, verticalAccuracy: 4) > 2)
        #expect(PulsarRunDerivedMetrics.elevationGain(previousAltitude: 100, nextAltitude: 105, verticalAccuracy: 40) == 0)
    }
}
