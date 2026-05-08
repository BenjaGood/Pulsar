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
    private let alarmScheduler: AlarmScheduler?
    private let watchSyncStore: PulsarWatchConnectivitySyncStore?
    private let sideEffectsEnabled: Bool

    init(
        defaults: UserDefaults = .standard,
        alarmScheduler: AlarmScheduler? = .shared,
        watchSyncStore: PulsarWatchConnectivitySyncStore? = .shared,
        sideEffectsEnabled: Bool = true
    ) {
        self.defaults = defaults
        self.alarmScheduler = alarmScheduler
        self.watchSyncStore = watchSyncStore
        self.sideEffectsEnabled = sideEffectsEnabled
        if let data = defaults.data(forKey: storageKey), let decoded = try? decoder.decode(UserProfile.self, from: data) {
            self.profile = decoded
        } else {
            self.profile = .empty
        }
        if sideEffectsEnabled {
            refreshSleepPreferenceSideEffects(reason: "profileStoreInit")
        }
    }

    func update(_ edit: (inout UserProfile) -> Void) {
        let previousProfile = profile
        edit(&profile)
        profile.lastUpdated = Date()
        save(previousProfile: previousProfile, reason: "profileStoreUpdate")
    }

    func save(_ profile: UserProfile) {
        let previousProfile = self.profile
        var profileToSave = profile
        profileToSave.lastUpdated = Date()
        self.profile = profileToSave
        save(previousProfile: previousProfile, reason: "profileStoreSave")
    }

    func resetLocalProfile() {
        let previousProfile = profile
        profile = .empty
        save(previousProfile: previousProfile, reason: "profileStoreReset")
    }

    func mergeHealthKitProfile(heightCentimeters: Double?, weightKilograms: Double?, dateOfBirth: Date?, biologicalSex: BiologicalSex?) {
        let previousProfile = profile
        profile.healthKitHeightCentimeters = heightCentimeters
        profile.healthKitWeightKilograms = weightKilograms
        profile.healthKitDateOfBirth = dateOfBirth
        profile.healthKitBiologicalSex = biologicalSex
        profile.lastUpdated = Date()
        save(previousProfile: previousProfile, reason: "profileStoreHealthKitMerge")
    }

    func refreshSleepPreferenceSideEffects(reason: String = "profileStoreRefresh") {
        guard sideEffectsEnabled else { return }
        syncSleepPreferenceSideEffects(previousProfile: nil, reason: reason, force: true)
    }

    private func save(previousProfile: UserProfile?, reason: String) {
        guard let data = try? encoder.encode(profile) else { return }
        defaults.set(data, forKey: storageKey)
        syncSleepPreferenceSideEffects(previousProfile: previousProfile, reason: reason)
    }

    private func syncSleepPreferenceSideEffects(previousProfile: UserProfile?, reason: String, force: Bool = false) {
        guard sideEffectsEnabled else { return }
        let currentFingerprint = SleepPreferenceFingerprint(profile: profile)
        if !force, let previousProfile, SleepPreferenceFingerprint(profile: previousProfile) == currentFingerprint {
            return
        }
        let currentProfile = profile
        Task { [alarmScheduler, watchSyncStore] in
            await alarmScheduler?.sync(with: currentProfile)
            watchSyncStore?.storeSleepPreferences(for: currentProfile, broadcast: true, reason: reason)
        }
    }
}

private struct SleepPreferenceFingerprint: Equatable {
    var schedule: SleepSchedule
    var sleepGoalDays: SleepGoalDays

    init(profile: UserProfile) {
        self.schedule = profile.sleepSchedule
        self.sleepGoalDays = profile.sleepGoalDays
    }
}
