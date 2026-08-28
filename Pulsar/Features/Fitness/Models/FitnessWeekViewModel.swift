//
//  FitnessWeekViewModel.swift
//  Pulsar
//

import Combine
import Foundation
import OSLog

protocol FitnessWeeklyActivityProviding: Sendable {
    func fetchWeeklyActivities(
        start: Date,
        end: Date,
        includesHeartRate: Bool,
        includesRoutes: Bool
    ) async -> [WeeklyActivity]

    func fetchWorkoutStartDates(start: Date, end: Date) async -> [Date]
}

extension HealthKitGateway: FitnessWeeklyActivityProviding {}

protocol FitnessRunHistoryProviding: Sendable {
    func loadCachedRuns(hydratingRoutes: Bool) async -> [PulsarRunSummary]
    func loadCachedRunStartDates(start: Date, end: Date) async -> [Date]
}

extension PulsarRunHistoryStore: FitnessRunHistoryProviding {}

@MainActor
final class FitnessWeekViewModel: ObservableObject {
    @Published private(set) var weeks: [WeekPeriod]
    @Published private(set) var selectedWeek: WeekPeriod
    @Published private(set) var historyWeeks: [WeekPeriod] = []
    @Published private(set) var activities: [WeeklyActivity] = []
    @Published private(set) var muscleMatrixViewModel: MuscleMatrixViewModel
    @Published private(set) var isLoadingActivities = false
    @Published private(set) var isRefreshingWeeks = false
    @Published private(set) var isLoadingWeekHistory = false

    private let healthKit: any FitnessWeeklyActivityProviding
    private let runHistoryStore: any FitnessRunHistoryProviding
    private let gymHistoryStore: PulsarGymWorkoutHistoryStore
    private let calendar: Calendar
    private var rolloverTask: Task<Void, Never>?
    private var hasLoadedInitialData = false
    private var activitiesByWeekID: [String: [WeeklyActivity]] = [:]
    private var activityFetchDatesByWeekID: [String: Date] = [:]
    private var lastPresenceRefreshAt: Date?
    private let cacheFreshnessInterval: TimeInterval = 90
    private let cachedWeekLimit = 12

    init(
        healthKit: any FitnessWeeklyActivityProviding = HealthKitGateway(),
        runHistoryStore: any FitnessRunHistoryProviding = PulsarRunHistoryStore.shared,
        gymHistoryStore: PulsarGymWorkoutHistoryStore? = nil,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now
    ) {
        self.healthKit = healthKit
        self.runHistoryStore = runHistoryStore
        self.gymHistoryStore = gymHistoryStore ?? PulsarGymWorkoutHistoryStore.shared
        let fitnessCalendar = FitnessWeekCalculator.fitnessCalendar(from: calendar)
        self.calendar = fitnessCalendar
        let generatedWeeks = FitnessWeekCalculator.getWeekPeriodsAroundCurrentWeek(calendar: fitnessCalendar, now: now)
        let initialSelection = generatedWeeks.first(where: \.isCurrentWeek) ?? FitnessWeekCalculator.getWeekPeriod(for: now, calendar: fitnessCalendar, now: now)
        self.weeks = generatedWeeks
        self.selectedWeek = initialSelection
        self.muscleMatrixViewModel = MuscleMatrixViewModel(week: initialSelection, activities: [], calendar: fitnessCalendar, now: now)
    }

    deinit {
        rolloverTask?.cancel()
    }

    var canMoveToNextWeek: Bool {
        guard let currentWeek = weeks.first(where: \.isCurrentWeek) else { return false }
        return selectedWeek.startDate < currentWeek.startDate
    }

    var currentWeekRefreshIsStale: Bool {
        !hasLoadedInitialData ||
            hasCurrentWeekRolledOver ||
            isPresenceStale ||
            (selectedWeek.isCurrentWeek && isActivitiesCacheStale(for: selectedWeek))
    }

