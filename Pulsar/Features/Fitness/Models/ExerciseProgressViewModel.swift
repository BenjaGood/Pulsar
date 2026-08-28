//
//  ExerciseProgressViewModel.swift
//  Pulsar
//

import Combine
import Foundation

@MainActor
final class ExerciseProgressViewModel: ObservableObject {
    @Published private(set) var selectedDate: Date
    @Published private(set) var dailySummaries: [DailyExerciseSummary] = []
    @Published private(set) var exerciseCountsByDay: [Date: Int] = [:]
    @Published private(set) var isLoading = false

    private let historyStore: PulsarGymWorkoutHistoryStore
    private let calendar: Calendar
    private let cacheFreshnessInterval: TimeInterval
    private let nowProvider: @MainActor () -> Date
    private var didLoadSessions = false
    private var loadedHistoryGeneration: HistoryGeneration?
    private var lastHistoryRefreshAt: Date?
    private var cachedCountsKey: CountsCacheKey?
    private var cachedExerciseCountsByDay: [Date: Int] = [:]
    private var cachedDailySummaryKey: DailySummaryCacheKey?
    private var cachedDailySummaries: [DailyExerciseSummary] = []

    init(
        historyStore: PulsarGymWorkoutHistoryStore? = nil,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now,
        cacheFreshnessInterval: TimeInterval = 90,
        nowProvider: @escaping @MainActor () -> Date = { .now }
    ) {
        self.historyStore = historyStore ?? .shared
        self.calendar = calendar
        self.cacheFreshnessInterval = cacheFreshnessInterval
        self.nowProvider = nowProvider
        self.selectedDate = calendar.startOfDay(for: now)
    }

    func load(displayUnit: PulsarWeightUnit, selectedWeek: WeekPeriod) async {
        refreshHistoryIfNeeded()
        alignSelectedDate(to: selectedWeek, displayUnit: displayUnit)
        await updateDerivedState(
            displayUnit: displayUnit,
            selectedWeek: selectedWeek,
            force: false
        )
    }

    func refreshIfNeeded(displayUnit: PulsarWeightUnit, selectedWeek: WeekPeriod) async {
        guard needsRefresh(displayUnit: displayUnit, selectedWeek: selectedWeek) else { return }

        refreshHistoryIfNeeded()
        await updateDerivedState(
            displayUnit: displayUnit,
            selectedWeek: selectedWeek,
            force: false
        )
    }

    func needsRefresh(displayUnit: PulsarWeightUnit, selectedWeek: WeekPeriod) -> Bool {
        let needsDerivedRefresh = cachedCountsKey != CountsCacheKey(
            weekID: selectedWeek.id,
            displayUnit: displayUnit
        ) || cachedDailySummaryKey != DailySummaryCacheKey(
            date: selectedDate,
            displayUnit: displayUnit
        )
        return !didLoadSessions || isHistoryStale || hasHistoryGenerationChanged || needsDerivedRefresh
    }

    func refresh(
        displayUnit: PulsarWeightUnit,
        selectedWeek: WeekPeriod,
        force: Bool = false,
        reloadsHistory: Bool = true
    ) async {
        if reloadsHistory {
            refreshHistoryIfNeeded(force: force)
        } else {
            ensureSessionsLoaded()
        }
        await updateDerivedState(
            displayUnit: displayUnit,
            selectedWeek: selectedWeek,
            force: force
        )
    }

    func selectDate(_ date: Date, displayUnit: PulsarWeightUnit, selectedWeek: WeekPeriod) async {
        selectedDate = calendar.startOfDay(for: date)
        await refresh(displayUnit: displayUnit, selectedWeek: selectedWeek, reloadsHistory: false)
    }

    func selectWeek(_ week: WeekPeriod, displayUnit: PulsarWeightUnit) async {
        ensureSessionsLoaded()
        alignSelectedDate(to: week, displayUnit: displayUnit)
        await refresh(displayUnit: displayUnit, selectedWeek: week, reloadsHistory: false)
    }

