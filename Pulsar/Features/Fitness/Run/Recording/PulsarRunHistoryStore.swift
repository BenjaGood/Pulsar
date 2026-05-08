//
//  PulsarRunHistoryStore.swift
//  Pulsar
//

import Foundation
import HealthKit

actor PulsarRunHistoryStore {
    private let defaults: UserDefaults
    private let cacheKey = "pulsar.running.history.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ summary: PulsarRunSummary) {
        var runs = loadCachedRuns()
        runs.removeAll { $0.id == summary.id || ($0.workoutUUID != nil && $0.workoutUUID == summary.workoutUUID) }
        runs.insert(summary, at: 0)
        runs = Array(runs.prefix(80))
        if let data = try? JSONEncoder().encode(runs) {
            defaults.set(data, forKey: cacheKey)
        }
    }

    func loadRuns(healthStore: HKHealthStore) async -> [PulsarRunSummary] {
        let localRuns = loadCachedRuns()
        let healthRuns = await fetchHealthKitRuns(healthStore: healthStore)
        var merged = localRuns

        for run in healthRuns where !merged.contains(where: { $0.workoutUUID == run.workoutUUID }) {
            merged.append(run)
        }

        return merged.sorted { $0.startedAt > $1.startedAt }
    }

    func loadCachedRuns() -> [PulsarRunSummary] {
        guard let data = defaults.data(forKey: cacheKey),
              let runs = try? JSONDecoder().decode([PulsarRunSummary].self, from: data) else { return [] }
        return runs
    }

    private func fetchHealthKitRuns(healthStore: HKHealthStore) async -> [PulsarRunSummary] {
        let predicate = HKQuery.predicateForWorkouts(with: .running)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 20, sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: samples as? [HKWorkout] ?? [])
            }
            healthStore.execute(query)
        }

        return workouts.map { workout in
            PulsarRunSummary(
                id: workout.uuid,
                workoutUUID: workout.uuid,
                startedAt: workout.startDate,
                endedAt: workout.endDate,
                source: workout.sourceRevision.source.name.localizedCaseInsensitiveContains("watch") ? .appleWatch : .iPhone,
                distanceMeters: workout.totalDistance?.doubleValue(for: .meter()) ?? 0,
                elapsedTime: workout.duration,
                movingTime: workout.duration,
                activeEnergyKilocalories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                elevationGainMeters: 0,
                averageHeartRate: nil,
                maxHeartRate: nil,
                steps: nil,
                averageCadenceStepsPerMinute: nil,
                route: [],
                splits: []
            )
        }
    }
}
