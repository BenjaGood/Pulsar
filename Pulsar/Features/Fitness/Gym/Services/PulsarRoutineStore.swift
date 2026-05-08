//
//  PulsarRoutineStore.swift
//  Pulsar
//

import Combine
import Foundation

@MainActor
final class PulsarRoutineStore: ObservableObject {
    @Published private(set) var routines: [PulsarRoutine]

    private let defaults: UserDefaults
    private let storageKey = "pulsar.gym.routines.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let routines = try? decoder.decode([PulsarRoutine].self, from: data) {
            self.routines = routines.sorted { $0.updatedAt > $1.updatedAt }
        } else {
            self.routines = []
        }
    }

    @discardableResult
    func upsert(_ routine: PulsarRoutine) -> PulsarRoutine {
        var nextRoutine = routine
        nextRoutine.updatedAt = .now
        if let existing = routines.first(where: { $0.id == routine.id }) {
            nextRoutine.createdAt = existing.createdAt
        }

        routines.removeAll { $0.id == routine.id }
        routines.insert(nextRoutine, at: 0)
        persist()
        return nextRoutine
    }

    func delete(_ routine: PulsarRoutine) {
        routines.removeAll { $0.id == routine.id }
        persist()
    }

    private func persist() {
        guard let data = try? encoder.encode(routines) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