    var isWeekRolloverMonitoring: Bool {
        rolloverTask != nil
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

    func load() async {
        guard !hasLoadedInitialData else {
            await refreshCurrentWeekIfNeeded()
            return
        }
        hasLoadedInitialData = true
        rebuildWeekWindow(now: .now, preservingSelectedWeek: true)
        await refreshWorkoutPresence()
        await fetchWorkouts(for: selectedWeek)
    }

    func refresh() async {
        gymHistoryStore.reload()
        await refreshWorkoutPresence()
        await fetchWorkouts(for: selectedWeek, force: true)
    }

    func selectWeek(_ week: WeekPeriod) async {
        guard selectedWeek.id != week.id else {
            await fetchWorkouts(for: week, force: true)
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
        let fetchStart = yearWeeks.first?.startDate ?? FitnessWeekCalculator.yearInterval(for: year, calendar: calendar).start
        let fetchEnd = yearWeeks.last.map { FitnessWeekCalculator.fetchEnd(for: $0, calendar: calendar) } ?? FitnessWeekCalculator.yearInterval(for: year, calendar: calendar).end
        let activityDates = await activityStartDates(start: fetchStart, end: fetchEnd)
        let now = Date()

        historyWeeks = yearWeeks.map { week in
            var updated = FitnessWeekCalculator.getWeekPeriod(for: week.startDate, calendar: calendar, now: now)
            updated.hasWorkout = activityDates.contains { FitnessWeekCalculator.contains($0, in: updated, calendar: calendar) }
            return updated
        }

        weeks = uniqueWeeks(weeks + historyWeeks).sorted { $0.startDate < $1.startDate }
        if let updatedSelection = historyWeeks.first(where: { $0.id == selectedWeek.id }) ?? weeks.first(where: { $0.id == selectedWeek.id }) {
            selectedWeek = updatedSelection
            rebuildMuscleMatrix()
        }
        isLoadingWeekHistory = false
    }

    func refreshCurrentWeekIfNeeded(force: Bool = false) async {
        if force {
            gymHistoryStore.reload()
        }
        let wasViewingCurrentWeek = selectedWeek.isCurrentWeek
        let previousSelectedWeekID = selectedWeek.id
        rebuildWeekWindow(now: .now, preservingSelectedWeek: !wasViewingCurrentWeek)
        let movedIntoNewCurrentWeek = wasViewingCurrentWeek && weeks.first(where: \.isCurrentWeek)?.id != previousSelectedWeekID
        if force || isPresenceStale || movedIntoNewCurrentWeek {
            await refreshWorkoutPresence()
        }

        if wasViewingCurrentWeek {
            selectedWeek = weeks.first(where: \.isCurrentWeek) ?? selectedWeek
            let didMoveToNewWeek = selectedWeek.id != previousSelectedWeekID
            if didMoveToNewWeek {
                applyActivities(activitiesByWeekID[selectedWeek.id] ?? [])
            } else {
                rebuildMuscleMatrix()
            }
            if force || isActivitiesCacheStale(for: selectedWeek) {
                await fetchWorkouts(for: selectedWeek, force: true)
            }
        } else if let preserved = weeks.first(where: { $0.id == selectedWeek.id }) {
            selectedWeek = preserved
            rebuildMuscleMatrix()
        }
    }

    func startWeekRolloverMonitoring() {
        guard rolloverTask == nil else { return }
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

    func stopWeekRolloverMonitoring() {
        rolloverTask?.cancel()
        rolloverTask = nil
    }

    private func fetchWorkouts(for week: WeekPeriod, clearsExisting: Bool = false, force: Bool = false) async {
        let signpostState = PulsarPerformanceSignposts.fitness.beginInterval("week_fetch")
        defer {
            PulsarPerformanceSignposts.fitness.endInterval("week_fetch", signpostState)
        }
        if !force, let cached = activitiesByWeekID[week.id], !isActivitiesCacheStale(for: week) {
            applyActivities(cached)
            return
        }

        isLoadingActivities = true
        if clearsExisting {
            if let cached = activitiesByWeekID[week.id] {
                applyActivities(cached)
            } else {
                applyActivities([])
            }
        }
        let fetchEnd = FitnessWeekCalculator.fetchEnd(for: week, calendar: calendar)

        async let healthActivities = healthKit.fetchWeeklyActivities(
            start: week.startDate,
            end: fetchEnd,
            includesHeartRate: HealthKitWeeklyActivityFetchOptions.dashboard.includesHeartRate,
            includesRoutes: HealthKitWeeklyActivityFetchOptions.dashboard.includesRoutes
        )
        async let cachedRuns = runHistoryStore.loadCachedRuns(hydratingRoutes: false)

        let runs = await cachedRuns
        let localRunActivities = runs
            .filter { FitnessWeekCalculator.contains($0.startedAt, in: week, calendar: calendar) }
            .map(localRunActivity)
        let localGymActivities = gymHistoryStore.sessions(start: week.startDate, end: fetchEnd).map(localGymActivity)
        let localActivities = localRunActivities + localGymActivities

        let healthKitActivities = await healthActivities
        let mergedActivities = mergeActivities(healthKit: healthKitActivities, local: localActivities)
        let sortedActivities = mergedActivities.sorted { $0.startDate > $1.startDate }
        activitiesByWeekID[week.id] = sortedActivities
        activityFetchDatesByWeekID[week.id] = Date()
        pruneActivityCaches(keeping: week.id)
        if selectedWeek.id == week.id {
            applyActivities(sortedActivities)
        }
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
        lastPresenceRefreshAt = Date()
        rebuildMuscleMatrix()
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

    private var isPresenceStale: Bool {
        guard let lastPresenceRefreshAt else { return true }
        return Date().timeIntervalSince(lastPresenceRefreshAt) > cacheFreshnessInterval
    }

    private var hasCurrentWeekRolledOver: Bool {
        let latestCurrentWeek = FitnessWeekCalculator.getWeekPeriod(for: .now, calendar: calendar)
        return weeks.first(where: \.isCurrentWeek)?.id != latestCurrentWeek.id
    }

    private func isActivitiesCacheStale(for week: WeekPeriod) -> Bool {
        guard let fetchedAt = activityFetchDatesByWeekID[week.id] else { return true }
        return Date().timeIntervalSince(fetchedAt) > cacheFreshnessInterval
    }

    private func pruneActivityCaches(keeping weekID: String) {
        guard activitiesByWeekID.count > cachedWeekLimit else { return }
        let protectedIDs = Set([weekID, selectedWeek.id])
        let evictionCandidates = activityFetchDatesByWeekID
            .filter { !protectedIDs.contains($0.key) }
            .sorted { $0.value < $1.value }
            .map(\.key)
        let removalCount = activitiesByWeekID.count - cachedWeekLimit
        for cachedWeekID in evictionCandidates.prefix(removalCount) {
            activitiesByWeekID.removeValue(forKey: cachedWeekID)
            activityFetchDatesByWeekID.removeValue(forKey: cachedWeekID)
        }
    }

    private func applyActivities(_ nextActivities: [WeeklyActivity]) {
        updateStoredPresence(for: selectedWeek, hasWorkout: !nextActivities.isEmpty)
        guard activities != nextActivities else {
            rebuildMuscleMatrix()
            return
        }
        activities = nextActivities
        rebuildMuscleMatrix()
    }

    private func updateStoredPresence(for period: WeekPeriod, hasWorkout: Bool) {
        guard period.hasWorkout != hasWorkout else { return }
        var updatedSelection = selectedWeek
        updatedSelection.hasWorkout = hasWorkout
        selectedWeek = updatedSelection
        weeks = weeks.map { week in
            guard week.id == period.id else { return week }
            var updated = week
            updated.hasWorkout = hasWorkout
            return updated
        }
        if !historyWeeks.isEmpty {
            historyWeeks = historyWeeks.map { week in
                guard week.id == period.id else { return week }
                var updated = week
                updated.hasWorkout = hasWorkout
                return updated
            }
        }
    }

    private func rebuildMuscleMatrix(now: Date = .now) {
        let next = MuscleMatrixViewModel(week: selectedWeek, activities: activities, calendar: calendar, now: now)
        guard next != muscleMatrixViewModel else { return }
        muscleMatrixViewModel = next
    }

    private func activityStartDates(start: Date, end: Date) async -> [Date] {
        async let healthWorkoutDates = healthKit.fetchWorkoutStartDates(start: start, end: end)
        async let cachedRunDates = runHistoryStore.loadCachedRunStartDates(start: start, end: end)

        let healthDates = await healthWorkoutDates
        let runDates = await cachedRunDates
        let gymDates = gymHistoryStore.sessions(start: start, end: end).map(\.startedAt)
        return healthDates + runDates + gymDates
    }

    private func localRunActivity(_ run: PulsarRunSummary) -> WeeklyActivity {
        let category: WeeklyActivityCategory
        switch run.workoutKind {
        case .running, .indoorRunning: category = .running
        case .walking: category = .walking
        case .hiking: category = .hiking
        case .cycling: category = .cycling
        case .hiit: category = .hiit
        case .strength, .boxing, .core: category = .strength
        case .yoga, .pilates: category = .yoga
        case .swimming: category = .swimming
        case .rowing, .elliptical, .stairClimber: category = .rowing
        case .dance: category = .dance
        case .stretching, .mobility, .cooldown: category = .recovery
        case .other: category = .other
        }
        return WeeklyActivity(
            id: "local-\(run.workoutKind.rawValue)-\(run.id.uuidString)",
            pulsarWorkoutSessionId: run.pulsarWorkoutSessionId,
            workoutUUID: run.workoutUUID,
            workoutType: run.workoutKind.displayName,
            displayName: run.workoutKind.displayName,
            category: category,
            startDate: run.startedAt,
            endDate: run.endedAt,
            duration: run.movingTime > 0 ? run.movingTime : run.elapsedTime,
            calories: run.activeEnergyKilocalories,
            distanceMeters: run.distanceMeters > 0 ? run.distanceMeters : nil,
            averageHeartRate: run.averageHeartRate,
            maxHeartRate: run.maxHeartRate,
            source: .localRun,
            sourceName: run.sourceDeviceName,
            sourceDeviceName: run.sourceDeviceName,
            trainingType: run.workoutKind.isOutdoorDistanceWorkout ? run.workoutKind.outdoorTitle : run.workoutKind.displayName,
            route: run.route,
            splits: run.splits.map { split in
                FitnessWorkoutSplit(
                    index: split.index,
                    distanceMeters: split.distanceMeters,
                    movingTime: split.movingTime,
                    paceSecondsPerKilometer: split.paceSecondsPerKilometer,
                    averageHeartRate: split.averageHeartRate
                )
            },
            notes: [run.weatherSummary].compactMap(trimmedDetailText),
            metadata: runDetailMetadata(for: run)
        )
    }

    private func localGymActivity(_ session: PulsarGymWorkoutSession) -> WeeklyActivity {
        let displayName = session.activityLogDisplayName
        let endedAt = session.finishedAt ?? session.startedAt.addingTimeInterval(TimeInterval(max(session.elapsedSeconds, 0)))
        let duration = session.elapsedSeconds > 0
            ? TimeInterval(session.elapsedSeconds)
            : max(0, endedAt.timeIntervalSince(session.startedAt))
        let muscleSummary = MuscleTrainingAnalyticsService.summary(for: session)

        return WeeklyActivity(
            id: "local-gym-\(session.id.uuidString)",
            pulsarWorkoutSessionId: session.id,
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
            sourceName: "Pulsar Gym",
            sourceDeviceName: "Pulsar Gym",
            trainingType: session.workoutKind.displayName,
            notes: gymNotes(for: session),
            metadata: gymDetailMetadata(for: session, muscleSummary: muscleSummary),
            completedSets: muscleSummary.completedSets,
            totalSets: muscleSummary.totalSets,
            gymSetSummaries: PulsarGymWorkoutSummary.completedExerciseSummaries(from: session.exercises),
            mainMuscleGroups: muscleSummary.mainMuscleGroupNames,
            muscleLoadByMatrixGroup: muscleSummary.loadByMatrixGroup,
            muscleExercisesByMatrixGroup: muscleSummary.exercisesByMatrixGroup
        )
    }

    private func runDetailMetadata(for run: PulsarRunSummary) -> [FitnessWorkoutMetadataItem] {
        var items = [
            FitnessWorkoutMetadataItem(title: "Recorder", value: run.sourceDeviceName)
        ]
        if let workoutUUID = run.workoutUUID {
            items.append(FitnessWorkoutMetadataItem(title: "HealthKit Workout", value: workoutUUID.uuidString))
        }
        if let sessionId = run.pulsarWorkoutSessionId {
            items.append(FitnessWorkoutMetadataItem(title: "Session", value: sessionId.uuidString))
        }
        if !run.route.isEmpty {
            items.append(FitnessWorkoutMetadataItem(title: "Route Points", value: "\(run.route.count)"))
        }
        return items
    }

    private func gymDetailMetadata(for session: PulsarGymWorkoutSession, muscleSummary: WeeklyMuscleTrainingSummary) -> [FitnessWorkoutMetadataItem] {
        var items = [
            FitnessWorkoutMetadataItem(title: "Routine", value: session.activityLogDisplayName),
            FitnessWorkoutMetadataItem(title: "Training Type", value: session.workoutKind.displayName),
            FitnessWorkoutMetadataItem(title: "Exercises", value: "\(session.exercises.count)"),
            FitnessWorkoutMetadataItem(title: "Sets", value: "\(muscleSummary.completedSets)/\(muscleSummary.totalSets)")
        ]
        if let healthKitWorkoutUUID = session.healthKitWorkoutUUID {
            items.append(FitnessWorkoutMetadataItem(title: "HealthKit Workout", value: healthKitWorkoutUUID.uuidString))
        }
        return items
    }

    private func gymNotes(for session: PulsarGymWorkoutSession) -> [String] {
        var seen = Set<String>()
        let exerciseNotes = session.exercises.compactMap { exercise in
            trimmedDetailText(exercise.notes).map { "\(exercise.exerciseName): \($0)" }
        }
        var notes = exerciseNotes.filter { seen.insert($0).inserted }
        if let healthKitStatusMessage = trimmedDetailText(session.healthKitStatusMessage),
           seen.insert(healthKitStatusMessage).inserted {
            notes.append(healthKitStatusMessage)
        }
        return notes
    }

    private func trimmedDetailText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func mergeActivities(healthKit healthActivities: [WeeklyActivity], local localActivities: [WeeklyActivity]) -> [WeeklyActivity] {
        var merged = healthActivities

        for localActivity in localActivities {
            if let existingIndex = merged.firstIndex(where: { isDuplicate(localActivity, of: $0) }) {
                let existing = merged[existingIndex]
                merged[existingIndex] = Self.mergedActivity(healthKit: existing, local: localActivity)
                PulsarSyncDebugLogger.log(
                    "Activity Log merged duplicate session=\(localActivity.pulsarWorkoutSessionId?.uuidString ?? "none") action=fieldMerge localSource=\(localActivity.source.rawValue) healthSource=\(existing.sourceName) routePoints=\(merged[existingIndex].route.count)"
                )
            } else if !merged.contains(where: { isDuplicate(localActivity, of: $0) }) {
                merged.append(localActivity)
            }
        }

        return merged
    }

    nonisolated private static func mergedActivity(healthKit: WeeklyActivity, local: WeeklyActivity) -> WeeklyActivity {
        let preferLocalShell = shouldPreferLocalActivity(local, over: healthKit)
        var merged = preferLocalShell ? local : healthKit
        merged.pulsarWorkoutSessionId = local.pulsarWorkoutSessionId ?? healthKit.pulsarWorkoutSessionId
        merged.workoutUUID = local.workoutUUID ?? healthKit.workoutUUID
        merged.route = PulsarWorkoutRouteMerge.preferredRoute(local.route, healthKit.route)
        if local.splits.isEmpty {
            merged.splits = healthKit.splits
        } else if healthKit.splits.isEmpty {
            merged.splits = local.splits
        } else {
            merged.splits = preferLocalShell ? local.splits : healthKit.splits
        }
        if merged.calories == nil {
            merged.calories = preferLocalShell ? healthKit.calories : local.calories
        }
        if merged.distanceMeters == nil || (merged.distanceMeters ?? 0) <= 0 {
            merged.distanceMeters = preferLocalShell ? healthKit.distanceMeters : local.distanceMeters
        }
        if merged.averageHeartRate == nil {
            merged.averageHeartRate = local.averageHeartRate ?? healthKit.averageHeartRate
        }
        if merged.maxHeartRate == nil {
            merged.maxHeartRate = local.maxHeartRate ?? healthKit.maxHeartRate
        }
        if merged.metadata.isEmpty {
            merged.metadata = preferLocalShell ? healthKit.metadata : local.metadata
        } else if preferLocalShell, local.metadata.allSatisfy({ $0.title != "Route Points" }), !merged.route.isEmpty {
            merged.metadata.append(
                FitnessWorkoutMetadataItem(title: "Route Points", value: "\(merged.route.count)")
            )
        }
        return merged
    }

    private func isDuplicate(_ local: WeeklyActivity, of healthActivity: WeeklyActivity) -> Bool {
        if let localSessionId = local.pulsarWorkoutSessionId,
           let healthSessionId = healthActivity.pulsarWorkoutSessionId,
           localSessionId == healthSessionId {
            return true
        }

        if let localUUID = local.workoutUUID,
           let healthUUID = healthActivity.workoutUUID,
           localUUID == healthUUID {
            return true
        }

        let startDelta = abs(local.startDate.timeIntervalSince(healthActivity.startDate))
        let durationDelta = abs(local.duration - healthActivity.duration)
        let bothOutdoorKind = local.category == healthActivity.category && local.category.isCardioTraining
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

        return bothOutdoorKind && startDelta < 180 && durationDelta < 300 && distanceLooksSame
    }

    private func shouldPreferLocalActivity(_ local: WeeklyActivity, over healthActivity: WeeklyActivity) -> Bool {
        Self.shouldPreferLocalActivity(local, over: healthActivity)
    }

    nonisolated private static func shouldPreferLocalActivity(_ local: WeeklyActivity, over healthActivity: WeeklyActivity) -> Bool {
        if local.source == .localGym {
            return true
        }

        if let localSessionId = local.pulsarWorkoutSessionId,
           let healthSessionId = healthActivity.pulsarWorkoutSessionId,
           localSessionId == healthSessionId {
            return true
        }

        // Prefer whichever side already carries a durable route so history does not
        // permanently drop GPS data when HealthKit sync is incomplete.
        if local.route.count > 1, healthActivity.route.count <= 1 {
            return true
        }

        return false
    }

    private func secondsUntilNextWeekBoundary() -> TimeInterval {
        let currentWeek = FitnessWeekCalculator.getWeekPeriod(for: .now, calendar: calendar)
        let nextBoundary = FitnessWeekCalculator.fetchEnd(for: currentWeek, calendar: calendar)
        return max(60, nextBoundary.timeIntervalSinceNow + 1)
    }
}
