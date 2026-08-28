//
//  WorkoutRoutePersistenceTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

struct WorkoutRoutePersistenceTests {
    @Test func preferredRouteKeepsRicherPolyline() {
        let short = [
            PulsarRunCoordinate(latitude: 1, longitude: 1, timestamp: Date(timeIntervalSince1970: 1)),
            PulsarRunCoordinate(latitude: 1.1, longitude: 1.1, timestamp: Date(timeIntervalSince1970: 2))
        ]
        let long = short + [
            PulsarRunCoordinate(latitude: 1.2, longitude: 1.2, timestamp: Date(timeIntervalSince1970: 3)),
            PulsarRunCoordinate(latitude: 1.3, longitude: 1.3, timestamp: Date(timeIntervalSince1970: 4))
        ]

        #expect(PulsarWorkoutRouteMerge.preferredRoute(short, long) == long)
        #expect(PulsarWorkoutRouteMerge.preferredRoute(long, []) == long)
        #expect(PulsarWorkoutRouteMerge.preferredRoute([], short) == short)
    }

    @Test func enrichSummaryFallsBackToInMemoryRoute() {
        let fallback = [
            PulsarRunCoordinate(latitude: 37.33, longitude: -122.03, timestamp: Date(timeIntervalSince1970: 10)),
            PulsarRunCoordinate(latitude: 37.34, longitude: -122.02, timestamp: Date(timeIntervalSince1970: 20)),
            PulsarRunCoordinate(latitude: 37.35, longitude: -122.01, timestamp: Date(timeIntervalSince1970: 30))
        ]
        let emptyRouteSummary = makeSummary(route: [], splits: [
            PulsarRunSplit(index: 1, distanceMeters: 1_000, movingTime: 300, elevationGainMeters: 0, averageHeartRate: nil)
        ])

        let enriched = PulsarWorkoutRouteMerge.enrichSummary(emptyRouteSummary, withFallbackRoute: fallback)
        #expect(enriched.route == fallback)
        #expect(enriched.splits.count == 1)
    }

    @Test func historyStorePersistsRouteAcrossUserDefaultsCompaction() async throws {
        let suiteName = "pulsar.run.route.persistence.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PulsarRunRouteTests-\(UUID().uuidString)", isDirectory: true)
        let routeStore = PulsarRunRouteFileStore(directoryURL: directory)
        let store = PulsarRunHistoryStore(defaults: defaults, routeFileStore: routeStore)

        let sessionId = UUID()
        let workoutUUID = UUID()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var route: [PulsarRunCoordinate] = []
        for index in 0..<320 {
            route.append(
                PulsarRunCoordinate(
                    latitude: 37.3 + Double(index) * 0.0001,
                    longitude: -122.0 - Double(index) * 0.0001,
                    timestamp: start.addingTimeInterval(Double(index))
                )
            )
        }

        let summary = PulsarRunSummary(
            id: workoutUUID,
            pulsarWorkoutSessionId: sessionId,
            workoutUUID: workoutUUID,
            workoutKind: .running,
            startedAt: start,
            endedAt: start.addingTimeInterval(1_200),
            source: .appleWatch,
            distanceMeters: 4_020,
            elapsedTime: 1_200,
            movingTime: 1_140,
            activeEnergyKilocalories: 370,
            elevationGainMeters: 18,
            averageHeartRate: 164,
            maxHeartRate: 179,
            steps: nil,
            averageCadenceStepsPerMinute: nil,
            route: route,
            splits: [
                PulsarRunSplit(index: 1, distanceMeters: 1_000, movingTime: 180, elevationGainMeters: 0, averageHeartRate: nil),
                PulsarRunSplit(index: 2, distanceMeters: 1_000, movingTime: 220, elevationGainMeters: 0, averageHeartRate: nil),
                PulsarRunSplit(index: 3, distanceMeters: 1_000, movingTime: 332, elevationGainMeters: 0, averageHeartRate: nil),
                PulsarRunSplit(index: 4, distanceMeters: 1_000, movingTime: 357, elevationGainMeters: 0, averageHeartRate: nil)
            ]
        )

        await store.save(summary)
        let cached = await store.loadCachedRuns()
        #expect(cached.count == 1)
        #expect(cached.first?.route.count == route.count)
        #expect(cached.first?.splits.count == 4)
        #expect(cached.first?.workoutUUID == workoutUUID)
    }

    @Test func historyMergeKeepsLocalRouteWhenHealthKitImportIsEmpty() async throws {
        let suiteName = "pulsar.run.route.merge.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PulsarRunRouteMerge-\(UUID().uuidString)", isDirectory: true)
        let routeStore = PulsarRunRouteFileStore(directoryURL: directory)
        let store = PulsarRunHistoryStore(defaults: defaults, routeFileStore: routeStore)

        let sessionId = UUID()
        let workoutUUID = UUID()
        let start = Date(timeIntervalSince1970: 1_800_000_100)
        let localRoute = [
            PulsarRunCoordinate(latitude: 37.33, longitude: -122.03, timestamp: start),
            PulsarRunCoordinate(latitude: 37.34, longitude: -122.02, timestamp: start.addingTimeInterval(30)),
            PulsarRunCoordinate(latitude: 37.35, longitude: -122.01, timestamp: start.addingTimeInterval(60))
        ]

        await store.save(
            makeSummary(
                id: UUID(),
                sessionId: sessionId,
                workoutUUID: nil,
                start: start,
                route: localRoute,
                splits: [PulsarRunSplit(index: 1, distanceMeters: 1_000, movingTime: 300, elevationGainMeters: 0, averageHeartRate: nil)]
            )
        )
        await store.save(
            makeSummary(
                id: workoutUUID,
                sessionId: sessionId,
                workoutUUID: workoutUUID,
                start: start,
                route: [],
                splits: []
            )
        )

        let cached = await store.loadCachedRuns()
        #expect(cached.count == 1)
        #expect(cached.first?.route.count == localRoute.count)
        #expect(cached.first?.splits.count == 1)
        #expect(cached.first?.workoutUUID == workoutUUID)
    }

    private func makeSummary(
        id: UUID = UUID(),
        sessionId: UUID = UUID(),
        workoutUUID: UUID? = nil,
        start: Date = Date(timeIntervalSince1970: 1_700_000_000),
        route: [PulsarRunCoordinate],
        splits: [PulsarRunSplit]
    ) -> PulsarRunSummary {
        PulsarRunSummary(
            id: id,
            pulsarWorkoutSessionId: sessionId,
            workoutUUID: workoutUUID,
            workoutKind: .running,
            startedAt: start,
            endedAt: start.addingTimeInterval(900),
            source: .appleWatch,
            distanceMeters: 2_000,
            elapsedTime: 900,
            movingTime: 860,
            activeEnergyKilocalories: 200,
            elevationGainMeters: 10,
            averageHeartRate: 150,
            maxHeartRate: 170,
            steps: nil,
            averageCadenceStepsPerMinute: nil,
            route: route,
            splits: splits
        )
    }
}
