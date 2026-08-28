//
//  PulsarGymWorkoutHistoryStore.swift
//  Pulsar
//

import Combine
import Foundation
import OSLog

@MainActor
final class PulsarGymWorkoutHistoryStore: ObservableObject {
    static let shared = PulsarGymWorkoutHistoryStore()
    static let didChangeNotification = Notification.Name("pulsar.gym.workoutHistoryDidChange")
    /// Activity Log retains the 100 newest sessions. Existing larger v1 blobs are
    /// sorted and pruned to this boundary the first time this store loads them.
    static let retentionLimit = 100

    private static let storageKey = "pulsar.gym.workoutSessions.v1"

    @Published private(set) var sessions: [PulsarGymWorkoutSession]

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var lastPersistedData: Data?

    init(defaults: UserDefaults = .standard) {
        let signpostState = PulsarPerformanceSignposts.fitness.beginInterval("history_init")
        self.defaults = defaults
        let storedData = defaults.data(forKey: Self.storageKey)
        let loadedSessions = Self.loadSessions(data: storedData, decoder: decoder)
        self.sessions = Self.retainedSessions(from: loadedSessions)
        self.lastPersistedData = storedData
        if sessions.count != loadedSessions.count {
            persist()
        }
        PulsarPerformanceSignposts.fitness.endInterval("history_init", signpostState)
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
                (existing.healthKitWorkoutUUID != nil && existing.healthKitWorkoutUUID == completedSession.healthKitWorkoutUUID) ||
                (existing.crossDeviceRequestID != nil && existing.crossDeviceRequestID == completedSession.crossDeviceRequestID)
        }
        sessions.removeAll { existing in
            existing.id == completedSession.id ||
                (existing.healthKitWorkoutUUID != nil && existing.healthKitWorkoutUUID == completedSession.healthKitWorkoutUUID) ||
                (existing.crossDeviceRequestID != nil && existing.crossDeviceRequestID == completedSession.crossDeviceRequestID)
        }
        sessions.insert(completedSession, at: 0)
        sessions = Self.retainedSessions(from: sessions)
        persist()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: completedSession)
        PulsarSyncDebugLogger.log("Gym Activity Log \(wasExisting ? "updated" : "created") session=\(completedSession.id.uuidString) type=\(completedSession.workoutKind.rawValue) workoutUUID=\(completedSession.healthKitWorkoutUUID?.uuidString ?? "none")")
        return completedSession
    }

    func reload() {
        let storedData = defaults.data(forKey: Self.storageKey)
        guard storedData != lastPersistedData else { return }
        let loadedSessions = Self.loadSessions(data: storedData, decoder: decoder)
        sessions = Self.retainedSessions(from: loadedSessions)
        lastPersistedData = storedData
        if sessions.count != loadedSessions.count {
            persist()
        }
    }

    func session(id: UUID) -> PulsarGymWorkoutSession? {
        sessions.first { $0.id == id }
    }

    @discardableResult
    func updateSession(_ session: PulsarGymWorkoutSession) -> PulsarGymWorkoutSession {
        save(session)
    }

    func sessions(start: Date, end: Date) -> [PulsarGymWorkoutSession] {
        return sessions.filter { session in
            session.finishedAt != nil && session.startedAt >= start && session.startedAt < end
        }
    }

    private func persist() {
        guard let data = try? encoder.encode(sessions) else { return }
        guard data != lastPersistedData else { return }
        defaults.set(data, forKey: Self.storageKey)
        lastPersistedData = data
    }

    private static func loadSessions(data: Data?, decoder: JSONDecoder) -> [PulsarGymWorkoutSession] {
        guard let data,
              let sessions = try? decoder.decode([PulsarGymWorkoutSession].self, from: data) else {
            return []
        }
        return sessions.sorted { $0.startedAt > $1.startedAt }
    }

    private static func retainedSessions(from sessions: [PulsarGymWorkoutSession]) -> [PulsarGymWorkoutSession] {
        Array(sessions.sorted { $0.startedAt > $1.startedAt }.prefix(retentionLimit))
    }
}
