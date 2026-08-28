//
//  FitnessRefreshCoordinatorTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

@MainActor
struct FitnessRefreshCoordinatorTests {
    @Test func replacementWaitsForCancellationInsensitivePredecessor() async {
        let coordinator = FitnessRefreshCoordinator()
        let gate = FitnessRefreshTestGate()
        var events: [String] = []

        let first = Task { @MainActor in
            _ = await coordinator.run {
                events.append("first-start")
                await gate.wait()
                events.append("first-end")
            }
        }
        while events.isEmpty {
            await Task.yield()
        }

        let second = Task { @MainActor in
            _ = await coordinator.run {
                events.append("second-start")
            }
        }
        await Task.yield()
        #expect(events == ["first-start"])

        await gate.open()
        await first.value
        await second.value

        #expect(events == ["first-start", "first-end", "second-start"])
    }

    @Test func cancelledSubmissionReportsThatItDidNotComplete() async {
        let coordinator = FitnessRefreshCoordinator()
        let gate = FitnessRefreshTestGate()

        let first = Task { @MainActor in
            await coordinator.run {
                await gate.wait()
            }
        }
        while !coordinator.isRunning {
            await Task.yield()
        }

        coordinator.cancel()
        await gate.open()

        #expect(await first.value == false)
        #expect(!coordinator.isRunning)
    }

    @Test func maintenanceWaitsForAuthoritativeRefreshWithoutCancellingIt() async {
        let coordinator = FitnessRefreshCoordinator()
        let gate = FitnessRefreshTestGate()
        var events: [String] = []

        let authoritative = Task { @MainActor in
            await coordinator.run(priority: .authoritative) {
                events.append("authoritative-start")
                await gate.wait()
                events.append("authoritative-end")
            }
        }
        while events.isEmpty {
            await Task.yield()
        }

        let maintenance = Task { @MainActor in
            await coordinator.run(priority: .maintenance) {
                events.append("maintenance-start")
            }
        }
        await Task.yield()
        #expect(events == ["authoritative-start"])

        await gate.open()
        #expect(await authoritative.value)
        #expect(await maintenance.value)
        #expect(events == ["authoritative-start", "authoritative-end", "maintenance-start"])
    }

    @Test func authoritativeRefreshReplacesMaintenanceRefresh() async {
        let coordinator = FitnessRefreshCoordinator()
        let gate = FitnessRefreshTestGate()
        var events: [String] = []

        let maintenance = Task { @MainActor in
            await coordinator.run(priority: .maintenance) {
                events.append("maintenance-start")
                await gate.wait()
            }
        }
        while events.isEmpty {
            await Task.yield()
        }

        let authoritative = Task { @MainActor in
            await coordinator.run(priority: .authoritative) {
                events.append("authoritative-start")
            }
        }
        await Task.yield()
        #expect(events == ["maintenance-start"])

        await gate.open()
        #expect(await maintenance.value == false)
        #expect(await authoritative.value)
        #expect(events == ["maintenance-start", "authoritative-start"])
    }

    @Test func cancellationDropsMaintenanceWaitingBehindAuthoritativeRefresh() async {
        let coordinator = FitnessRefreshCoordinator()
        let gate = FitnessRefreshTestGate()
        var events: [String] = []

        let authoritative = Task { @MainActor in
            await coordinator.run(priority: .authoritative) {
                events.append("authoritative-start")
                await gate.wait()
            }
        }
        while events.isEmpty {
            await Task.yield()
        }

        let maintenance = Task { @MainActor in
            await coordinator.run(priority: .maintenance) {
                events.append("maintenance-start")
            }
        }
        await Task.yield()
        coordinator.cancel()
        await gate.open()

        #expect(await authoritative.value == false)
        #expect(await maintenance.value == false)
        #expect(events == ["authoritative-start"])
        #expect(!coordinator.isRunning)
    }

    @Test func warmMaintenanceCanSkipInsteadOfReplacingActiveWork() async {
        let coordinator = FitnessRefreshCoordinator()
        let gate = FitnessRefreshTestGate()
        var events: [String] = []

        let first = Task { @MainActor in
            await coordinator.run(priority: .maintenance) {
                events.append("first-start")
                await gate.wait()
                events.append("first-end")
            }
        }
        while events.isEmpty {
            await Task.yield()
        }

        let duplicateCompleted = await coordinator.run(
            priority: .maintenance,
            skipIfBusy: true
        ) {
            events.append("duplicate-start")
        }

        #expect(!duplicateCompleted)
        #expect(events == ["first-start"])

        await gate.open()
        #expect(await first.value)
        #expect(events == ["first-start", "first-end"])
    }

