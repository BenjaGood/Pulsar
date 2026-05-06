//
//  ProfileStore.swift
//  Pulsar
//

import Combine
import Foundation

@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profile: UserProfile

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let storageKey = "pulsar.profile.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey), let decoded = try? decoder.decode(UserProfile.self, from: data) {
            self.profile = decoded
        } else {
            self.profile = .empty
        }
    }

    func update(_ edit: (inout UserProfile) -> Void) {
        edit(&profile)
        profile.lastUpdated = Date()
        save()
    }

    func save(_ profile: UserProfile) {
        var profileToSave = profile
        profileToSave.lastUpdated = Date()
        self.profile = profileToSave
        save()
    }

    func resetLocalProfile() {
        profile = .empty
        save()
    }

    func mergeHealthKitProfile(heightCentimeters: Double?, weightKilograms: Double?, dateOfBirth: Date?, biologicalSex: BiologicalSex?) {
        profile.healthKitHeightCentimeters = heightCentimeters
        profile.healthKitWeightKilograms = weightKilograms
        profile.healthKitDateOfBirth = dateOfBirth
        profile.healthKitBiologicalSex = biologicalSex
        profile.lastUpdated = Date()
        save()
    }

    private func save() {
        guard let data = try? encoder.encode(profile) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
