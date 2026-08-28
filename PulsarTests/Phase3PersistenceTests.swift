//
//  Phase3PersistenceTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

struct Phase3PersistenceTests {
    @Test @MainActor func gymHistoryMigratesLegacyBlobToNewestOneHundredSessions() throws {
        let suiteName = "pulsar.phase3.gym-retention.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacySessions = PulsarPerformanceFixtures.completedGymSessions(count: 120)
        defaults.set(
            try JSONEncoder().encode(Array(legacySessions.reversed())),
            forKey: "pulsar.gym.workoutSessions.v1"
        )

        let store = PulsarGymWorkoutHistoryStore(defaults: defaults)
        let migratedData = try #require(defaults.data(forKey: "pulsar.gym.workoutSessions.v1"))
        let migratedSessions = try JSONDecoder().decode([PulsarGymWorkoutSession].self, from: migratedData)

        #expect(store.sessions.count == PulsarGymWorkoutHistoryStore.retentionLimit)
        #expect(migratedSessions.count == PulsarGymWorkoutHistoryStore.retentionLimit)
        #expect(store.sessions.map(\.id) == Array(legacySessions.prefix(100)).map(\.id))
        #expect(migratedSessions.map(\.id) == store.sessions.map(\.id))
    }

    @Test @MainActor func gymHistoryStillDeduplicatesCrossDeviceSaves() throws {
        let suiteName = "pulsar.phase3.gym-deduplication.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let requestID = UUID()
        var sessions = PulsarPerformanceFixtures.completedGymSessions(count: 2)
        sessions[0].crossDeviceRequestID = requestID
        sessions[1].crossDeviceRequestID = requestID

        let store = PulsarGymWorkoutHistoryStore(defaults: defaults)
        store.save(sessions[0])
        store.save(sessions[1])

        #expect(store.sessions.count == 1)
        #expect(store.sessions.first?.id == sessions[1].id)
        #expect(store.sessions.first?.crossDeviceRequestID == requestID)
    }

    @Test func runPresenceDoesNotHydrateRouteSidecars() async throws {
        let suiteName = "pulsar.phase3.run-presence.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PulsarPhase3Presence-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let routeStore = PulsarRunRouteFileStore(directoryURL: directory)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let sessionID = UUID()
        let workoutUUID = UUID()
        let route = [
            PulsarRunCoordinate(latitude: 37.33, longitude: -122.03, timestamp: start),
            PulsarRunCoordinate(latitude: 37.34, longitude: -122.02, timestamp: start.addingTimeInterval(30))
        ]
        await routeStore.save(route: route, sessionId: sessionID, workoutUUID: workoutUUID)
        defaults.set(
            try JSONEncoder().encode([
                makeRunSummary(
                    sessionID: sessionID,
                    workoutUUID: workoutUUID,
                    startedAt: start
                )
            ]),
            forKey: "pulsar.running.history.v1"
        )

        let store = PulsarRunHistoryStore(defaults: defaults, routeFileStore: routeStore)
        let dates = await store.loadCachedRunStartDates(
            start: start.addingTimeInterval(-1),
            end: start.addingTimeInterval(1)
        )
        try FileManager.default.removeItem(at: directory)
        let hydratedAfterSidecarRemoval = await store.loadCachedRuns()

        #expect(dates == [start])
        #expect(hydratedAfterSidecarRemoval.first?.route.isEmpty == true)
    }

    @Test @MainActor func fitnessDashboardUsesSlimHealthKitAndRunHistoryRequests() async throws {
        let healthKit = WeeklyActivityProviderSpy()
        let runHistory = RunHistoryProviderSpy()
        let suiteName = "pulsar.phase3.fitness-seams.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let viewModel = FitnessWeekViewModel(
            healthKit: healthKit,
            runHistoryStore: runHistory,
            gymHistoryStore: PulsarGymWorkoutHistoryStore(defaults: defaults),
            calendar: Calendar(identifier: .gregorian),
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        await viewModel.load()

        let healthRequests = await healthKit.weeklyRequests
        let routeHydrationRequests = await runHistory.routeHydrationRequests
        let presenceRequestCount = await runHistory.presenceRequestCount
        #expect(healthRequests.count == 1)
        #expect(healthRequests.first?.includesHeartRate == false)
        #expect(healthRequests.first?.includesRoutes == false)
        #expect(routeHydrationRequests == [false])
        #expect(presenceRequestCount == 1)
        #expect(HealthKitWeeklyActivityFetchOptions.details.includesHeartRate)
        #expect(HealthKitWeeklyActivityFetchOptions.details.includesRoutes)
    }

