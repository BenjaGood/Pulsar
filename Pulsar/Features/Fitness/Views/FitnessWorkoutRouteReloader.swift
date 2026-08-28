//
//  FitnessWorkoutRouteReloader.swift
//  Pulsar
//

import Foundation
import HealthKit

enum FitnessWorkoutRouteLoadState: Equatable {
    case idle
    case loading
    case loaded([PulsarRunCoordinate])
    case unavailable
}

enum FitnessWorkoutRouteReloader {
    static func loadDetails(for activity: WeeklyActivity) async -> WeeklyActivity {
        guard let workoutUUID = activity.workoutUUID else { return activity }
        let gateway = HealthKitGateway()
        let activities = await gateway.fetchWeeklyActivities(
            start: activity.startDate.addingTimeInterval(-1),
            end: activity.endDate.addingTimeInterval(1),
            includesHeartRate: HealthKitWeeklyActivityFetchOptions.details.includesHeartRate,
            includesRoutes: HealthKitWeeklyActivityFetchOptions.details.includesRoutes
        )
        guard let details = activities.first(where: { $0.workoutUUID == workoutUUID }) else {
            return activity
        }

        return merging(activity, with: details)
    }

    static func merging(_ activity: WeeklyActivity, with details: WeeklyActivity) -> WeeklyActivity {
        var enriched = activity
        enriched.calories = enriched.calories ?? details.calories
        enriched.distanceMeters = enriched.distanceMeters ?? details.distanceMeters
        enriched.averageHeartRate = enriched.averageHeartRate ?? details.averageHeartRate
        enriched.maxHeartRate = enriched.maxHeartRate ?? details.maxHeartRate
        if enriched.route.count <= 1, details.route.count > 1 {
            enriched.route = details.route
        }
        if enriched.splits.isEmpty {
            enriched.splits = details.splits
        }
        if enriched.metadata.isEmpty {
            enriched.metadata = details.metadata
        } else {
            let existingTitles = Set(enriched.metadata.map(\.title))
            enriched.metadata.append(contentsOf: details.metadata.filter { !existingTitles.contains($0.title) })
        }
        return enriched
    }

    static func loadRoute(
        existingRoute: [PulsarRunCoordinate],
        workoutUUID: UUID?,
        healthStore: HKHealthStore = HKHealthStore(),
        retryCount: Int = 3,
        retryDelayNanoseconds: UInt64 = 1_500_000_000
    ) async -> FitnessWorkoutRouteLoadState {
        if existingRoute.count > 1 {
            return .loaded(existingRoute)
        }

        guard let workoutUUID else { return .unavailable }

        for attempt in 0..<retryCount {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: retryDelayNanoseconds)
            }
            guard let workout = await fetchWorkout(uuid: workoutUUID, healthStore: healthStore) else {
                continue
            }
            if let route = await PulsarHealthKitWorkoutRouteImporter.route(for: workout, healthStore: healthStore),
               route.runCoordinates.count > 1 {
                let coordinates = route.runCoordinates
                await PulsarRunRouteFileStore.shared.save(
                    route: coordinates,
                    sessionId: PulsarWorkoutMetadata.sessionId(from: workout.metadata),
                    workoutUUID: workout.uuid
                )
                return .loaded(coordinates)
            }
        }

        return existingRoute.isEmpty ? .unavailable : .loaded(existingRoute)
    }

    private static func fetchWorkout(uuid: UUID, healthStore: HKHealthStore) async -> HKWorkout? {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForObject(with: uuid)
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: samples?.first as? HKWorkout)
            }
            healthStore.execute(query)
        }
    }
}
