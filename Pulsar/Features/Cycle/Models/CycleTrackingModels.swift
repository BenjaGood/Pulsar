//
//  CycleTrackingModels.swift
//  Pulsar
//

import Foundation

enum CyclePhase: String, CaseIterable, Identifiable, Codable, Equatable {
    case menstrual
    case follicular
    case ovulatory
    case luteal
    case uncertain

    var id: String { rawValue }

    var segmentStart: Double {
        switch self {
        case .menstrual: 0.00
        case .follicular: 0.18
        case .ovulatory: 0.48
        case .luteal: 0.58
        case .uncertain: 0.00
        }
    }

    var segmentEnd: Double {
        switch self {
        case .menstrual: 0.16
        case .follicular: 0.46
        case .ovulatory: 0.56
        case .luteal: 0.98
        case .uncertain: 1.00
        }
    }
}

enum PredictionConfidence: String, Codable, Equatable {
    case strong = "Strong"
    case moderate = "Moderate"
    case limited = "Limited"

    var symbolName: String {
        switch self {
        case .strong: "checkmark.seal.fill"
        case .moderate: "calendar.badge.clock"
        case .limited: "questionmark.diamond.fill"
        }
    }
}

enum BleedingIntensity: String, CaseIterable, Codable, Equatable {
    case spotting
    case light
    case moderate
    case heavy

    var title: String {
        switch self {
        case .spotting: "Spotting"
        case .light: "Light"
        case .moderate: "Moderate"
        case .heavy: "Heavy"
        }
    }
}

enum CycleSymptomKind: String, CaseIterable, Codable, Equatable {
    case cramps
    case bloating
    case fatigue
    case moodShift
    case breastTenderness
    case headache
    case cravings
    case lowEnergy
    case sleepDisruption
    case libido
    case cervicalFluid
    case nausea

    var title: String {
        switch self {
        case .cramps: "Cramps"
        case .bloating: "Bloating"
        case .fatigue: "Fatigue"
        case .moodShift: "Mood shift"
        case .breastTenderness: "Breast tenderness"
        case .headache: "Headache"
        case .cravings: "Cravings"
        case .lowEnergy: "Low energy"
        case .sleepDisruption: "Sleep disruption"
        case .libido: "Libido"
        case .cervicalFluid: "Cervical fluid"
        case .nausea: "Nausea"
        }
    }

    var shortTitle: String {
        switch self {
        case .moodShift: "Mood"
        case .breastTenderness: "Tender"
        case .sleepDisruption: "Sleep"
        case .cervicalFluid: "Fluid"
        default: title
        }
    }
}

struct BleedingLog: Identifiable, Codable, Equatable {
    var id: String { CycleTrackingCalculator.dateKey(for: date) }
    var date: Date
    var intensity: BleedingIntensity
    var note: String?

    init(date: Date, intensity: BleedingIntensity = .moderate, note: String? = nil) {
        self.date = date
        self.intensity = intensity
        self.note = note
    }
}

struct SymptomLog: Identifiable, Codable, Equatable {
    var id: String { "\(CycleTrackingCalculator.dateKey(for: date))-\(kind.rawValue)" }
    var date: Date
    var kind: CycleSymptomKind
    var severity: Int
    var note: String?

    init(date: Date, kind: CycleSymptomKind, severity: Int, note: String? = nil) {
        self.date = date
        self.kind = kind
        self.severity = severity
        self.note = note
    }
}

struct PeriodLog: Identifiable, Codable, Equatable {
    var id: Date { startDate }
    var startDate: Date
    var endDate: Date
    var bleedingLogs: [BleedingLog]

    var dayCount: Int {
        bleedingLogs.count
    }
}

struct CycleRecord: Identifiable, Codable, Equatable {
    var id: Date { period.startDate }
    var period: PeriodLog
    var nextPeriodStartDate: Date?
    var length: Int?
    var symptoms: [SymptomLog]
    var notesByDateKey: [String: String]

    var isComplete: Bool {
        length != nil
    }
}

