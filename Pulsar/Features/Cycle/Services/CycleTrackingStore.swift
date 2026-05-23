//
//  CycleTrackingStore.swift
//  Pulsar
//

import Combine
import Foundation

@MainActor
final class CycleTrackingStore: ObservableObject {
    @Published private(set) var state: CycleTrackingState

    private let defaults: UserDefaults
    private let storageKey = "pulsar.cycle.trackingState.v1"
    private let calendar: Calendar
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        initialState: CycleTrackingState? = nil
    ) {
        self.defaults = defaults
        self.calendar = calendar
        if let initialState {
            state = Self.normalized(initialState, calendar: calendar)
            CycleTrackingDebugLogger.log("Initialized with injected state bleedingDays=\(state.bleedingLogs.count) symptoms=\(state.symptomLogs.count)")
        } else {
            state = Self.loadState(defaults: defaults, storageKey: storageKey, decoder: decoder, calendar: calendar)
            CycleTrackingDebugLogger.log("Loaded state onboarding=\(state.onboardingCompleted) bleedingDays=\(state.bleedingLogs.count) symptoms=\(state.symptomLogs.count)")
        }
    }

    var today: Date {
        calendar.startOfDay(for: .now)
    }

    var hasCycleData: Bool {
        state.onboardingCompleted && !state.bleedingLogs.isEmpty
    }

    var periodGroups: [CyclePeriodGroup] {
        CycleTrackingCalculator.periodGroups(from: state.bleedingDates, calendar: calendar)
    }

    var summary: CycleTrackingSummary {
        CycleTrackingCalculator.summary(for: state, today: today, calendar: calendar)
    }

    func completeOnboarding(
        lastPeriodStartDate: Date,
        averagePeriodLength: Int,
        averageCycleLength: Int
    ) {
        let start = calendar.startOfDay(for: lastPeriodStartDate)
        let periodLength = CycleTrackingCalculator.clamped(
            averagePeriodLength,
            to: CycleTrackingCalculator.baselinePeriodLengthRange
        )
        let bleedingLogs = (0..<periodLength).map { offset in
            BleedingLog(
                date: CycleTrackingCalculator.addDays(offset, to: start, calendar: calendar),
                intensity: .moderate
            )
        }

        state = recalculated(
            CycleTrackingState(
                bleedingDates: bleedingLogs.map(\.date),
                lastPeriodStartDate: start,
                averageCycleLength: CycleTrackingCalculator.clamped(
                    averageCycleLength,
                    to: CycleTrackingCalculator.baselineCycleLengthRange
                ),
                averagePeriodLength: periodLength,
                onboardingCompleted: true,
                notesByDateKey: state.notesByDateKey,
                bleedingLogs: bleedingLogs,
                symptomLogs: state.symptomLogs
            )
        )
        persist(reason: "completeOnboarding")
    }

    func saveCycleData(
        lastPeriodStartDate: Date,
        averagePeriodLength: Int,
        averageCycleLength: Int,
        bleedingDates: Set<Date>,
        symptomLogs: [SymptomLog]? = nil,
        notesByDateKey: [String: String]? = nil
    ) {
        let start = calendar.startOfDay(for: lastPeriodStartDate)
        let periodLength = CycleTrackingCalculator.clamped(
            averagePeriodLength,
            to: CycleTrackingCalculator.baselinePeriodLengthRange
        )
        let existingLogsByKey = Dictionary(
            uniqueKeysWithValues: state.bleedingLogs.map {
                (CycleTrackingCalculator.dateKey(for: $0.date, calendar: calendar), $0)
            }
        )
        let previousLatestKeys = Set(
            periodGroups.last?.bleedingDates.map { CycleTrackingCalculator.dateKey(for: $0, calendar: calendar) } ?? []
        )
        let setupPeriodDates = (0..<periodLength).map {
            CycleTrackingCalculator.addDays($0, to: start, calendar: calendar)
        }
        let setupKeys = Set(setupPeriodDates.map { CycleTrackingCalculator.dateKey(for: $0, calendar: calendar) })
        let retainedDates = bleedingDates
            .map { calendar.startOfDay(for: $0) }
            .filter { date in
                let key = CycleTrackingCalculator.dateKey(for: date, calendar: calendar)
                return !previousLatestKeys.contains(key) || setupKeys.contains(key)
            }
        let mergedDates = Set(retainedDates + setupPeriodDates)
        let mergedLogs = mergedDates.map { date in
            let key = CycleTrackingCalculator.dateKey(for: date, calendar: calendar)
            return existingLogsByKey[key].map {
                BleedingLog(date: date, intensity: $0.intensity, note: $0.note)
            } ?? BleedingLog(date: date, intensity: .moderate)
        }

        state = recalculated(
            CycleTrackingState(
                bleedingDates: Array(mergedDates),
                lastPeriodStartDate: start,
                averageCycleLength: CycleTrackingCalculator.clamped(
                    averageCycleLength,
                    to: CycleTrackingCalculator.baselineCycleLengthRange
                ),
                averagePeriodLength: periodLength,
                onboardingCompleted: true,
                notesByDateKey: notesByDateKey ?? state.notesByDateKey,
                bleedingLogs: mergedLogs,
                symptomLogs: symptomLogs ?? state.symptomLogs
            )
        )
        persist(reason: "saveCycleData")
    }

    func setBleedingDates(_ dates: Set<Date>) {
        let existingLogsByKey = Dictionary(
            uniqueKeysWithValues: state.bleedingLogs.map {
                (CycleTrackingCalculator.dateKey(for: $0.date, calendar: calendar), $0)
            }
        )
        let bleedingLogs = dates.map { date in
            let normalizedDate = calendar.startOfDay(for: date)
            let key = CycleTrackingCalculator.dateKey(for: normalizedDate, calendar: calendar)
            return existingLogsByKey[key].map {
                BleedingLog(date: normalizedDate, intensity: $0.intensity, note: $0.note)
            } ?? BleedingLog(date: normalizedDate, intensity: .moderate)
        }
        var nextState = state
        nextState.bleedingLogs = bleedingLogs
        nextState.bleedingDates = bleedingLogs.map(\.date)
        nextState.onboardingCompleted = !dates.isEmpty || nextState.onboardingCompleted
        state = recalculated(nextState)
        persist(reason: "setBleedingDates")
    }

    func saveDailyLog(
        date: Date,
        bleedingIntensity: BleedingIntensity?,
        symptoms: Set<CycleSymptomKind>,
        symptomSeverity: Int,
        note: String
    ) {
        let normalizedDate = calendar.startOfDay(for: date)
        let dateKey = CycleTrackingCalculator.dateKey(for: normalizedDate, calendar: calendar)
        var nextState = state
        var logsByKey = Dictionary(
            uniqueKeysWithValues: nextState.bleedingLogs.map {
                (CycleTrackingCalculator.dateKey(for: $0.date, calendar: calendar), $0)
            }
        )

        if let bleedingIntensity {
            logsByKey[dateKey] = BleedingLog(date: normalizedDate, intensity: bleedingIntensity)
        } else {
            logsByKey.removeValue(forKey: dateKey)
        }

        let existingSymptoms = nextState.symptomLogs.filter {
            !calendar.isDate($0.date, inSameDayAs: normalizedDate)
        }
        let newSymptoms = symptoms.map {
            SymptomLog(date: normalizedDate, kind: $0, severity: symptomSeverity)
        }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedNote.isEmpty {
            nextState.notesByDateKey.removeValue(forKey: dateKey)
        } else {
            nextState.notesByDateKey[dateKey] = trimmedNote
        }

        nextState.bleedingLogs = Array(logsByKey.values)
        nextState.bleedingDates = nextState.bleedingLogs.map(\.date)
        nextState.symptomLogs = existingSymptoms + newSymptoms
        nextState.onboardingCompleted = !nextState.bleedingLogs.isEmpty || nextState.onboardingCompleted
        state = recalculated(nextState)
        persist(reason: "saveDailyLog")
    }

    func toggleBleeding(on date: Date) {
        let normalizedDate = calendar.startOfDay(for: date)
        var dates = Set(state.bleedingDates.map { calendar.startOfDay(for: $0) })
        if dates.contains(normalizedDate) {
            dates.remove(normalizedDate)
        } else {
            dates.insert(normalizedDate)
        }
        setBleedingDates(dates)
    }

    func isBleedingDay(_ date: Date) -> Bool {
        let normalizedDate = calendar.startOfDay(for: date)
        return state.bleedingDates.contains(normalizedDate)
    }

    func symptoms(on date: Date) -> [SymptomLog] {
        let normalizedDate = calendar.startOfDay(for: date)
        return state.symptomLogs.filter { calendar.isDate($0.date, inSameDayAs: normalizedDate) }
    }

    func note(on date: Date) -> String {
        state.notesByDateKey[CycleTrackingCalculator.dateKey(for: date, calendar: calendar)] ?? ""
    }

    func bleedingLog(on date: Date) -> BleedingLog? {
        let key = CycleTrackingCalculator.dateKey(for: date, calendar: calendar)
        return state.bleedingLogs.first { CycleTrackingCalculator.dateKey(for: $0.date, calendar: calendar) == key }
    }

    // TODO: Import menstrual flow samples from HealthKit.
    func importHealthKitMenstrualFlowSamplesPlaceholder() {}

    // TODO: Export user-logged bleeding days to HealthKit if permissions are enabled.
    func exportUserLoggedBleedingDaysPlaceholder() {}

    private func recalculated(_ nextState: CycleTrackingState) -> CycleTrackingState {
        var normalizedState = Self.normalized(nextState, calendar: calendar)
        let groups = CycleTrackingCalculator.periodGroups(from: normalizedState.bleedingDates, calendar: calendar)
        if let latestStart = groups.last?.startDate {
            normalizedState.lastPeriodStartDate = latestStart
        }
        return normalizedState
    }

    private func persist(reason: String) {
        guard let data = try? encoder.encode(state) else {
            CycleTrackingDebugLogger.log("Persist failed reason=\(reason) encode=false")
            return
        }
        defaults.set(data, forKey: storageKey)
        CycleTrackingDebugLogger.log(
            "Persisted reason=\(reason) bytes=\(data.count) bleedingDays=\(state.bleedingLogs.count) symptoms=\(state.symptomLogs.count) latestStart=\(state.lastPeriodStartDate?.description ?? "none")"
        )
    }

    private static func loadState(
        defaults: UserDefaults,
        storageKey: String,
        decoder: JSONDecoder,
        calendar: Calendar
    ) -> CycleTrackingState {
        guard let data = defaults.data(forKey: storageKey) else {
            CycleTrackingDebugLogger.log("Load empty storage key=\(storageKey)")
            return .empty
        }

        do {
            let decoded = try decoder.decode(CycleTrackingState.self, from: data)
            let normalizedState = normalized(decoded, calendar: calendar)
            CycleTrackingDebugLogger.log(
                "Decoded state bytes=\(data.count) bleedingDays=\(normalizedState.bleedingLogs.count) symptoms=\(normalizedState.symptomLogs.count)"
            )
            return normalizedState
        } catch {
            CycleTrackingDebugLogger.log("Decode failed error=\(error.localizedDescription)")
            return .empty
        }
    }

    private static func normalized(_ state: CycleTrackingState, calendar: Calendar) -> CycleTrackingState {
        var normalizedState = state
        normalizedState.bleedingLogs = CycleTrackingCalculator.normalizedBleedingLogs(for: state, calendar: calendar)
        normalizedState.bleedingDates = normalizedState.bleedingLogs.map(\.date)
        normalizedState.symptomLogs = CycleTrackingCalculator.normalizedSymptomLogs(state.symptomLogs, calendar: calendar)
        normalizedState.lastPeriodStartDate = state.lastPeriodStartDate.map { calendar.startOfDay(for: $0) }
        normalizedState.averageCycleLength = CycleTrackingCalculator.clamped(
            state.averageCycleLength,
            to: CycleTrackingCalculator.baselineCycleLengthRange
        )
        normalizedState.averagePeriodLength = CycleTrackingCalculator.clamped(
            state.averagePeriodLength,
            to: CycleTrackingCalculator.baselinePeriodLengthRange
        )
        return normalizedState
    }
}

enum CycleTrackingDebugLogger {
    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[CycleTracking] \(message())")
        #endif
    }
}
