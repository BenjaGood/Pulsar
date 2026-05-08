import Foundation

final class ProcessedHealthEventStore {
    private enum Key {
        static let processedWorkoutIDs = "pulsar.notifications.processedWorkoutIDs.v1"
        static let processedSleepSessionIDs = "pulsar.notifications.processedSleepSessionIDs.v1"
    }

    private let defaults: UserDefaults
    private let maximumStoredIdentifiers = 500

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func hasProcessedWorkout(id: String) -> Bool {
        loadSet(forKey: Key.processedWorkoutIDs).contains(id)
    }

    func markWorkoutProcessed(id: String) {
        store(id: id, forKey: Key.processedWorkoutIDs)
    }

    func hasProcessedSleepSession(id: String) -> Bool {
        loadSet(forKey: Key.processedSleepSessionIDs).contains(id)
    }

    func markSleepSessionProcessed(id: String) {
        store(id: id, forKey: Key.processedSleepSessionIDs)
    }

    func reset() {
        defaults.removeObject(forKey: Key.processedWorkoutIDs)
        defaults.removeObject(forKey: Key.processedSleepSessionIDs)
    }

    private func store(id: String, forKey key: String) {
        var values = loadSet(forKey: key)
        values.insert(id)
        let storedValues = Array(values).sorted().suffix(maximumStoredIdentifiers)
        defaults.set(Array(storedValues), forKey: key)
    }

    private func loadSet(forKey key: String) -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }
}