struct CyclePrediction: Equatable {
    let cycleDay: Int?
    let phase: CyclePhase
    let confidence: PredictionConfidence
    let estimatedNextPeriodDate: Date?
    let estimatedOvulationStart: Date?
    let estimatedOvulationEnd: Date?
    let estimatedFertileWindowStart: Date?
    let estimatedFertileWindowEnd: Date?
    let estimatedCycleLength: Int
    let estimatedPeriodLength: Int
    let historyCycleCount: Int
    let cycleLengthVariability: Int?
    let notice: String?
}

struct CycleTrackingState: Codable, Equatable {
    var bleedingDates: [Date]
    var lastPeriodStartDate: Date?
    var averageCycleLength: Int
    var averagePeriodLength: Int
    var onboardingCompleted: Bool
    var notesByDateKey: [String: String]
    var bleedingLogs: [BleedingLog]
    var symptomLogs: [SymptomLog]

    init(
        bleedingDates: [Date] = [],
        lastPeriodStartDate: Date? = nil,
        averageCycleLength: Int = 28,
        averagePeriodLength: Int = 5,
        onboardingCompleted: Bool = false,
        notesByDateKey: [String: String] = [:],
        bleedingLogs: [BleedingLog] = [],
        symptomLogs: [SymptomLog] = []
    ) {
        self.bleedingDates = bleedingDates
        self.lastPeriodStartDate = lastPeriodStartDate
        self.averageCycleLength = averageCycleLength
        self.averagePeriodLength = averagePeriodLength
        self.onboardingCompleted = onboardingCompleted
        self.notesByDateKey = notesByDateKey
        self.bleedingLogs = bleedingLogs
        self.symptomLogs = symptomLogs
    }

    static let empty = CycleTrackingState()

    enum CodingKeys: String, CodingKey {
        case bleedingDates
        case lastPeriodStartDate
        case averageCycleLength
        case averagePeriodLength
        case onboardingCompleted
        case notesByDateKey
        case bleedingLogs
        case symptomLogs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bleedingDates = try container.decodeIfPresent([Date].self, forKey: .bleedingDates) ?? []
        lastPeriodStartDate = try container.decodeIfPresent(Date.self, forKey: .lastPeriodStartDate)
        averageCycleLength = try container.decodeIfPresent(Int.self, forKey: .averageCycleLength) ?? 28
        averagePeriodLength = try container.decodeIfPresent(Int.self, forKey: .averagePeriodLength) ?? 5
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        notesByDateKey = try container.decodeIfPresent([String: String].self, forKey: .notesByDateKey) ?? [:]
        bleedingLogs = try container.decodeIfPresent([BleedingLog].self, forKey: .bleedingLogs) ?? []
        symptomLogs = try container.decodeIfPresent([SymptomLog].self, forKey: .symptomLogs) ?? []
    }
}

struct CyclePeriodGroup: Identifiable, Codable, Equatable {
    var id: Date { startDate }
    let startDate: Date
    let endDate: Date
    let bleedingDates: [Date]

    var dayCount: Int {
        bleedingDates.count
    }
}

struct CycleTrackingSummary: Equatable {
    let periodGroups: [CyclePeriodGroup]
    let cycleRecords: [CycleRecord]
    let latestCycleStartDate: Date?
    let currentCycleDay: Int?
    let estimatedNextPeriodDate: Date?
    let estimatedOvulationStart: Date?
    let estimatedOvulationEnd: Date?
    let estimatedFertileWindowStart: Date?
    let estimatedFertileWindowEnd: Date?
    let bleedingLoggedCount: Int
    let averageCycleLength: Int
    let averagePeriodLength: Int
    let baselineCycleLength: Int
    let baselinePeriodLength: Int
    let cycleLengthSamples: [Int]
    let cycleLengthVariability: Int?
    let predictionConfidence: PredictionConfidence
    let cyclePatternNotice: String?
    let usesFallbackCycleLength: Bool
}

enum CycleTrackingCalculator {
    static let minimumCycleStartGapDays = 10
    static let baselineCycleLengthRange = 15...90
    static let baselinePeriodLengthRange = 1...14

    static func normalizedDates(_ dates: [Date], calendar: Calendar = .current) -> [Date] {
        Array(Set(dates.map { calendar.startOfDay(for: $0) })).sorted()
    }

