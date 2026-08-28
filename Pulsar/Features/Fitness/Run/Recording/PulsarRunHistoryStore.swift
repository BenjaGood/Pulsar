//
//  PulsarRunHistoryStore.swift
//  Pulsar
//

import Foundation
import HealthKit
import OSLog

actor PulsarRunHistoryStore {
    static let shared = PulsarRunHistoryStore()

    private let defaults: UserDefaults
    private let cacheKey = "pulsar.running.history.v1"
    private let routeFileStore: PulsarRunRouteFileStore
    private var compactRunsCache: [PulsarRunSummary]?
    private var hydratedRunsCache: [PulsarRunSummary]?

    init(
        defaults: UserDefaults = .standard,
        routeFileStore: PulsarRunRouteFileStore = .shared
    ) {
        self.defaults = defaults
        self.routeFileStore = routeFileStore
    }

    func save(_ summary: PulsarRunSummary) async {
        var runs = await loadCachedRuns()
        let summaryWithDiskRoute = await routeFileStore.hydrate(summary)
        await routeFileStore.save(
            route: summaryWithDiskRoute.route,
            sessionId: summaryWithDiskRoute.pulsarWorkoutSessionId,
            workoutUUID: summaryWithDiskRoute.workoutUUID
        )
        if let existingIndex = runs.firstIndex(where: { isSameWorkout($0, summaryWithDiskRoute) }) {
            let merged = runs[existingIndex].merged(with: summaryWithDiskRoute)
            runs.remove(at: existingIndex)
            runs.insert(merged, at: 0)
            PulsarSyncDebugLogger.log("Run Activity Log updated session=\(merged.pulsarWorkoutSessionId?.uuidString ?? "none") type=\(merged.workoutKind.rawValue) workoutUUID=\(merged.workoutUUID?.uuidString ?? "none") routePoints=\(merged.route.count)")
        } else {
            runs.insert(summaryWithDiskRoute, at: 0)
            PulsarSyncDebugLogger.log("Run Activity Log created session=\(summaryWithDiskRoute.pulsarWorkoutSessionId?.uuidString ?? "none") type=\(summaryWithDiskRoute.workoutKind.rawValue) workoutUUID=\(summaryWithDiskRoute.workoutUUID?.uuidString ?? "none") routePoints=\(summaryWithDiskRoute.route.count)")
        }
        runs = Array(runs.prefix(80))
        await persist(runs)
    }

    func loadRuns(healthStore: HKHealthStore) async -> [PulsarRunSummary] {
        let localRuns = await loadCachedRuns()
        let healthRuns = await fetchHealthKitRuns(healthStore: healthStore)
        var merged = localRuns

        for run in healthRuns {
            if let existingIndex = merged.firstIndex(where: { isSameWorkout($0, run) }) {
                merged[existingIndex] = merged[existingIndex].merged(with: run)
                PulsarSyncDebugLogger.log("Run HealthKit import merged session=\(run.pulsarWorkoutSessionId?.uuidString ?? "none") type=\(run.workoutKind.rawValue) workoutUUID=\(run.workoutUUID?.uuidString ?? "none") routePoints=\(merged[existingIndex].route.count)")
            } else {
                merged.append(run)
                PulsarSyncDebugLogger.log("Run HealthKit import appended session=\(run.pulsarWorkoutSessionId?.uuidString ?? "none") type=\(run.workoutKind.rawValue) workoutUUID=\(run.workoutUUID?.uuidString ?? "none") routePoints=\(run.route.count)")
            }
        }

        let sorted = Array(merged.sorted { $0.startedAt > $1.startedAt }.prefix(80))
        if sorted != localRuns {
            await persist(sorted)
        }
        return sorted
    }

    func loadCachedRuns() async -> [PulsarRunSummary] {
        await loadCachedRuns(hydratingRoutes: true)
    }

    func loadCachedRuns(hydratingRoutes: Bool) async -> [PulsarRunSummary] {
        guard hydratingRoutes else {
            return loadCompactRuns()
        }
        if let hydratedRunsCache {
            return hydratedRunsCache
        }
        let signpostState = PulsarPerformanceSignposts.fitness.beginInterval("runs_hydrate")
        defer {
            PulsarPerformanceSignposts.fitness.endInterval("runs_hydrate", signpostState)
        }
        let runs = loadCompactRuns()
        var hydrated: [PulsarRunSummary] = []
        hydrated.reserveCapacity(runs.count)
        for run in runs {
            let withDiskRoute = await routeFileStore.hydrate(run)
            hydrated.append(withDiskRoute)
        }
        hydratedRunsCache = hydrated
        return hydrated
    }

    /// Returns only the dates needed to mark weeks with workouts. This path never
    /// reads route sidecars, so paging the week selector stays independent of GPS payload size.
    func loadCachedRunStartDates(start: Date, end: Date) async -> [Date] {
        loadCompactRuns()
            .lazy
            .filter { $0.startedAt >= start && $0.startedAt < end }
            .map(\.startedAt)
    }

    private func loadCompactRuns() -> [PulsarRunSummary] {
        if let compactRunsCache {
            return compactRunsCache
        }
        guard let data = defaults.data(forKey: cacheKey),
              let runs = try? JSONDecoder().decode([PulsarRunSummary].self, from: data) else {
            compactRunsCache = []
            return []
        }
        let retainedRuns = Array(runs.sorted { $0.startedAt > $1.startedAt }.prefix(80))
        compactRunsCache = retainedRuns
        return retainedRuns
    }

    private func fetchHealthKitRuns(healthStore: HKHealthStore) async -> [PulsarRunSummary] {
        let predicates = PulsarOutdoorWorkoutKind.allCases.map { HKQuery.predicateForWorkouts(with: $0.healthKitActivityType) }
        let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: samples as? [HKWorkout] ?? [])
            }
            healthStore.execute(query)
        }

        var summaries: [PulsarRunSummary] = []
        for workout in workouts {
            let sessionId = PulsarWorkoutMetadata.sessionId(from: workout.metadata)
            if Self.isPulsarGymWorkout(workout.metadata) {
                PulsarSyncDebugLogger.log("Run HealthKit import skipped Gym workout session=\(sessionId?.uuidString ?? "none") type=\(PulsarWorkoutMetadata.workoutType(from: workout.metadata) ?? "unknown")")
                continue
            }
            let workoutKind = PulsarOutdoorWorkoutKind(metadata: workout.metadata, fallbackActivityType: workout.workoutActivityType)
            let startedFrom = PulsarWorkoutMetadata.startedFrom(from: workout.metadata)
            let isAppleWatchSource = startedFrom?.isAppleWatchRecorder == true ||
                workout.sourceRevision.source.name.localizedCaseInsensitiveContains("watch")
            if isAppleWatchSource {
                await MainActor.run {
                    PulsarWatchConnectivitySyncStore.shared.recordAppleWatchSeen(
                        reason: "runHealthKitMetadata",
                        payloadKind: "healthKitWorkoutMetadata"
                    )
                }
            }
            PulsarSyncDebugLogger.log("Run HealthKit metadata received session=\(sessionId?.uuidString ?? "none") type=\(PulsarWorkoutMetadata.workoutType(from: workout.metadata) ?? workoutKind.rawValue) startedFrom=\(startedFrom?.rawValue ?? "unknown") hkType=\(workout.workoutActivityType.rawValue) source=\(workout.sourceRevision.source.name) watchSource=\(isAppleWatchSource)")
            let importedRoute = workoutKind.isOutdoorDistanceWorkout
                ? await PulsarHealthKitWorkoutRouteImporter.route(for: workout, healthStore: healthStore)
                : nil
            let route = importedRoute?.runCoordinates ?? []
            let elevationMetrics = importedRoute?.elevationMetrics
            let heartRateMetrics = await fetchHeartRateMetrics(
                healthStore: healthStore,
                workout: workout
            )
            let sourceName = Self.sourceName(for: workout, isAppleWatchSource: isAppleWatchSource)
            summaries.append(PulsarRunSummary(
                id: workout.uuid,
                pulsarWorkoutSessionId: sessionId,
                workoutUUID: workout.uuid,
                workoutKind: workoutKind,
                startedAt: workout.startDate,
                endedAt: workout.endDate,
                source: isAppleWatchSource ? .appleWatch : .iPhone,
                sourceName: sourceName,
                heartRateSourceHistory: heartRateMetrics.sourceHistory,
                distanceMeters: workout.totalDistance?.doubleValue(for: .meter()) ?? 0,
                elapsedTime: workout.duration,
                movingTime: workout.duration,
                activeEnergyKilocalories: Self.activeEnergyKilocalories(for: workout),
                elevationGainMeters: elevationMetrics?.gainMeters ?? 0,
                elevationLossMeters: elevationMetrics?.lossMeters ?? 0,
                minimumElevationMeters: elevationMetrics?.minimumElevationMeters,
                maximumElevationMeters: elevationMetrics?.maximumElevationMeters,
                averageHeartRate: heartRateMetrics.average,
                maxHeartRate: heartRateMetrics.maximum,
                steps: nil,
                averageCadenceStepsPerMinute: nil,
                route: route,
                splits: importedRoute.map { PulsarHealthKitWorkoutRouteImporter.splitEstimates(from: $0) } ?? []
            ))
        }
        return summaries
    }

    private func fetchHeartRateMetrics(
        healthStore: HKHealthStore,
        workout: HKWorkout
    ) async -> (average: Double?, maximum: Double?, sourceHistory: [WorkoutHeartRateSourceSegment]) {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return (nil, nil, [])
        }
        let associatedSamples = await fetchHeartRateSamples(
            healthStore: healthStore,
            type: heartRateType,
            predicate: HKQuery.predicateForObjects(from: workout)
        )
        let samples: [HKQuantitySample]
        if associatedSamples.isEmpty {
            let fallbackPredicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate)
            samples = await fetchHeartRateSamples(
                healthStore: healthStore,
                type: heartRateType,
                predicate: fallbackPredicate
            )
        } else {
            samples = associatedSamples
        }

        let values = samples.map { $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) }
            .filter { $0 > 0 }
        let sourceHistory = Self.heartRateSourceHistory(from: samples)
        guard !values.isEmpty else { return (nil, nil, sourceHistory) }
        return (values.reduce(0, +) / Double(values.count), values.max(), sourceHistory)
    }

    private func fetchHeartRateSamples(
        healthStore: HKHealthStore,
        type: HKQuantityType,
        predicate: NSPredicate
    ) async -> [HKQuantitySample] {
        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
            }
            healthStore.execute(query)
        }
        return samples
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

    private nonisolated static func activeEnergyKilocalories(for workout: HKWorkout) -> Double? {
        guard let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return nil }
        return workout.statistics(for: activeEnergyType)?
            .sumQuantity()?
            .doubleValue(for: .kilocalorie())
    }

    private nonisolated static func sourceName(for workout: HKWorkout, isAppleWatchSource: Bool) -> String? {
        let candidates = [
            workout.device?.name,
            workout.sourceRevision.productType,
            workout.sourceRevision.source.name
        ]
        let sourceName = candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return sourceName ?? (isAppleWatchSource ? PulsarRunRecordingSource.appleWatch.label : nil)
    }

    private nonisolated static func heartRateSourceHistory(from samples: [HKQuantitySample]) -> [WorkoutHeartRateSourceSegment] {
        var history: [WorkoutHeartRateSourceSegment] = []
        for sample in samples.sorted(by: { $0.startDate < $1.startDate }) {
            let metadata = WorkoutHeartRateFallbackMonitor.metadata(from: sample)
            let sourceKind = metadata.sourceKind == .unknown ? WorkoutHeartRateSourceKind.healthKit : metadata.sourceKind
            if let lastIndex = history.indices.last,
               history[lastIndex].sourceKind == sourceKind {
                history[lastIndex].endedAt = sample.startDate
                history[lastIndex].metadata = metadata
                continue
            }
            if let lastIndex = history.indices.last,
               history[lastIndex].endedAt == nil {
                history[lastIndex].endedAt = sample.startDate
            }
            history.append(
                WorkoutHeartRateSourceSegment(
                    sourceKind: sourceKind,
                    startedAt: sample.startDate,
                    endedAt: nil,
                    metadata: metadata,
                    isFallback: false
                )
            )
        }
        return history
    }

    private func persist(_ runs: [PulsarRunSummary]) async {
        for run in runs where run.route.count > 1 {
            await routeFileStore.save(
                route: run.route,
                sessionId: run.pulsarWorkoutSessionId,
                workoutUUID: run.workoutUUID
            )
        }
        // Keep UserDefaults lean: persist summaries with routes stripped when oversized,
        // relying on the on-disk route sidecar for restoration.
        let compactRuns = runs.map { run -> PulsarRunSummary in
            guard run.route.count > 250 else { return run }
            var compact = run
            // Keep UserDefaults lean; the on-disk sidecar is the source of truth.
            compact.route = []
            return compact
        }
        do {
            let data = try JSONEncoder().encode(compactRuns)
            defaults.set(data, forKey: cacheKey)
            compactRunsCache = compactRuns
            hydratedRunsCache = runs
        } catch {
            PulsarSyncDebugLogger.log("Run Activity Log persist failed error=\(error.localizedDescription)")
            let routeStrippedRuns = compactRuns.map { run -> PulsarRunSummary in
                var stripped = run
                stripped.route = []
                return stripped
            }
            if let data = try? JSONEncoder().encode(routeStrippedRuns) {
                defaults.set(data, forKey: cacheKey)
                compactRunsCache = routeStrippedRuns
                hydratedRunsCache = runs
                PulsarSyncDebugLogger.log("Run Activity Log persist fell back to route-stripped summaries")
            }
        }
    }

    private nonisolated static func isPulsarGymWorkout(_ metadata: [String: Any]?) -> Bool {
        guard let metadata else { return false }
        let rawType = PulsarWorkoutMetadata.workoutType(from: metadata)
        if rawType == PulsarGymWorkoutKind.routine.rawValue ||
            rawType == PulsarGymWorkoutKind.freeWorkout.rawValue {
            return true
        }
        guard let category = metadata["PulsarWorkoutCategory"] as? String else { return false }
        return category.localizedCaseInsensitiveCompare(PulsarGymWorkoutKind.routine.categoryName) == .orderedSame
    }
}