    @Test func workoutDetailMergeRestoresDeferredHeartRateAndRoute() {
        let workoutUUID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let listActivity = WeeklyActivity(
            id: workoutUUID.uuidString,
            workoutUUID: workoutUUID,
            workoutType: "Running",
            displayName: "Morning Run",
            category: .running,
            startDate: startedAt,
            endDate: startedAt.addingTimeInterval(1_800),
            duration: 1_800,
            calories: nil,
            distanceMeters: 5_000,
            averageHeartRate: nil,
            maxHeartRate: nil,
            source: .localRun,
            sourceName: "Pulsar"
        )
        var details = listActivity
        details.source = .healthKit
        details.sourceName = "Apple Watch"
        details.calories = 320
        details.averageHeartRate = 148
        details.maxHeartRate = 176
        details.route = [
            PulsarRunCoordinate(latitude: 37.33, longitude: -122.03, timestamp: startedAt),
            PulsarRunCoordinate(latitude: 37.34, longitude: -122.02, timestamp: startedAt.addingTimeInterval(30))
        ]
        details.metadata = [FitnessWorkoutMetadataItem(title: "Average Heart Rate", value: "148 bpm")]

        let merged = FitnessWorkoutRouteReloader.merging(listActivity, with: details)

        #expect(merged.displayName == "Morning Run")
        #expect(merged.source == .localRun)
        #expect(merged.calories == 320)
        #expect(merged.averageHeartRate == 148)
        #expect(merged.maxHeartRate == 176)
        #expect(merged.route == details.route)
        #expect(merged.metadata == details.metadata)
    }

    @Test func dailyAndSourceCachesRetainOnlyNewestOneHundredTwentyDays() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let payloads = Dictionary(uniqueKeysWithValues: (0..<125).map { day in
            let date = start.addingTimeInterval(TimeInterval(day * 86_400))
            let key = "day-\(day)"
            let payload = PulsarDailyMetricsSyncPayload(
                date: date,
                dateKey: key,
                syncedAt: date,
                sourceDevice: .iPhone,
                strain: nil,
                recovery: nil
            )
            return (key, payload)
        })
        let sourcePayloads: [String: [PulsarSyncSourceDevice: PulsarDailyMetricsSyncPayload]] =
            payloads.mapValues { [PulsarSyncSourceDevice.iPhone: $0] }

        let retained = PulsarWatchConnectivitySyncStore.retainedDailyPayloads(payloads)
        let retainedSources = PulsarWatchConnectivitySyncStore.retainedSourcePayloads(sourcePayloads)

        #expect(retained.count == PulsarWatchConnectivitySyncStore.dailyCacheRetentionLimit)
        #expect(retainedSources.count == PulsarWatchConnectivitySyncStore.dailyCacheRetentionLimit)
        #expect(retained["day-0"] == nil)
        #expect(retainedSources["day-0"] == nil)
        #expect(retained["day-124"] != nil)
        #expect(retainedSources["day-124"] != nil)
    }

    private func makeRunSummary(
        sessionID: UUID,
        workoutUUID: UUID,
        startedAt: Date
    ) -> PulsarRunSummary {
        PulsarRunSummary(
            id: workoutUUID,
            pulsarWorkoutSessionId: sessionID,
            workoutUUID: workoutUUID,
            workoutKind: .running,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(900),
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
            route: [],
            splits: []
        )
    }
}

private struct WeeklyActivityRequest: Equatable, Sendable {
    var includesHeartRate: Bool
    var includesRoutes: Bool
}

private actor WeeklyActivityProviderSpy: FitnessWeeklyActivityProviding {
    private(set) var weeklyRequests: [WeeklyActivityRequest] = []

    func fetchWeeklyActivities(
        start: Date,
        end: Date,
        includesHeartRate: Bool,
        includesRoutes: Bool
    ) async -> [WeeklyActivity] {
        weeklyRequests.append(
            WeeklyActivityRequest(
                includesHeartRate: includesHeartRate,
                includesRoutes: includesRoutes
            )
        )
        return []
    }

    func fetchWorkoutStartDates(start: Date, end: Date) async -> [Date] {
        []
    }
}

private actor RunHistoryProviderSpy: FitnessRunHistoryProviding {
    private(set) var routeHydrationRequests: [Bool] = []
    private(set) var presenceRequestCount = 0

    func loadCachedRuns(hydratingRoutes: Bool) async -> [PulsarRunSummary] {
        routeHydrationRequests.append(hydratingRoutes)
        return []
    }

    func loadCachedRunStartDates(start: Date, end: Date) async -> [Date] {
        presenceRequestCount += 1
        return []
    }
}