    static func normalizedBleedingLogs(for state: CycleTrackingState, calendar: Calendar = .current) -> [BleedingLog] {
        var logsByKey: [String: BleedingLog] = [:]

        for date in normalizedDates(state.bleedingDates, calendar: calendar) {
            let key = dateKey(for: date, calendar: calendar)
            logsByKey[key] = BleedingLog(date: date, intensity: .moderate)
        }

        for log in state.bleedingLogs {
            let normalizedDate = calendar.startOfDay(for: log.date)
            let key = dateKey(for: normalizedDate, calendar: calendar)
            logsByKey[key] = BleedingLog(
                date: normalizedDate,
                intensity: log.intensity,
                note: sanitizedNote(log.note)
            )
        }

        return logsByKey.values.sorted { $0.date < $1.date }
    }

    static func normalizedSymptomLogs(_ logs: [SymptomLog], calendar: Calendar = .current) -> [SymptomLog] {
        var logsByKey: [String: SymptomLog] = [:]
        for log in logs {
            let normalizedDate = calendar.startOfDay(for: log.date)
            let normalizedLog = SymptomLog(
                date: normalizedDate,
                kind: log.kind,
                severity: max(1, min(log.severity, 3)),
                note: sanitizedNote(log.note)
            )
            logsByKey[normalizedLog.id] = normalizedLog
        }
        return logsByKey.values.sorted {
            if $0.date == $1.date { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.date < $1.date
        }
    }

    static func periodGroups(
        from bleedingDates: [Date],
        minimumGapDays: Int = minimumCycleStartGapDays,
        calendar: Calendar = .current
    ) -> [CyclePeriodGroup] {
        let dates = normalizedDates(bleedingDates, calendar: calendar)
        guard let firstDate = dates.first else { return [] }

        var groups: [CyclePeriodGroup] = []
        var currentDates = [firstDate]

        for date in dates.dropFirst() {
            guard let previousDate = currentDates.last else { continue }
            let gap = daysBetween(previousDate, date, calendar: calendar)
            if gap >= minimumGapDays {
                groups.append(makeGroup(from: currentDates))
                currentDates = [date]
            } else {
                currentDates.append(date)
            }
        }

        groups.append(makeGroup(from: currentDates))
        return groups
    }

    static func summary(
        for state: CycleTrackingState,
        today: Date = .now,
        calendar: Calendar = .current
    ) -> CycleTrackingSummary {
        let normalizedToday = calendar.startOfDay(for: today)
        let bleedingLogs = normalizedBleedingLogs(for: state, calendar: calendar)
        let normalizedBleedingDates = bleedingLogs.map(\.date)
        let groups = periodGroups(from: normalizedBleedingDates, calendar: calendar)
        let latestCycleStart = groups.last?.startDate ?? state.lastPeriodStartDate.map { calendar.startOfDay(for: $0) }
        let cycleLengths = cycleLengthSamples(from: groups, calendar: calendar)
        let averageCycleLength = computedAverageCycleLength(from: groups, calendar: calendar)
            ?? clamped(state.averageCycleLength, to: baselineCycleLengthRange)
        let averagePeriodLength = computedAveragePeriodLength(from: groups)
            ?? clamped(state.averagePeriodLength, to: baselinePeriodLengthRange)
        let currentCycleDay = latestCycleStart.map { max(1, daysBetween($0, normalizedToday, calendar: calendar) + 1) }
        let nextPeriodDate = latestCycleStart.map { addDays(averageCycleLength, to: $0, calendar: calendar) }
        let ovulationCenter = latestCycleStart.map {
            addDays(max(averagePeriodLength + 3, averageCycleLength - 14), to: $0, calendar: calendar)
        }
        let ovulationStart = ovulationCenter.map { addDays(-1, to: $0, calendar: calendar) }
        let ovulationEnd = ovulationCenter.map { addDays(1, to: $0, calendar: calendar) }
        let fertileStart = ovulationStart.map { addDays(-5, to: $0, calendar: calendar) }
        let fertileEnd = ovulationEnd
        let variability = cycleLengthVariability(from: cycleLengths)
        let notice = cyclePatternNotice(
            cycleLengths: cycleLengths,
            averageCycleLength: averageCycleLength,
            averagePeriodLength: averagePeriodLength,
            latestPeriodLength: groups.last?.dayCount,
            variability: variability
        )
        let predictionConfidence = predictionConfidence(
            periodGroupCount: groups.count,
            variability: variability,
            hasPatternNotice: notice != nil
        )

        return CycleTrackingSummary(
            periodGroups: groups,
            cycleRecords: cycleRecords(
                groups: groups,
                bleedingLogs: bleedingLogs,
                symptomLogs: normalizedSymptomLogs(state.symptomLogs, calendar: calendar),
                notesByDateKey: state.notesByDateKey,
                calendar: calendar
            ),
            latestCycleStartDate: latestCycleStart,
            currentCycleDay: currentCycleDay,
            estimatedNextPeriodDate: nextPeriodDate,
            estimatedOvulationStart: ovulationStart,
            estimatedOvulationEnd: ovulationEnd,
            estimatedFertileWindowStart: fertileStart,
            estimatedFertileWindowEnd: fertileEnd,
            bleedingLoggedCount: normalizedBleedingDates.count,
            averageCycleLength: averageCycleLength,
            averagePeriodLength: averagePeriodLength,
            baselineCycleLength: clamped(state.averageCycleLength, to: baselineCycleLengthRange),
            baselinePeriodLength: clamped(state.averagePeriodLength, to: baselinePeriodLengthRange),
            cycleLengthSamples: cycleLengths,
            cycleLengthVariability: variability,
            predictionConfidence: predictionConfidence,
            cyclePatternNotice: notice,
            usesFallbackCycleLength: cycleLengths.count < 2
        )
    }

    static func prediction(
        for state: CycleTrackingState,
        today: Date = .now,
        calendar: Calendar = .current
    ) -> CyclePrediction {
        let summary = summary(for: state, today: today, calendar: calendar)
        let phase = phase(
            cycleDay: summary.currentCycleDay ?? 0,
            predictedCycleLength: summary.averageCycleLength,
            predictedPeriodLength: summary.averagePeriodLength
        )

        return CyclePrediction(
            cycleDay: summary.currentCycleDay,
            phase: phase,
            confidence: summary.predictionConfidence,
            estimatedNextPeriodDate: summary.estimatedNextPeriodDate,
            estimatedOvulationStart: summary.estimatedOvulationStart,
            estimatedOvulationEnd: summary.estimatedOvulationEnd,
            estimatedFertileWindowStart: summary.estimatedFertileWindowStart,
            estimatedFertileWindowEnd: summary.estimatedFertileWindowEnd,
            estimatedCycleLength: summary.averageCycleLength,
            estimatedPeriodLength: summary.averagePeriodLength,
            historyCycleCount: summary.periodGroups.count,
            cycleLengthVariability: summary.cycleLengthVariability,
            notice: summary.cyclePatternNotice
        )
    }

    static func dateKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: calendar.startOfDay(for: date))
        return [
            components.year.map(String.init) ?? "0000",
            String(format: "%02d", components.month ?? 0),
            String(format: "%02d", components.day ?? 0)
        ].joined(separator: "-")
    }

    static func daysBetween(_ start: Date, _ end: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: start),
            to: calendar.startOfDay(for: end)
        ).day ?? 0
    }

    static func addDays(_ days: Int, to date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: date)) ?? date
    }

    static func computedAverageCycleLength(from groups: [CyclePeriodGroup], calendar: Calendar = .current) -> Int? {
        let usableIntervals = cycleLengthSamples(from: groups, calendar: calendar)
            .filter { (18...60).contains($0) }
            .suffix(6)
        guard !usableIntervals.isEmpty else { return nil }
        return Int((median(Array(usableIntervals)) ?? 28).rounded())
    }

    static func computedAveragePeriodLength(from groups: [CyclePeriodGroup]) -> Int? {
        let lengths = groups.map(\.dayCount).filter { (1...14).contains($0) }.suffix(6)
        guard !lengths.isEmpty else { return nil }
        return Int((median(Array(lengths)) ?? 5).rounded())
    }

    static func cycleLengthSamples(from groups: [CyclePeriodGroup], calendar: Calendar = .current) -> [Int] {
        let starts = groups.map(\.startDate).sorted()
        guard starts.count >= 2 else { return [] }
        return zip(starts, starts.dropFirst()).map { daysBetween($0, $1, calendar: calendar) }
    }

    static func cycleLengthVariability(from samples: [Int]) -> Int? {
        guard samples.count >= 2, let min = samples.min(), let max = samples.max() else { return nil }
        return max - min
    }

    static func phase(cycleDay: Int, predictedCycleLength: Int, predictedPeriodLength: Int) -> CyclePhase {
        guard cycleDay > 0 else { return .uncertain }
        if cycleDay <= predictedPeriodLength { return .menstrual }

        let ovulationDay = max(predictedPeriodLength + 3, predictedCycleLength - 14)
        if (ovulationDay - 2)...(ovulationDay + 1) ~= cycleDay {
            return .ovulatory
        }
        if cycleDay > ovulationDay + 1 {
            return .luteal
        }
        return .follicular
    }

    static func clamped(_ value: Int, to range: ClosedRange<Int>) -> Int {
        max(range.lowerBound, min(value, range.upperBound))
    }

    private static func cycleRecords(
        groups: [CyclePeriodGroup],
        bleedingLogs: [BleedingLog],
        symptomLogs: [SymptomLog],
        notesByDateKey: [String: String],
        calendar: Calendar
    ) -> [CycleRecord] {
        groups.enumerated().map { index, group in
            let nextStart = index + 1 < groups.count ? groups[index + 1].startDate : nil
            let endBoundary = nextStart ?? .distantFuture
            let periodBleedingLogs = bleedingLogs.filter { group.bleedingDates.contains(calendar.startOfDay(for: $0.date)) }
            let periodSymptoms = symptomLogs.filter { $0.date >= group.startDate && $0.date < endBoundary }
            let periodNotes = notesByDateKey.filter { key, _ in
                guard let date = date(fromKey: key, calendar: calendar) else { return false }
                return date >= group.startDate && date < endBoundary
            }
            return CycleRecord(
                period: PeriodLog(
                    startDate: group.startDate,
                    endDate: group.endDate,
                    bleedingLogs: periodBleedingLogs
                ),
                nextPeriodStartDate: nextStart,
                length: nextStart.map { daysBetween(group.startDate, $0, calendar: calendar) },
                symptoms: periodSymptoms,
                notesByDateKey: periodNotes
            )
        }
    }

    private static func predictionConfidence(
        periodGroupCount: Int,
        variability: Int?,
        hasPatternNotice: Bool
    ) -> PredictionConfidence {
        if periodGroupCount < 2 { return .limited }
        if hasPatternNotice { return .limited }
        if let variability, variability >= 9 { return .limited }
        if periodGroupCount >= 6 { return .strong }
        return .moderate
    }

    private static func cyclePatternNotice(
        cycleLengths: [Int],
        averageCycleLength: Int,
        averagePeriodLength: Int,
        latestPeriodLength: Int?,
        variability: Int?
    ) -> String? {
        if let latestPeriodLength, latestPeriodLength > 7 {
            return "Bleeding has been logged for more than 7 days. If this repeats or feels unusually heavy, consider sharing the pattern with a clinician."
        }
        if averagePeriodLength > 7 {
            return "Your logged periods are averaging longer than 7 days. Estimates stay conservative, and this may be worth discussing if it repeats."
        }
        if averageCycleLength < 21 || averageCycleLength > 35 {
            return "Your logged cycle length is outside the typical adult 21-35 day range. Predictions may shift, and a clinician can help interpret persistent patterns."
        }
        if let variability, variability >= 9 {
            return "Your cycle length has varied by \(variability) days. Pulsar will keep estimates broad until more regular history is logged."
        }
        if cycleLengths.contains(where: { $0 < 21 || $0 > 35 }) {
            return "At least one logged cycle was outside the typical adult range. If that pattern continues, consider reviewing it with a clinician."
        }
        return nil
    }

    private static func sanitizedNote(_ note: String?) -> String? {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func date(fromKey key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func makeGroup(from dates: [Date]) -> CyclePeriodGroup {
        let sortedDates = dates.sorted()
        return CyclePeriodGroup(
            startDate: sortedDates[0],
            endDate: sortedDates[sortedDates.count - 1],
            bleedingDates: sortedDates
        )
    }

    private static func median(_ values: [Int]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return Double(sorted[middle - 1] + sorted[middle]) / 2
        }
        return Double(sorted[middle])
    }
}
