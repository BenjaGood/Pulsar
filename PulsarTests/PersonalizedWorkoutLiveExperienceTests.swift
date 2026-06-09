//
//  PersonalizedWorkoutLiveExperienceTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

struct PersonalizedWorkoutLiveExperienceTests {
    @Test func indoorRunningIsPersonalizedButNotOutdoor() {
        #expect(PersonalizedWorkoutKind.allCases.contains(.indoorRunning))
        #expect(PersonalizedWorkoutKind.indoorRunning.title == "Indoor Running")
        #expect(PersonalizedWorkoutKind.indoorRunning.outdoorWorkoutKind == nil)
        #expect(WorkoutOption.personalized.contains { $0.personalizedKind == .indoorRunning })
    }

    @Test func heartRateZonesUseManualMaxHeartRate() {
        var profile = UserProfile.empty
        profile.manualMaxHeartRate = 190

        let zoneProfile = PulsarHeartRateZoneProfile(profile: profile)
        let zone3 = zoneProfile.zones.first { $0.number == 3 }

        #expect(zoneProfile.maxHeartRate == 190)
        #expect(zoneProfile.maxHeartRateSource == .manual)
        #expect(zone3?.lowerBound == 133)
        #expect(zone3?.upperBound == 152)
        #expect(zoneProfile.zone(for: 148)?.number == 3)
        #expect(Int((zoneProfile.percentOfMax(for: 148) ?? 0) * 100) == 77)
    }

    @Test func heartRateZonesFallBackToTwoTwentyMinusAge() {
        var profile = UserProfile.empty
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 6, day: 5))!
        profile.dateOfBirth = calendar.date(from: DateComponents(year: 1996, month: 6, day: 5))

        let zoneProfile = PulsarHeartRateZoneProfile(profile: profile, date: date, calendar: calendar)

        #expect(zoneProfile.maxHeartRate == 190)
        #expect(zoneProfile.maxHeartRateSource == .ageFormula)
        #expect(zoneProfile.zone(for: 171)?.number == 5)
    }

    @Test func heartRateZonesDoNotGuessWhenProfileIsMissing() {
        let zoneProfile = PulsarHeartRateZoneProfile(profile: .empty)

        #expect(zoneProfile.maxHeartRate == nil)
        #expect(zoneProfile.maxHeartRateSource == .unavailable)
        #expect(zoneProfile.zone(for: 148) == nil)
        #expect(zoneProfile.percentOfMax(for: 148) == nil)
    }
}
