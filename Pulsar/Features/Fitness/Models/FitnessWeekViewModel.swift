//
//  FitnessWeekViewModel.swift
//  Pulsar
//

import Combine
import Foundation

@MainActor
final class FitnessWeekViewModel: ObservableObject {
    @Published private(set) var weeks: [WeekPeriod]
    @Published private(set) var selectedWeek: WeekPeriod
    @Published private(set) var historyWeeks: [WeekPeriod] = []
    @Published private(set) var activities: [WeeklyActivity] = []
    @Published private(set) var isLoadingActivities = false
    @Published private(set) var isRefreshingWeeks = false
    @Published private(set) var isLoadingWeekHistory = false

    private let healthKit: HealthKitGateway
    private let runHistoryStore: PulsarRunHistoryStore
    private let gymHistoryStore: PulsarGymWorkoutHistoryStore
    private let calendar: Calendar
    private var rolloverTask: Task<Void, Never>?

    init(
        healthKit: HealthKitGateway = HealthKitGateway(),
        runHistoryStore: PulsarRunHistoryStore = PulsarRunHistoryStore(),
        gymHistoryStore: PulsarGymWorkoutHistoryStore? = nil,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now
    ) {
        self.healthKit = healthKit
        self.runHistoryStore = runHistoryStore
        self.gymHistoryStore = gymHistoryStore ?? PulsarGymWorkoutHistoryStore()
        self.calendar = calendar
        let generatedWeeks = FitnessWeekCalculator.getWeekPeriodsAroundCurrentWeek(calendar: calendar, now: now)
        self.weeks = generatedWeeks
        self.selectedWeek = generatedWeeks.first(where: \.isCurrentWeek) ?? FitnessWeekCalculator.getWeekPeriod(for: now, calendar: calendar, now: now)
    }

    deinit {
        rolloverTask?.cancel()
    }

    var canMoveToNextWeek: Bool {
        guard let currentWeek = weeks.first(where: \.isCurrentWeek) else { return false }
        return selectedWeek.startDate < currentWeek.startDate
    }

