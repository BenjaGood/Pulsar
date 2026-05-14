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
        if let existingIndex = runs.firstIndex(where: { isSameWorkout($0, summary) }) {
            let merged = runs[existingIndex].merged(with: summary)
            runs.remove(at: existingIndex)
            runs.insert(merged, at: 0)
            PulsarSyncDebugLogger.log("Run Activity Log updated session=\(merged.pulsarWorkoutSessionId?.uuidString ?? "none") type=\(merged.workoutKind.rawValue) workoutUUID=\(merged.workoutUUID?.uuidString ?? "none")")
        } else {
            runs.insert(summary, at: 0)
            PulsarSyncDebugLogger.log("Run Activity Log created session=\(summary.pulsarWorkoutSessionId?.uuidString ?? "none") type=\(summary.workoutKind.rawValue) workoutUUID=\(summary.workoutUUID?.uuidString ?? "none")")
        }
        runs = Array(runs.prefix(80))
        if let data = try? JSONEncoder().encode(runs) {
            defaults.set(data, forKey: cacheKey)
        }
    }

    func loadRuns(healthStore: HKHealthStore) async -> [PulsarRunSummary] {
        let localRuns = loadCachedRuns()
        let healthRuns = await fetchHealthKitRuns(healthStore: healthStore)
        var merged = localRuns

        for run in healthRuns {
            if let existingIndex = merged.firstIndex(where: { isSameWorkout($0, run) }) {
                merged[existingIndex] = merged[existingIndex].merged(with: run)
                PulsarSyncDebugLogger.log("Run HealthKit import merged session=\(run.pulsarWorkoutSessionId?.uuidString ?? "none") type=\(run.workoutKind.rawValue) workoutUUID=\(run.workoutUUID?.uuidString ?? "none")")
            } else {
                merged.append(run)
                PulsarSyncDebugLogger.log("Run HealthKit import appended session=\(run.pulsarWorkoutSessionId?.uuidString ?? "none") type=\(run.workoutKind.rawValue) workoutUUID=\(run.workoutUUID?.uuidString ?? "none")")
            }
        }

        return merged.sorted { $0.startedAt > $1.startedAt }
    }

    func loadCachedRuns() -> [PulsarRunSummary] {
        guard let data = defaults.data(forKey: cacheKey),
              let runs = try? JSONDecoder().decode([PulsarRunSummary].self, from: data) else { return [] }
        return runs
    }

    private func fetchHealthKitRuns(healthStore: HKHealthStore) async -> [PulsarRunSummary] {
        let predicates = PulsarOutdoorWorkoutKind.allCases.map { HKQuery.predicateForWorkouts(with: $0.healthKitActivityType) }
        let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 20, sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: samples as? [HKWorkout] ?? [])
            }
            healthStore.execute(query)
        }

        return workouts.map { workout in
            let sessionId = PulsarWorkoutMetadata.sessionId(from: workout.metadata)
            let workoutKind = PulsarOutdoorWorkoutKind(metadata: workout.metadata, fallbackActivityType: workout.workoutActivityType)
            let startedFrom = PulsarWorkoutMetadata.startedFrom(from: workout.metadata)
            PulsarSyncDebugLogger.log("Run HealthKit metadata received session=\(sessionId?.uuidString ?? "none") type=\(PulsarWorkoutMetadata.workoutType(from: workout.metadata) ?? workoutKind.rawValue) startedFrom=\(startedFrom?.rawValue ?? "unknown") hkType=\(workout.workoutActivityType.rawValue) source=\(workout.sourceRevision.source.name)")
            return PulsarRunSummary(
                id: workout.uuid,
                pulsarWorkoutSessionId: sessionId,
                workoutUUID: workout.uuid,
                workoutKind: workoutKind,
                startedAt: workout.startDate,
                endedAt: workout.endDate,
                source: startedFrom == .appleWatch || workout.sourceRevision.source.name.localizedCaseInsensitiveContains("watch") ? .appleWatch : .iPhone,
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

    private func isSameWorkout(_ first: PulsarRunSummary, _ second: PulsarRunSummary) -> Bool {
        if let firstSessionId = first.pulsarWorkoutSessionId,
           let secondSessionId = second.pulsarWorkoutSessionId,
           firstSessionId == secondSessionId {
            return true
        }

        if let firstWorkoutUUID = first.workoutUUID,
           let secondWorkoutUUID = second.workoutUUID,
           firstWorkoutUUID == secondWorkoutUUID {
            return true
        }

        return first.id == second.id
    }
}

private extension PulsarRunSummary {
    func merged(with incoming: PulsarRunSummary) -> PulsarRunSummary {
        var merged = incoming
        merged.pulsarWorkoutSessionId = incoming.pulsarWorkoutSessionId ?? pulsarWorkoutSessionId
        merged.workoutUUID = incoming.workoutUUID ?? workoutUUID
        if incoming.workoutKind == .other, workoutKind != .other {
            merged.workoutKind = workoutKind
        }
        merged.route = incoming.route.isEmpty ? route : incoming.route
        merged.splits = incoming.splits.isEmpty ? splits : incoming.splits
        merged.activeEnergyKilocalories = incoming.activeEnergyKilocalories ?? activeEnergyKilocalories
        merged.averageHeartRate = incoming.averageHeartRate ?? averageHeartRate
        merged.maxHeartRate = incoming.maxHeartRate ?? maxHeartRate
        merged.steps = incoming.steps ?? steps
        merged.averageCadenceStepsPerMinute = incoming.averageCadenceStepsPerMinute ?? averageCadenceStepsPerMinute
        merged.distanceMeters = incoming.distanceMeters > 0 ? incoming.distanceMeters : distanceMeters
        merged.elevationGainMeters = incoming.elevationGainMeters > 0 ? incoming.elevationGainMeters : elevationGainMeters
        merged.movingTime = incoming.movingTime > 0 ? incoming.movingTime : movingTime
        merged.elapsedTime = incoming.elapsedTime > 0 ? incoming.elapsedTime : elapsedTime
        return merged
    }
}
