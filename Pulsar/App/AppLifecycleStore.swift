//
//  AppLifecycleStore.swift
//  Pulsar
//

import Foundation

struct AppLifecycleStore {
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let firstLaunchDateKey = "pulsar.lifecycle.firstLaunchDate.v1"
    private let firstStrainSyncDateKey = "pulsar.lifecycle.firstStrainSyncDate.v1"
    private let healthKitOnboardingKey = "pulsar.lifecycle.healthKitOnboarding.v1"

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    var firstLaunchDate: Date {
        if let stored = defaults.object(forKey: firstLaunchDateKey) as? Date {
            return calendar.startOfDay(for: stored)
        }

        let today = calendar.startOfDay(for: Date())
        defaults.set(today, forKey: firstLaunchDateKey)
        return today
    }

    var firstStrainSyncDate: Date? {
        get {
            guard let stored = defaults.object(forKey: firstStrainSyncDateKey) as? Date else { return nil }
            return calendar.startOfDay(for: stored)
        }
        nonmutating set {
            if let newValue {
                defaults.set(calendar.startOfDay(for: newValue), forKey: firstStrainSyncDateKey)
            } else {
                defaults.removeObject(forKey: firstStrainSyncDateKey)
            }
        }
    }

    func registerFirstLaunchIfNeeded() {
        _ = firstLaunchDate
    }

    var hasSeenHealthKitOnboarding: Bool {
        get { defaults.bool(forKey: healthKitOnboardingKey) }
        nonmutating set { defaults.set(newValue, forKey: healthKitOnboardingKey) }
    }

    func registerStrainSync(on date: Date) {
        let day = calendar.startOfDay(for: date)
        if let current = firstStrainSyncDate, current <= day { return }
        firstStrainSyncDate = day
    }
}