    var focusedWeeks: [WeekPeriod] {
        let currentWeek = periodWithStoredPresence(FitnessWeekCalculator.getWeekPeriod(for: .now, calendar: calendar))
        let selected = periodWithStoredPresence(selectedWeek)
        let offsets: [Int]

        if selected.id == currentWeek.id || selected.startDate >= currentWeek.startDate {
            offsets = [-2, -1, 0]
        } else {
            let next = FitnessWeekCalculator.nextWeek(after: selected, calendar: calendar)
            offsets = next.startDate <= currentWeek.startDate ? [-1, 0, 1] : [-2, -1, 0]
        }

        return offsets.compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset * 7, to: selected.startDate) else { return nil }
            let week = FitnessWeekCalculator.getWeekPeriod(for: date, calendar: calendar)
            guard week.startDate <= currentWeek.startDate else { return nil }
            return periodWithStoredPresence(week)
        }
    }

    var bodyMapAnalysis: BodyMapAnalysis {
        BodyMapAnalyzer.analyze(activities: activities)
    }

    func load() async {
        rebuildWeekWindow(now: .now, preservingSelectedWeek: true)
        await refreshWorkoutPresence()
        await fetchWorkouts(for: selectedWeek)
    }

    func refresh() async {
        await refreshWorkoutPresence()
        await fetchWorkouts(for: selectedWeek)
    }

    func selectWeek(_ week: WeekPeriod) async {
        guard selectedWeek.id != week.id else {
            await fetchWorkouts(for: week)
            return
        }

        insertFocusedWeeks(around: week)
        selectedWeek = periodWithStoredPresence(week)
        await fetchWorkouts(for: selectedWeek, clearsExisting: true)
    }

    func selectPreviousWeek() async {
        let previous = FitnessWeekCalculator.previousWeek(before: selectedWeek, calendar: calendar)
        insertWeekIfNeeded(previous)
        await refreshWorkoutPresence()
        await selectWeek(previous)
    }

    func selectNextWeek() async {
        guard canMoveToNextWeek else { return }
        let next = FitnessWeekCalculator.nextWeek(after: selectedWeek, calendar: calendar)
        insertWeekIfNeeded(next)
        await refreshWorkoutPresence()
        await selectWeek(next)
    }

    func selectCurrentWeek() async {
        let current = FitnessWeekCalculator.getWeekPeriod(for: .now, calendar: calendar)
        insertFocusedWeeks(around: current)
        await refreshWorkoutPresence()
        await selectWeek(current)
    }

    func prepareWeekHistory() async {
        isLoadingWeekHistory = true
        let year = selectedWeek.year
        let yearWeeks = FitnessWeekCalculator.getWeekPeriods(forYear: year, calendar: calendar)
        let interval = FitnessWeekCalculator.yearInterval(for: year, calendar: calendar)
        let activityDates = await activityStartDates(start: interval.start, end: interval.end)
        let now = Date()

        historyWeeks = yearWeeks.map { week in
            var updated = FitnessWeekCalculator.getWeekPeriod(for: week.startDate, calendar: calendar, now: now)
            updated.hasWorkout = activityDates.contains { FitnessWeekCalculator.contains($0, in: updated, calendar: calendar) }
            return updated
        }

        weeks = uniqueWeeks(weeks + historyWeeks).sorted { $0.startDate < $1.startDate }
        if let updatedSelection = historyWeeks.first(where: { $0.id == selectedWeek.id }) ?? weeks.first(where: { $0.id == selectedWeek.id }) {
            selectedWeek = updatedSelection
        }
        isLoadingWeekHistory = false
    }

    func refreshCurrentWeekIfNeeded() async {
        let wasViewingCurrentWeek = selectedWeek.isCurrentWeek
        rebuildWeekWindow(now: .now, preservingSelectedWeek: !wasViewingCurrentWeek)
        await refreshWorkoutPresence()

        if wasViewingCurrentWeek {
            selectedWeek = weeks.first(where: \.isCurrentWeek) ?? selectedWeek
            await fetchWorkouts(for: selectedWeek)
        } else if let preserved = weeks.first(where: { $0.id == selectedWeek.id }) {
            selectedWeek = preserved
        }
    }

    func startWeekRolloverMonitoring() {
        rolloverTask?.cancel()
        rolloverTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay = self.secondsUntilNextWeekBoundary()
                let nanoseconds = UInt64(max(1, delay) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                if Task.isCancelled { return }
                await self.refreshCurrentWeekIfNeeded()
            }
        }
    }

    private func fetchWorkouts(for week: WeekPeriod, clearsExisting: Bool = false) async {
        isLoadingActivities = true
        if clearsExisting {
            activities = []
        }
        let fetchEnd = FitnessWeekCalculator.fetchEnd(for: week, calendar: calendar)

        async let healthActivities = healthKit.fetchWeeklyActivities(start: week.startDate, end: fetchEnd, includesHeartRate: true)
        async let cachedRuns = runHistoryStore.loadCachedRuns()

        let runs = await cachedRuns
        let localRunActivities = runs
            .filter { FitnessWeekCalculator.contains($0.startedAt, in: week, calendar: calendar) }
            .map(localRunActivity)
        let localGymActivities = gymHistoryStore.sessions(start: week.startDate, end: fetchEnd).map(localGymActivity)
        let localActivities = localRunActivities + localGymActivities

        let healthKitActivities = await healthActivities
        let mergedActivities = mergeActivities(healthKit: healthKitActivities, local: localActivities)
        activities = mergedActivities.sorted { $0.startDate > $1.startDate }
        isLoadingActivities = false
    }

    private func refreshWorkoutPresence() async {
        guard !weeks.isEmpty else { return }
        isRefreshingWeeks = true

        let sortedWeeks = weeks.sorted { $0.startDate < $1.startDate }
        let start = sortedWeeks.first?.startDate ?? selectedWeek.startDate
        let end = sortedWeeks.last.map { FitnessWeekCalculator.fetchEnd(for: $0, calendar: calendar) } ?? FitnessWeekCalculator.fetchEnd(for: selectedWeek, calendar: calendar)
        let activityDates = await activityStartDates(start: start, end: end)
        let now = Date()

        weeks = weeks.map { week in
            var updated = FitnessWeekCalculator.getWeekPeriod(for: week.startDate, calendar: calendar, now: now)
            updated.hasWorkout = activityDates.contains { FitnessWeekCalculator.contains($0, in: updated, calendar: calendar) }
            return updated
        }
        .sorted { $0.startDate < $1.startDate }

        if let updatedSelection = weeks.first(where: { $0.id == selectedWeek.id }) {
            selectedWeek = updatedSelection
        }

        if !historyWeeks.isEmpty {
            historyWeeks = historyWeeks.map { week in
                weeks.first(where: { $0.id == week.id }) ?? week
            }
        }

        isRefreshingWeeks = false
    }

    private func rebuildWeekWindow(now: Date, preservingSelectedWeek: Bool) {
        var nextWeeks = FitnessWeekCalculator.getWeekPeriodsAroundCurrentWeek(calendar: calendar, now: now)
        if preservingSelectedWeek {
            nextWeeks.append(selectedWeek)
        }
        weeks = uniqueWeeks(nextWeeks).sorted { $0.startDate < $1.startDate }
    }

    private func insertWeekIfNeeded(_ week: WeekPeriod) {
        guard !weeks.contains(where: { $0.id == week.id }) else { return }
        weeks = uniqueWeeks(weeks + [week]).sorted { $0.startDate < $1.startDate }
    }

    private func insertFocusedWeeks(around week: WeekPeriod) {
        let adjacentWeeks = [
            FitnessWeekCalculator.previousWeek(before: week, calendar: calendar),
            week,
            FitnessWeekCalculator.nextWeek(after: week, calendar: calendar)
        ]
        weeks = uniqueWeeks(weeks + adjacentWeeks).sorted { $0.startDate < $1.startDate }
    }

    private func uniqueWeeks(_ periods: [WeekPeriod]) -> [WeekPeriod] {
        var byID: [String: WeekPeriod] = [:]
        for period in periods {
            var merged = period
            if let existing = byID[period.id] {
                merged.hasWorkout = existing.hasWorkout || period.hasWorkout
            }
            byID[period.id] = merged
        }
        return Array(byID.values)
    }

    private func periodWithStoredPresence(_ period: WeekPeriod) -> WeekPeriod {
        if let stored = weeks.first(where: { $0.id == period.id }) {
            return stored
        }
        if let stored = historyWeeks.first(where: { $0.id == period.id }) {
            return stored
        }
        return period
    }

    private func activityStartDates(start: Date, end: Date) async -> [Date] {
        async let healthWorkoutDates = healthKit.fetchWorkoutStartDates(start: start, end: end)
        async let cachedRuns = runHistoryStore.loadCachedRuns()

        let healthDates = await healthWorkoutDates
        let runs = await cachedRuns
        let gymDates = gymHistoryStore.sessions(start: start, end: end).map(\.startedAt)
        return healthDates + runs.map(\.startedAt) + gymDates
    }

    private func localRunActivity(_ run: PulsarRunSummary) -> WeeklyActivity {
        WeeklyActivity(
            id: "local-run-\(run.id.uuidString)",
            workoutUUID: run.workoutUUID,
            workoutType: "Running",
            displayName: "Running",
            category: .running,
            startDate: run.startedAt,
            endDate: run.endedAt,
            duration: run.movingTime > 0 ? run.movingTime : run.elapsedTime,
            calories: run.activeEnergyKilocalories,
            distanceMeters: run.distanceMeters > 0 ? run.distanceMeters : nil,
            averageHeartRate: run.averageHeartRate,
            maxHeartRate: run.maxHeartRate,
            source: .localRun,
            sourceName: run.source.label
        )
    }

    private func localGymActivity(_ session: PulsarGymWorkoutSession) -> WeeklyActivity {
        let trimmedRoutineName = session.routineName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmedRoutineName.isEmpty ? "Gym Workout" : trimmedRoutineName
        let endedAt = session.finishedAt ?? session.startedAt.addingTimeInterval(TimeInterval(max(session.elapsedSeconds, 0)))
        let duration = session.elapsedSeconds > 0
            ? TimeInterval(session.elapsedSeconds)
            : max(0, endedAt.timeIntervalSince(session.startedAt))
        let muscleSummary = MuscleTrainingAnalyticsService.summary(for: session)

        return WeeklyActivity(
            id: "local-gym-\(session.id.uuidString)",
            workoutUUID: session.healthKitWorkoutUUID,
            workoutType: "Gym",
            displayName: displayName,
            category: .gym,
            startDate: session.startedAt,
            endDate: endedAt,
            duration: duration,
            calories: session.activeEnergyKilocalories,
            distanceMeters: nil,
            averageHeartRate: session.averageHeartRate,
            maxHeartRate: session.maxHeartRate,
            source: .localGym,
            sourceName: WeeklyActivitySource.localGym.rawValue,
            completedSets: muscleSummary.completedSets,
            totalSets: muscleSummary.totalSets,
            mainMuscleGroups: muscleSummary.mainMuscleGroupNames,
            muscleLoadByBodyZone: muscleSummary.loadByBodyMapRegion,
            muscleExercisesByBodyZone: muscleSummary.exercisesByBodyMapRegion
        )
    }

    private func mergeActivities(healthKit healthActivities: [WeeklyActivity], local localActivities: [WeeklyActivity]) -> [WeeklyActivity] {
        var merged = healthActivities

        for localActivity in localActivities {
            if localActivity.source == .localGym,
               merged.contains(where: { isDuplicate(localActivity, of: $0) }) {
                merged.removeAll { isDuplicate(localActivity, of: $0) }
                merged.append(localActivity)
            } else if !merged.contains(where: { isDuplicate(localActivity, of: $0) }) {
                merged.append(localActivity)
            }
        }

        return merged
    }

    private func isDuplicate(_ local: WeeklyActivity, of healthActivity: WeeklyActivity) -> Bool {
        if let localUUID = local.workoutUUID,
           let healthUUID = healthActivity.workoutUUID,
           localUUID == healthUUID {
            return true
        }

        let startDelta = abs(local.startDate.timeIntervalSince(healthActivity.startDate))
        let durationDelta = abs(local.duration - healthActivity.duration)
        let bothRunning = local.category == .running && healthActivity.category == .running
        let distanceDelta = abs((local.distanceMeters ?? 0) - (healthActivity.distanceMeters ?? 0))
        let distanceLooksSame = (local.distanceMeters == nil || healthActivity.distanceMeters == nil) || distanceDelta < 120
        let healthSearchText = "\(healthActivity.workoutType) \(healthActivity.displayName)".lowercased()
        let healthLooksLikeStrength = healthActivity.category == .gym ||
            healthActivity.category == .strength ||
            healthSearchText.contains("strength") ||
            healthSearchText.contains("gym")

        if local.category == .gym {
            return healthLooksLikeStrength && startDelta < 300 && durationDelta < 600
        }

        return bothRunning && startDelta < 180 && durationDelta < 300 && distanceLooksSame
    }

    private func secondsUntilNextWeekBoundary() -> TimeInterval {
        let currentWeek = FitnessWeekCalculator.getWeekPeriod(for: .now, calendar: calendar)
        let nextBoundary = FitnessWeekCalculator.fetchEnd(for: currentWeek, calendar: calendar)
        return max(60, nextBoundary.timeIntervalSinceNow + 1)
    }
}
