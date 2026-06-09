//
//  PulsarHealthKitWorkoutRouteImporter.swift
//  Pulsar
//

import CoreLocation
import Foundation
import HealthKit

enum PulsarHealthKitWorkoutRouteImporter {
    static func route(for workout: HKWorkout, healthStore: HKHealthStore) async -> GPSWorkoutRoute? {
        let routes = await fetchRoutes(for: workout, healthStore: healthStore)
        guard !routes.isEmpty else { return nil }

        var allLocations: [CLLocation] = []
        for route in routes {
            let locations = await fetchLocations(for: route, healthStore: healthStore)
            allLocations.append(contentsOf: locations)
        }

        let points = allLocations
            .sorted { $0.timestamp < $1.timestamp }
            .map(GPSRoutePoint.init(location:))
        guard points.count > 1 else { return nil }
        return GPSWorkoutRoute(points: points, source: .healthKitRoute, capturedAt: workout.endDate)
    }

    nonisolated static func splitEstimates(from route: GPSWorkoutRoute) -> [PulsarRunSplit] {
        guard route.points.count > 1 else { return [] }
        var splits: [PulsarRunSplit] = []
        var previousLocation: CLLocation?
        var previousAltitude: Double?
        var cumulativeDistance = 0.0
        var splitStartDistance = 0.0
        var splitStartTime = route.points.first?.timestamp ?? Date()
        var splitGain = 0.0
        var splitLoss = 0.0

        for point in route.points {
            let location = CLLocation(
                coordinate: point.coordinate,
                altitude: point.altitude ?? 0,
                horizontalAccuracy: point.horizontalAccuracy ?? -1,
                verticalAccuracy: point.verticalAccuracy ?? -1,
                timestamp: point.timestamp
            )
            if let previousLocation {
                cumulativeDistance += max(0, location.distance(from: previousLocation))
            }
            previousLocation = location

            if let altitude = point.altitude {
                let change = PulsarRunDerivedMetrics.elevationChange(
                    previousAltitude: previousAltitude,
                    nextAltitude: altitude,
                    verticalAccuracy: point.verticalAccuracy
                )
                splitGain += change.gain
                splitLoss += change.loss
                if point.verticalAccuracy.map({ $0 <= 18 }) ?? true {
                    previousAltitude = altitude
                }
            }

            while cumulativeDistance - splitStartDistance >= 1_000 {
                let index = splits.count + 1
                splits.append(
                    PulsarRunSplit(
                        index: index,
                        distanceMeters: 1_000,
                        movingTime: max(0, point.timestamp.timeIntervalSince(splitStartTime)),
                        elevationGainMeters: splitGain,
                        elevationLossMeters: splitLoss,
                        averageHeartRate: nil
                    )
                )
                splitStartDistance += 1_000
                splitStartTime = point.timestamp
                splitGain = 0
                splitLoss = 0
            }
        }

        return splits
    }

    private static func fetchRoutes(for workout: HKWorkout, healthStore: HKHealthStore) async -> [HKWorkoutRoute] {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForObjects(from: workout)
            let query = HKSampleQuery(
                sampleType: HKSeriesType.workoutRoute(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    PulsarSyncDebugLogger.log("HealthKit route import failed workout=\(workout.uuid.uuidString) error=\(error.localizedDescription)")
                }
                continuation.resume(returning: samples as? [HKWorkoutRoute] ?? [])
            }
            healthStore.execute(query)
        }
    }

    private static func fetchLocations(for route: HKWorkoutRoute, healthStore: HKHealthStore) async -> [CLLocation] {
        await withCheckedContinuation { continuation in
            var locations: [CLLocation] = []
            let lock = NSLock()
            var didResume = false
            let query = HKWorkoutRouteQuery(route: route) { _, routeData, done, error in
                lock.lock()
                defer { lock.unlock() }
                guard !didResume else { return }
                if let routeData {
                    locations.append(contentsOf: routeData)
                }
                if let error {
                    PulsarSyncDebugLogger.log("HealthKit route location import failed route=\(route.uuid.uuidString) error=\(error.localizedDescription)")
                    didResume = true
                    continuation.resume(returning: locations)
                } else if done {
                    didResume = true
                    continuation.resume(returning: locations)
                }
            }
            healthStore.execute(query)
        }
    }
}