    func days(in week: WeekPeriod) -> [Date] {
        (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: week.startDate)
        }
    }

    private func alignSelectedDate(to week: WeekPeriod, displayUnit: PulsarWeightUnit) {
        let range = FitnessWeekCalculator.getFitnessWeekRange(for: week.startDate, calendar: calendar)
        if range.contains(selectedDate) {
            return
        }

        let today = calendar.startOfDay(for: nowProvider())
        if range.contains(today) {
            selectedDate = today
            return
        }

        let counts = ExerciseProgressService.exerciseCountsByDay(
            sessions: historyStore.sessions,
            week: week,
            displayUnit: displayUnit,
            calendar: calendar
        )
        selectedDate = counts.keys.sorted().last ?? week.startDate
    }

    private func ensureSessionsLoaded() {
        guard !didLoadSessions else { return }
        refreshHistoryIfNeeded(force: true)
    }

    private func refreshHistoryIfNeeded(force: Bool = false) {
        let generationBeforeReload = currentHistoryGeneration
        let generationChanged = loadedHistoryGeneration != nil && loadedHistoryGeneration != generationBeforeReload
        let shouldReloadStore = !didLoadSessions || force || isHistoryStale

        if shouldReloadStore {
            historyStore.reload()
        }

        let nextGeneration = currentHistoryGeneration
        let shouldInvalidateCaches = !didLoadSessions || force || generationChanged || loadedHistoryGeneration != nextGeneration
        didLoadSessions = true
        loadedHistoryGeneration = nextGeneration
        lastHistoryRefreshAt = nowProvider()

        if shouldInvalidateCaches {
            cachedCountsKey = nil
            cachedExerciseCountsByDay = [:]
            cachedDailySummaryKey = nil
            cachedDailySummaries = []
        }
    }

    private func updateDerivedState(
        displayUnit: PulsarWeightUnit,
        selectedWeek: WeekPeriod,
        force: Bool
    ) async {
        let countsKey = CountsCacheKey(weekID: selectedWeek.id, displayUnit: displayUnit)
        let summaryKey = DailySummaryCacheKey(date: selectedDate, displayUnit: displayUnit)
        let needsUpdate = force || cachedCountsKey != countsKey || cachedDailySummaryKey != summaryKey
        guard needsUpdate else { return }

        isLoading = true
        await Task.yield()
        guard !Task.isCancelled else {
            isLoading = false
            return
        }
        exerciseCountsByDay = cachedExerciseCounts(
            displayUnit: displayUnit,
            selectedWeek: selectedWeek,
            force: force
        )
        dailySummaries = cachedDailySummary(displayUnit: displayUnit, force: force)
        isLoading = false
    }

    private var currentHistoryGeneration: HistoryGeneration {
        let sessions = historyStore.sessions
        return HistoryGeneration(
            count: sessions.count,
            newestID: sessions.first?.id,
            newestFinishedAt: sessions.first?.finishedAt,
            newestElapsedSeconds: sessions.first?.elapsedSeconds,
            oldestID: sessions.last?.id
        )
    }

    private var hasHistoryGenerationChanged: Bool {
        guard let loadedHistoryGeneration else { return true }
        return loadedHistoryGeneration != currentHistoryGeneration
    }

    private var isHistoryStale: Bool {
        guard let lastHistoryRefreshAt else { return true }
        return nowProvider().timeIntervalSince(lastHistoryRefreshAt) > cacheFreshnessInterval
    }

    private func cachedExerciseCounts(
        displayUnit: PulsarWeightUnit,
        selectedWeek: WeekPeriod,
        force: Bool
    ) -> [Date: Int] {
        let key = CountsCacheKey(weekID: selectedWeek.id, displayUnit: displayUnit)
        if !force, cachedCountsKey == key {
            return cachedExerciseCountsByDay
        }
        let counts = ExerciseProgressService.exerciseCountsByDay(
            sessions: historyStore.sessions,
            week: selectedWeek,
            displayUnit: displayUnit,
            calendar: calendar
        )
        cachedCountsKey = key
        cachedExerciseCountsByDay = counts
        return counts
    }

    private func cachedDailySummary(
        displayUnit: PulsarWeightUnit,
        force: Bool
    ) -> [DailyExerciseSummary] {
        let key = DailySummaryCacheKey(date: selectedDate, displayUnit: displayUnit)
        if !force, cachedDailySummaryKey == key {
            return cachedDailySummaries
        }
        let summaries = ExerciseProgressService.getDailyExerciseSummary(
            date: selectedDate,
            sessions: historyStore.sessions,
            displayUnit: displayUnit,
            calendar: calendar
        )
        cachedDailySummaryKey = key
        cachedDailySummaries = summaries
        return summaries
    }

    private struct CountsCacheKey: Equatable {
        var weekID: String
        var displayUnit: PulsarWeightUnit
    }

    private struct DailySummaryCacheKey: Equatable {
        var date: Date
        var displayUnit: PulsarWeightUnit
    }

    private struct HistoryGeneration: Equatable {
        var count: Int
        var newestID: UUID?
        var newestFinishedAt: Date?
        var newestElapsedSeconds: Int?
        var oldestID: UUID?
    }
}

@MainActor
final class ExerciseProgressHistoryViewModel: ObservableObject {
    @Published private(set) var history: ExerciseProgressHistory
    @Published private(set) var isLoading = false

    private let target: ExerciseProgressLookup
    private let displayUnit: PulsarWeightUnit
    private let historyStore: PulsarGymWorkoutHistoryStore
    private let calendar: Calendar

    init(
        target: ExerciseProgressLookup,
        displayUnit: PulsarWeightUnit,
        historyStore: PulsarGymWorkoutHistoryStore? = nil,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.target = target
        self.displayUnit = displayUnit
        self.historyStore = historyStore ?? .shared
        self.calendar = calendar
        self.history = .empty(target: target, displayUnit: displayUnit)
    }

    func load() async {
        historyStore.reload()
        isLoading = true
        await Task.yield()
        history = ExerciseProgressService.getExerciseHistory(
            target: target,
            sessions: historyStore.sessions,
            displayUnit: displayUnit,
            calendar: calendar
        )
        isLoading = false
    }
}