    @Test func freshProgressWarmLoadKeepsDerivedCachesReady() async throws {
        let suiteName = "pulsar.fitness-progress-warm.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PulsarGymWorkoutHistoryStore(defaults: defaults)
        let calendar = Calendar(identifier: .gregorian)
        let initialNow = Date(timeIntervalSince1970: 1_800_000_000)
        var clock = initialNow
        let viewModel = ExerciseProgressViewModel(
            historyStore: store,
            calendar: calendar,
            now: initialNow,
            nowProvider: { clock }
        )
        let week = FitnessWeekCalculator.getWeekPeriod(
            for: initialNow,
            calendar: calendar,
            now: initialNow
        )

        await viewModel.load(displayUnit: .kilograms, selectedWeek: week)
        #expect(!viewModel.needsRefresh(displayUnit: .kilograms, selectedWeek: week))

        let counts = viewModel.exerciseCountsByDay
        let summaries = viewModel.dailySummaries
        clock = initialNow.addingTimeInterval(30)
        await viewModel.load(displayUnit: .kilograms, selectedWeek: week)

        #expect(viewModel.exerciseCountsByDay == counts)
        #expect(viewModel.dailySummaries == summaries)
        #expect(viewModel.isLoading == false)
        #expect(!viewModel.needsRefresh(displayUnit: .kilograms, selectedWeek: week))
    }

    @Test func progressRefreshDetectsHistoryGenerationChange() async throws {
        let suiteName = "pulsar.fitness-progress-generation.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PulsarGymWorkoutHistoryStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let viewModel = ExerciseProgressViewModel(
            historyStore: store,
            calendar: calendar,
            now: now,
            nowProvider: { now }
        )
        let week = FitnessWeekCalculator.getWeekPeriod(for: now, calendar: calendar, now: now)

        await viewModel.load(displayUnit: .kilograms, selectedWeek: week)
        store.save(PulsarPerformanceFixtures.completedGymSessions(count: 1)[0])

        #expect(viewModel.needsRefresh(displayUnit: .kilograms, selectedWeek: week))
        await viewModel.refreshIfNeeded(displayUnit: .kilograms, selectedWeek: week)
        #expect(!viewModel.needsRefresh(displayUnit: .kilograms, selectedWeek: week))
    }

    @Test func warmWeekLoadDoesNotRefetchProviders() async throws {
        let suiteName = "pulsar.fitness-week-warm.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let healthKit = FitnessWeeklyActivityProviderCounter()
        let runHistory = FitnessRunHistoryProviderCounter()
        let viewModel = FitnessWeekViewModel(
            healthKit: healthKit,
            runHistoryStore: runHistory,
            gymHistoryStore: PulsarGymWorkoutHistoryStore(defaults: defaults),
            calendar: Calendar(identifier: .gregorian),
            now: .now
        )

        await viewModel.load()
        let firstHealthCounts = await healthKit.counts()
        let firstRunCounts = await runHistory.counts()

        await viewModel.load()

        #expect(firstHealthCounts == FitnessWeeklyProviderCounts(weekly: 1, presence: 1))
        #expect(firstRunCounts == FitnessRunProviderCounts(runs: 1, presence: 1))
        #expect(await healthKit.counts() == firstHealthCounts)
        #expect(await runHistory.counts() == firstRunCounts)
    }

    @Test func weekRolloverMonitoringStopsWhileFitnessIsOffscreen() {
        let viewModel = FitnessWeekViewModel()

        viewModel.startWeekRolloverMonitoring()
        #expect(viewModel.isWeekRolloverMonitoring)

        viewModel.stopWeekRolloverMonitoring()
        #expect(!viewModel.isWeekRolloverMonitoring)
    }
}

private actor FitnessRefreshTestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

private struct FitnessWeeklyProviderCounts: Equatable, Sendable {
    var weekly: Int
    var presence: Int
}

private actor FitnessWeeklyActivityProviderCounter: FitnessWeeklyActivityProviding {
    private var weeklyCount = 0
    private var presenceCount = 0

    func fetchWeeklyActivities(
        start: Date,
        end: Date,
        includesHeartRate: Bool,
        includesRoutes: Bool
    ) async -> [WeeklyActivity] {
        weeklyCount += 1
        return []
    }

    func fetchWorkoutStartDates(start: Date, end: Date) async -> [Date] {
        presenceCount += 1
        return []
    }

    func counts() -> FitnessWeeklyProviderCounts {
        FitnessWeeklyProviderCounts(weekly: weeklyCount, presence: presenceCount)
    }
}

private struct FitnessRunProviderCounts: Equatable, Sendable {
    var runs: Int
    var presence: Int
}

private actor FitnessRunHistoryProviderCounter: FitnessRunHistoryProviding {
    private var runsCount = 0
    private var presenceCount = 0

    func loadCachedRuns(hydratingRoutes: Bool) async -> [PulsarRunSummary] {
        runsCount += 1
        return []
    }

    func loadCachedRunStartDates(start: Date, end: Date) async -> [Date] {
        presenceCount += 1
        return []
    }

    func counts() -> FitnessRunProviderCounts {
        FitnessRunProviderCounts(runs: runsCount, presence: presenceCount)
    }
}
