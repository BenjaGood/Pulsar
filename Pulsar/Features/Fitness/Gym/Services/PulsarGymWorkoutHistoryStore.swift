//
//  PulsarGymWorkoutHistoryStore.swift
//  Pulsar
//

import Combine
import Foundation

@MainActor
final class PulsarGymWorkoutHistoryStore: ObservableObject {
    static let didChangeNotification = Notification.Name("pulsar.gym.workoutHistoryDidChange")

    @Published private(set) var sessions: [PulsarGymWorkoutSession]

    private let defaults: UserDefaults
    private let storageKey = "pulsar.gym.workoutSessions.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.sessions = Self.loadSessions(defaults: defaults, storageKey: storageKey, decoder: decoder)
    }

    @discardableResult
    func save(_ session: PulsarGymWorkoutSession) -> PulsarGymWorkoutSession {
        var completedSession = session
        if completedSession.finishedAt == nil {
            completedSession.finishedAt = .now
        }

        let muscleSummary = MuscleTrainingAnalyticsService.summary(for: completedSession)
        completedSession.trainedMuscleGroups = muscleSummary.trainedMuscleGroups
        completedSession.muscleLoadByGroup = Dictionary(uniqueKeysWithValues: muscleSummary.loadByGroup.map { group, score in
            (group.rawValue, score)
        })
        completedSession.muscleLoadByMatrixGroup = Dictionary(uniqueKeysWithValues: muscleSummary.loadByMatrixGroup.map { group, score in
            (group.rawValue, score)
        })

        let wasExisting = sessions.contains { existing in
            existing.id == completedSession.id ||
                (existing.healthKitWorkoutUUID != nil && existing.healthKitWorkoutUUID == completedSession.healthKitWorkoutUUID)
        }
        sessions.removeAll { existing in
            existing.id == completedSession.id ||
                (existing.healthKitWorkoutUUID != nil && existing.healthKitWorkoutUUID == completedSession.healthKitWorkoutUUID)
        }
        sessions.insert(completedSession, at: 0)
        sessions.sort { $0.startedAt > $1.startedAt }
        persist()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: completedSession)
        PulsarSyncDebugLogger.log("Gym Activity Log \(wasExisting ? "updated" : "created") session=\(completedSession.id.uuidString) type=\(completedSession.workoutKind.rawValue) workoutUUID=\(completedSession.healthKitWorkoutUUID?.uuidString ?? "none")")
        return completedSession
    }

    func reload() {
        sessions = Self.loadSessions(defaults: defaults, storageKey: storageKey, decoder: decoder)
    }

    func sessions(start: Date, end: Date) -> [PulsarGymWorkoutSession] {
        return sessions.filter { session in
            session.finishedAt != nil && session.startedAt >= start && session.startedAt < end
        }
    }

    private func persist() {
        guard let data = try? encoder.encode(sessions) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func loadSessions(defaults: UserDefaults, storageKey: String, decoder: JSONDecoder) -> [PulsarGymWorkoutSession] {
        guard let data = defaults.data(forKey: storageKey),
              let sessions = try? decoder.decode([PulsarGymWorkoutSession].self, from: data) else {
            return []
        }
        return sessions.sorted { $0.startedAt > $1.startedAt }
    }
}
