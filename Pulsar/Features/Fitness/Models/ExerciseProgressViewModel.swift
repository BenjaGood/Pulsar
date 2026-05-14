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

    init(
        historyStore: PulsarGymWorkoutHistoryStore? = nil,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now
    ) {
        self.historyStore = historyStore ?? PulsarGymWorkoutHistoryStore()
        self.calendar = calendar
        self.selectedDate = calendar.startOfDay(for: now)
    }

    func load(displayUnit: PulsarWeightUnit, selectedWeek: WeekPeriod) async {
        historyStore.reload()
        alignSelectedDate(to: selectedWeek, displayUnit: displayUnit)
        await refresh(displayUnit: displayUnit, selectedWeek: selectedWeek, reloadsHistory: false)
    }

    func refresh(
        displayUnit: PulsarWeightUnit,
        selectedWeek: WeekPeriod,
        force: Bool = false,
        reloadsHistory: Bool = true
    ) async {
        if reloadsHistory {
            historyStore.reload()
        }
        isLoading = true
        await Task.yield()
        exerciseCountsByDay = ExerciseProgressService.exerciseCountsByDay(
            sessions: historyStore.sessions,
            week: selectedWeek,
            displayUnit: displayUnit,
            calendar: calendar
        )
        dailySummaries = ExerciseProgressService.getDailyExerciseSummary(
            date: selectedDate,
            sessions: historyStore.sessions,
            displayUnit: displayUnit,
            calendar: calendar
        )
        isLoading = false
    }

    func selectDate(_ date: Date, displayUnit: PulsarWeightUnit, selectedWeek: WeekPeriod) async {
        selectedDate = calendar.startOfDay(for: date)
        await refresh(displayUnit: displayUnit, selectedWeek: selectedWeek, force: true)
    }

    func selectWeek(_ week: WeekPeriod, displayUnit: PulsarWeightUnit) async {
        historyStore.reload()
        alignSelectedDate(to: week, displayUnit: displayUnit)
        await refresh(displayUnit: displayUnit, selectedWeek: week, force: true, reloadsHistory: false)
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

        let today = calendar.startOfDay(for: Date())
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
        self.historyStore = historyStore ?? PulsarGymWorkoutHistoryStore()
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