private extension PulsarRunSummary {
    nonisolated func merged(with incoming: PulsarRunSummary) -> PulsarRunSummary {
        var merged = incoming
        merged.pulsarWorkoutSessionId = incoming.pulsarWorkoutSessionId ?? pulsarWorkoutSessionId
        merged.workoutUUID = incoming.workoutUUID ?? workoutUUID
        merged.sourceName = incoming.sourceName ?? sourceName
        merged.heartRateSourceHistory = incoming.heartRateSourceHistory.isEmpty ? heartRateSourceHistory : incoming.heartRateSourceHistory
        merged.heartRateSourceStatusMessage = incoming.heartRateSourceStatusMessage ?? heartRateSourceStatusMessage
        if incoming.workoutKind == .other, workoutKind != .other {
            merged.workoutKind = workoutKind
        }
        merged.route = PulsarWorkoutRouteMerge.preferredRoute(route, incoming.route)
        merged.splits = PulsarWorkoutRouteMerge.preferredSplits(splits, incoming.splits)
        merged.activeEnergyKilocalories = incoming.activeEnergyKilocalories ?? activeEnergyKilocalories
        merged.averageHeartRate = incoming.averageHeartRate ?? averageHeartRate
        merged.maxHeartRate = incoming.maxHeartRate ?? maxHeartRate
        merged.steps = incoming.steps ?? steps
        merged.averageCadenceStepsPerMinute = incoming.averageCadenceStepsPerMinute ?? averageCadenceStepsPerMinute
        let hasLocalMotionDetail = !route.isEmpty || !splits.isEmpty || movingTime < elapsedTime - 1
        let incomingLooksLikeGenericHealthKitImport = incoming.route.isEmpty &&
            incoming.splits.isEmpty &&
            abs(incoming.movingTime - incoming.elapsedTime) < 1
        if hasLocalMotionDetail, incomingLooksLikeGenericHealthKitImport {
            merged.distanceMeters = distanceMeters
            merged.movingTime = movingTime
            merged.elapsedTime = elapsedTime
        } else {
            merged.distanceMeters = incoming.distanceMeters > 0 ? incoming.distanceMeters : distanceMeters
            merged.movingTime = incoming.movingTime > 0 ? incoming.movingTime : movingTime
            merged.elapsedTime = incoming.elapsedTime > 0 ? incoming.elapsedTime : elapsedTime
        }
        merged.elevationGainMeters = incoming.elevationGainMeters > 0 ? incoming.elevationGainMeters : elevationGainMeters
        merged.elevationLossMeters = incoming.elevationLossMeters > 0 ? incoming.elevationLossMeters : elevationLossMeters
        merged.minimumElevationMeters = incoming.minimumElevationMeters ?? minimumElevationMeters
        merged.maximumElevationMeters = incoming.maximumElevationMeters ?? maximumElevationMeters
        merged.weatherSummary = incoming.weatherSummary ?? weatherSummary
        return merged
    }
}
