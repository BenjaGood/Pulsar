//
//  FitnessMuscleMatrixModels.swift
//  Pulsar
//

import Foundation
import SwiftUI

enum MuscleMatrixGroup: String, CaseIterable, Identifiable, Codable, Hashable {
    case chest
    case back
    case shoulders
    case biceps
    case triceps
    case core
    case glutes
    case quads
    case hamstrings
    case calves
    case cardio

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest: "Chest"
        case .back: "Back"
        case .shoulders: "Shoulders"
        case .biceps: "Biceps"
        case .triceps: "Triceps"
        case .core: "Core"
        case .glutes: "Glutes"
        case .quads: "Quads"
        case .hamstrings: "Hamstrings"
        case .calves: "Calves"
        case .cardio: "Cardio"
        }
    }

    var compactName: String {
        switch self {
        case .hamstrings: "Hams"
        case .shoulders: "Delts"
        default: displayName
        }
    }

    var category: TrainingMatrixCategory {
        self == .cardio ? .cardio : .muscle
    }

    var symbolName: String {
        switch self {
        case .cardio: "waveform.path.ecg"
        default: "circle.fill"
        }
    }

    var accent: Color {
        switch self {
        case .chest, .shoulders, .triceps:
            Color(red: 0.60, green: 0.66, blue: 1.00)
        case .back, .biceps:
            Color(red: 0.38, green: 0.82, blue: 1.00)
        case .core:
            Color(red: 1.00, green: 0.72, blue: 0.32)
        case .glutes, .quads, .hamstrings, .calves:
            Color(red: 0.30, green: 0.92, blue: 0.72)
        case .cardio:
            Color(red: 0.15, green: 0.78, blue: 0.82)
        }
    }

    var trainingFamily: MuscleTrainingFamily? {
        switch self {
        case .chest, .shoulders, .triceps:
            .push
        case .back, .biceps:
            .pull
        case .glutes, .quads, .hamstrings, .calves:
            .legs
        case .core:
            .core
        case .cardio:
            nil
        }
    }
}

enum TrainingMatrixCategory: String, Hashable {
    case muscle
    case cardio
}

enum WeeklyTrainingFocus: String, Hashable {
    case readyToTrain
    case pushDominant
    case pullDominant
    case legsDominant
    case cardioDominant
    case balanced
    case undertrainedCore
    case lowerBodyHeavy
    case upperBodyHeavy

    var title: String {
        switch self {
        case .readyToTrain: "Ready to train"
        case .pushDominant: "Push dominant"
        case .pullDominant: "Pull dominant"
        case .legsDominant: "Legs dominant"
        case .cardioDominant: "Cardio dominant"
        case .balanced: "Balanced week"
        case .undertrainedCore: "Undertrained core"
        case .lowerBodyHeavy: "Lower-body heavy"
        case .upperBodyHeavy: "Upper-body heavy"
        }
    }

    var insightTitle: String {
        switch self {
        case .readyToTrain: "Ready for signal"
        case .pushDominant: "Push is leading"
        case .pullDominant: "Pull is leading"
        case .legsDominant: "Legs are leading"
        case .cardioDominant: "Cardio is leading"
        case .balanced: "Balanced training week"
        case .undertrainedCore: "Core needs attention"
        case .lowerBodyHeavy: "Lower body is leading"
        case .upperBodyHeavy: "Upper body is leading"
        }
    }
}

enum MuscleTrainingFamily: String, CaseIterable, Hashable {
    case push
    case pull
    case legs
    case core

    var title: String {
        switch self {
        case .push: "Push"
        case .pull: "Pull"
        case .legs: "Legs"
        case .core: "Core"
        }
    }
}

enum TrainingDay: Int, CaseIterable, Identifiable, Codable, Hashable {
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7
    case sunday = 1

    var id: Int { rawValue }

    var shortTitle: String {
        switch self {
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        case .sunday: "Sun"
        }
    }

    var fullTitle: String {
        switch self {
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        case .sunday: "Sunday"
        }
    }

    init(date: Date, calendar: Calendar = .autoupdatingCurrent) {
        let weekday = calendar.component(.weekday, from: date)
        self = TrainingDay(rawValue: weekday) ?? .monday
    }
}

enum MuscleIntensity: String, CaseIterable, Codable, Hashable {
    case none
    case light
    case medium
    case high

    init(sets: Int) {
        switch sets {
        case ..<1:
            self = .none
        case 1...2:
            self = .light
        case 3...5:
            self = .medium
        default:
            self = .high
        }
    }

    init(score: Double) {
        self.init(sets: Int(score.rounded(.toNearestOrAwayFromZero)))
    }

    init(cardioMinutes: Int) {
        switch cardioMinutes {
        case ..<1:
            self = .none
        case 1...15:
            self = .light
        case 16...35:
            self = .medium
        default:
            self = .high
        }
    }

    var title: String {
        switch self {
        case .none: "None"
        case .light: "Light"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    var rank: Int {
        switch self {
        case .none: 0
        case .light: 1
        case .medium: 2
        case .high: 3
        }
    }

    var dotScale: CGFloat {
        switch self {
        case .none: 0.48
        case .light: 0.68
        case .medium: 0.88
        case .high: 1.10
        }
    }

    var opacity: Double {
        switch self {
        case .none: 0.16
        case .light: 0.42
        case .medium: 0.68
        case .high: 1.0
        }
    }

    var glowRadius: CGFloat {
        switch self {
        case .none: 0
        case .light: 4
        case .medium: 8
        case .high: 14
        }
    }
}

struct MuscleMatrixCell: Identifiable, Hashable {
    var muscleGroup: MuscleMatrixGroup
    var day: TrainingDay
    var intensity: MuscleIntensity
    var sets: Int
    var exercises: [String]
    var minutes: Int?

    var id: String { "\(muscleGroup.rawValue)-\(day.rawValue)" }

    var isActive: Bool {
        sets > 0 || (muscleGroup.category == .cardio && (minutes ?? 0) > 0)
    }

    static func empty(muscleGroup: MuscleMatrixGroup, day: TrainingDay) -> MuscleMatrixCell {
        MuscleMatrixCell(
            muscleGroup: muscleGroup,
            day: day,
            intensity: .none,
            sets: 0,
            exercises: [],
            minutes: nil
        )
    }
}

struct WeeklyMuscleSummary: Hashable {
    var totalSessions: Int
    var totalSets: Int
    var totalCardioMinutes: Int
    var focusArea: String
    var balanceScore: Int
    var dominantFocus: WeeklyTrainingFocus
    var insightTitle: String
    var insight: String
    var topAreas: [String]
    var undertrainedAreas: [String]

    var compactLine: String {
        "\(totalSessions) activities · \(totalSets) sets · \(totalCardioMinutes) min cardio · \(focusArea) · \(balanceScore)% balance"
    }
}

struct MuscleMatrixRowSummary: Identifiable, Hashable {
    var muscleGroup: MuscleMatrixGroup
    var totalSets: Int
    var totalMinutes: Int
    var daysTrained: Int
    var highestIntensityDay: TrainingDay?
    var lastTrainedDay: TrainingDay?
    var exercises: [String]

    var id: String { muscleGroup.rawValue }
}

struct WeeklyMatrixRow: Identifiable, Hashable {
    var muscleGroup: MuscleMatrixGroup
    var name: String
    var category: TrainingMatrixCategory
    var colorToken: String
    var dayIntensities: [TrainingDay: MuscleIntensity]
    var weeklyScore: Double
    var weeklyCompletedSets: Int
    var weeklyMinutes: Int

    var id: String { muscleGroup.rawValue }
}

struct WeeklyMatrixViewState: Hashable {
    var weekStart: Date
    var weekEnd: Date
    var totalActivities: Int
    var totalSets: Int
    var totalCardioMinutes: Int
    var balanceScore: Int
    var dominantFocus: WeeklyTrainingFocus
    var rows: [WeeklyMatrixRow]
    var insightTitle: String
    var insightBody: String
    var topAreas: [String]
    var undertrainedAreas: [String]
}

enum MuscleMatrixSelection: Identifiable, Hashable {
    case cell(MuscleMatrixCell)
    case row(MuscleMatrixRowSummary)

    var id: String {
        switch self {
        case .cell(let cell):
            "cell-\(cell.id)"
        case .row(let summary):
            "row-\(summary.id)"
        }
    }
}

struct MuscleMatrixViewModel: Hashable {
    var week: WeekPeriod
    var days: [TrainingDay]
    var muscleGroups: [MuscleMatrixGroup]
    var cells: [MuscleMatrixCell]
    var weeklySummary: WeeklyMuscleSummary
    var rows: [WeeklyMatrixRow]
    var state: WeeklyMatrixViewState
    var currentDay: TrainingDay?
    var isUsingDemoData: Bool
    private var cellLookup: [String: MuscleMatrixCell]
    private var rowSummaries: [MuscleMatrixGroup: MuscleMatrixRowSummary]

    init(
        week: WeekPeriod,
        activities: [WeeklyActivity],
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now
    ) {
        self.week = week
        let matrixDays = TrainingDay.allCases
        let matrixGroups = MuscleMatrixGroup.allCases
        days = matrixDays
        muscleGroups = matrixGroups
        currentDay = week.isCurrentWeek ? TrainingDay(date: now, calendar: calendar) : nil

        let realCells = Self.cells(from: activities, calendar: calendar)
        let lookup = Dictionary(uniqueKeysWithValues: realCells.map { ($0.id, $0) })
        let summaries = Self.rowSummaries(from: lookup, days: matrixDays, groups: matrixGroups)
        let matrixRows = Self.rows(from: summaries, lookup: lookup, days: matrixDays, groups: matrixGroups)
        let summary = FitnessInsightEngine.summary(
            from: realCells,
            rowSummaries: summaries,
            activityCount: activities.count
        )
        cells = realCells
        cellLookup = lookup
        rowSummaries = summaries
        rows = matrixRows
        isUsingDemoData = false
        weeklySummary = summary
        state = WeeklyMatrixViewState(
            weekStart: week.startDate,
            weekEnd: week.endDate,
            totalActivities: summary.totalSessions,
            totalSets: summary.totalSets,
            totalCardioMinutes: summary.totalCardioMinutes,
            balanceScore: summary.balanceScore,
            dominantFocus: summary.dominantFocus,
            rows: matrixRows,
            insightTitle: summary.insightTitle,
            insightBody: summary.insight,
            topAreas: summary.topAreas,
            undertrainedAreas: summary.undertrainedAreas
        )
    }

    func cell(for muscleGroup: MuscleMatrixGroup, day: TrainingDay) -> MuscleMatrixCell {
        cellLookup["\(muscleGroup.rawValue)-\(day.rawValue)"]
            ?? .empty(muscleGroup: muscleGroup, day: day)
    }

    func rowSummary(for muscleGroup: MuscleMatrixGroup) -> MuscleMatrixRowSummary {
        rowSummaries[muscleGroup] ?? Self.rowSummary(for: muscleGroup, days: days, lookup: cellLookup)
    }

    private static func rowSummaries(
        from lookup: [String: MuscleMatrixCell],
        days: [TrainingDay],
        groups: [MuscleMatrixGroup]
    ) -> [MuscleMatrixGroup: MuscleMatrixRowSummary] {
        Dictionary(uniqueKeysWithValues: groups.map { group in
            (group, rowSummary(for: group, days: days, lookup: lookup))
        })
    }

    private static func rowSummary(
        for muscleGroup: MuscleMatrixGroup,
        days: [TrainingDay],
        lookup: [String: MuscleMatrixCell]
    ) -> MuscleMatrixRowSummary {
        let rowCells = days.map { day in
            lookup["\(muscleGroup.rawValue)-\(day.rawValue)"] ?? .empty(muscleGroup: muscleGroup, day: day)
        }
        let activeCells = rowCells.filter(\.isActive)
        let highest = activeCells.max { lhs, rhs in
            if lhs.intensity.rank == rhs.intensity.rank {
                return lhs.metricValue < rhs.metricValue
            }
            return lhs.intensity.rank < rhs.intensity.rank
        }
        let last = activeCells.last
        let exercises = Array(Set(activeCells.flatMap(\.exercises))).sorted()

        return MuscleMatrixRowSummary(
            muscleGroup: muscleGroup,
            totalSets: activeCells.reduce(0) { $0 + $1.sets },
            totalMinutes: activeCells.reduce(0) { $0 + ($1.minutes ?? 0) },
            daysTrained: activeCells.count,
            highestIntensityDay: highest?.day,
            lastTrainedDay: last?.day,
            exercises: exercises
        )
    }

    private static func rows(
        from summaries: [MuscleMatrixGroup: MuscleMatrixRowSummary],
        lookup: [String: MuscleMatrixCell],
        days: [TrainingDay],
        groups: [MuscleMatrixGroup]
    ) -> [WeeklyMatrixRow] {
        groups.map { group in
            let dayIntensities = Dictionary(uniqueKeysWithValues: days.map { day in
                let cell = lookup["\(group.rawValue)-\(day.rawValue)"] ?? .empty(muscleGroup: group, day: day)
                return (day, cell.intensity)
            })
            let summary = summaries[group] ?? rowSummary(for: group, days: days, lookup: lookup)
            let weeklyScore = group.category == .cardio ? Double(summary.totalMinutes) : Double(summary.totalSets)

            return WeeklyMatrixRow(
                muscleGroup: group,
                name: group.displayName,
                category: group.category,
                colorToken: group.rawValue,
                dayIntensities: dayIntensities,
                weeklyScore: weeklyScore,
                weeklyCompletedSets: summary.totalSets,
                weeklyMinutes: summary.totalMinutes
            )
        }
    }

    private static func cells(from activities: [WeeklyActivity], calendar: Calendar) -> [MuscleMatrixCell] {
        var cellsByID: [String: MuscleMatrixCell] = [:]

        for activity in activities {
            let day = TrainingDay(date: activity.startDate, calendar: calendar)
            for (group, score) in activity.muscleLoadByMatrixGroup where score > 0 {
                let id = "\(group.rawValue)-\(day.rawValue)"
                var cell = cellsByID[id] ?? .empty(muscleGroup: group, day: day)
                let sets = max(1, Int(score.rounded(.toNearestOrAwayFromZero)))
                cell.sets += sets
                cell.exercises = Array(Set(cell.exercises + (activity.muscleExercisesByMatrixGroup[group] ?? []))).sorted()
                cell.minutes = (cell.minutes ?? 0) + Int(activity.durationMinutes.rounded())
                cell.intensity = MuscleIntensity(sets: cell.sets)
                cellsByID[id] = cell
            }

            if activity.contributesToCardioMatrix {
                let id = "\(MuscleMatrixGroup.cardio.rawValue)-\(day.rawValue)"
                var cell = cellsByID[id] ?? .empty(muscleGroup: .cardio, day: day)
                let minutes = max(1, Int(activity.durationMinutes.rounded(.toNearestOrAwayFromZero)))
                cell.minutes = (cell.minutes ?? 0) + minutes
                cell.exercises = Array(Set(cell.exercises + [activity.displayName])).sorted()
                cell.intensity = MuscleIntensity(cardioMinutes: cell.minutes ?? 0)
                cellsByID[id] = cell
            }
        }

        return allCells(overlaying: Array(cellsByID.values))
    }

    private static func allCells(overlaying activeCells: [MuscleMatrixCell]) -> [MuscleMatrixCell] {
        var cellsByID = Dictionary(uniqueKeysWithValues: activeCells.map { ($0.id, $0) })
        for group in MuscleMatrixGroup.allCases {
            for day in TrainingDay.allCases {
                let empty = MuscleMatrixCell.empty(muscleGroup: group, day: day)
                cellsByID[empty.id, default: empty] = cellsByID[empty.id] ?? empty
            }
        }
        return MuscleMatrixGroup.allCases.flatMap { group in
            TrainingDay.allCases.map { day in
                cellsByID["\(group.rawValue)-\(day.rawValue)"] ?? .empty(muscleGroup: group, day: day)
            }
        }
    }

}

enum FitnessInsightEngine {
    static func summary(
        from cells: [MuscleMatrixCell],
        rowSummaries: [MuscleMatrixGroup: MuscleMatrixRowSummary],
        activityCount: Int
    ) -> WeeklyMuscleSummary {
        let totalSets = cells
            .filter { $0.muscleGroup.category == .muscle }
            .reduce(0) { $0 + $1.sets }
        let totalCardioMinutes = cells
            .filter { $0.muscleGroup == .cardio }
            .reduce(0) { $0 + ($1.minutes ?? 0) }
        let familyLoads = strengthFamilyLoads(from: cells)
        let balanceScore = balanceScore(from: familyLoads)
        let topAreas = topAreas(from: rowSummaries)
        let undertrainedAreas = undertrainedAreas(from: rowSummaries, totalSets: totalSets, totalCardioMinutes: totalCardioMinutes)
        let repeatedHighArea = consecutiveHighArea(from: cells)
        let focus = focus(
            familyLoads: familyLoads,
            totalSets: totalSets,
            totalCardioMinutes: totalCardioMinutes,
            balanceScore: balanceScore
        )
        let body = insightBody(
            focus: focus,
            familyLoads: familyLoads,
            repeatedHighArea: repeatedHighArea,
            undertrainedAreas: undertrainedAreas,
            totalSets: totalSets,
            totalCardioMinutes: totalCardioMinutes,
            balanceScore: balanceScore
        )

        return WeeklyMuscleSummary(
            totalSessions: activityCount,
            totalSets: totalSets,
            totalCardioMinutes: totalCardioMinutes,
            focusArea: focus.title,
            balanceScore: balanceScore,
            dominantFocus: focus,
            insightTitle: focus.insightTitle,
            insight: body,
            topAreas: topAreas,
            undertrainedAreas: undertrainedAreas
        )
    }

    private static func strengthFamilyLoads(from cells: [MuscleMatrixCell]) -> [MuscleTrainingFamily: Int] {
        Dictionary(grouping: cells.compactMap { cell -> (family: MuscleTrainingFamily, load: Int)? in
            guard let family = cell.muscleGroup.trainingFamily else { return nil }
            return (family, cell.sets)
        }, by: { $0.family })
            .mapValues { $0.reduce(0) { $0 + $1.load } }
    }

    private static func balanceScore(from familyLoads: [MuscleTrainingFamily: Int]) -> Int {
        let majorLoads = [MuscleTrainingFamily.push, .pull, .legs]
            .map { familyLoads[$0, default: 0] }
        guard let maxLoad = majorLoads.max(), maxLoad > 0 else { return 0 }
        let minLoad = majorLoads.min() ?? 0
        return Int((Double(minLoad) / Double(maxLoad) * 100).rounded())
    }

    private static func focus(
        familyLoads: [MuscleTrainingFamily: Int],
        totalSets: Int,
        totalCardioMinutes: Int,
        balanceScore: Int
    ) -> WeeklyTrainingFocus {
        guard totalSets > 0 || totalCardioMinutes > 0 else { return .readyToTrain }
        if totalSets == 0, totalCardioMinutes > 0 { return .cardioDominant }

        let push = familyLoads[.push, default: 0]
        let pull = familyLoads[.pull, default: 0]
        let legs = familyLoads[.legs, default: 0]
        let core = familyLoads[.core, default: 0]
        let upper = push + pull

        if core == 0, totalSets >= 8 {
            return .undertrainedCore
        }
        if totalCardioMinutes >= 45, totalSets < 8 {
            return .cardioDominant
        }
        if balanceScore >= 70, core > 0, totalCardioMinutes > 0 {
            return .balanced
        }
        if legs >= 6, legs >= Int(Double(max(upper, 1)) * 1.45) {
            return .lowerBodyHeavy
        }
        if upper >= 8, upper >= Int(Double(max(legs, 1)) * 1.75) {
            return .upperBodyHeavy
        }

        let dominant = [
            (MuscleTrainingFamily.push, push),
            (.pull, pull),
            (.legs, legs)
        ].max { $0.1 < $1.1 }

        switch dominant?.0 {
        case .push: return .pushDominant
        case .pull: return .pullDominant
        case .legs: return .legsDominant
        case .core, .none: return .balanced
        }
    }

    private static func topAreas(from summaries: [MuscleMatrixGroup: MuscleMatrixRowSummary]) -> [String] {
        summaries.values
            .filter { $0.totalSets > 0 || $0.totalMinutes > 0 }
            .sorted { lhs, rhs in
                let lhsScore = lhs.muscleGroup == .cardio ? lhs.totalMinutes : lhs.totalSets
                let rhsScore = rhs.muscleGroup == .cardio ? rhs.totalMinutes : rhs.totalSets
                if lhsScore == rhsScore {
                    return lhs.muscleGroup.displayName < rhs.muscleGroup.displayName
                }
                return lhsScore > rhsScore
            }
            .prefix(3)
            .map { $0.muscleGroup.displayName }
    }

    private static func undertrainedAreas(
        from summaries: [MuscleMatrixGroup: MuscleMatrixRowSummary],
        totalSets: Int,
        totalCardioMinutes: Int
    ) -> [String] {
        guard totalSets > 0 || totalCardioMinutes > 0 else { return [] }
        let priority: [MuscleMatrixGroup] = [.core, .back, .hamstrings, .glutes, .calves, .cardio, .chest, .shoulders, .biceps, .triceps, .quads]
        return priority.compactMap { group in
            guard let summary = summaries[group] else { return nil }
            let isUndertrained = group == .cardio ? summary.totalMinutes == 0 : summary.totalSets == 0
            return isUndertrained ? group.displayName : nil
        }
        .prefix(3)
        .map { $0 }
    }

    private static func insightBody(
        focus: WeeklyTrainingFocus,
        familyLoads: [MuscleTrainingFamily: Int],
        repeatedHighArea: String?,
        undertrainedAreas: [String],
        totalSets: Int,
        totalCardioMinutes: Int,
        balanceScore: Int
    ) -> String {
        if totalSets == 0, totalCardioMinutes == 0 {
            return "Log strength or cardio work to reveal your weekly training distribution."
        }
        if totalSets == 0, totalCardioMinutes > 0 {
            return "Cardio dominated this week. Add strength work for a more balanced training load."
        }
        if totalCardioMinutes >= 45, totalSets < 8 {
            return "Cardio is consistent this week. Strength volume is still low."
        }
        if let repeatedHighArea {
            return "\(repeatedHighArea) is already highly stimulated this week. Consider recovery or train a different area next."
        }
        if undertrainedAreas.contains("Core"), totalSets >= 8 {
            return "Core has not been trained this week. Add 2-3 core sets to improve balance."
        }
        if totalSets >= 10, totalCardioMinutes == 0 {
            return "Strength volume is building. Add light cardio or walking to round out the week."
        }
        if focus == .balanced || balanceScore >= 70 {
            return "Balanced training week. Keep distributing sets across push, pull, legs, and cardio."
        }

        switch focus {
        case .pushDominant:
            return "Push muscles are leading this week. Add \(lowestRecommendation(from: familyLoads, excluding: .push)) to improve balance."
        case .pullDominant:
            return "Pull muscles are leading this week. Add \(lowestRecommendation(from: familyLoads, excluding: .pull)) to improve balance."
        case .legsDominant, .lowerBodyHeavy:
            return "Legs received the highest stimulus. Consider upper-body work next."
        case .upperBodyHeavy:
            return "Upper body is carrying the week. Add glute, quad, or hamstring work next."
        case .undertrainedCore:
            return "Core has not been trained this week. Add 2-3 core sets to improve balance."
        case .cardioDominant:
            return "Cardio dominated this week. Add strength work for a more balanced training load."
        case .balanced:
            return "Balanced training week. Keep distributing sets across push, pull, legs, and cardio."
        case .readyToTrain:
            return "Log strength or cardio work to reveal your weekly training distribution."
        }
    }

    private static func consecutiveHighArea(from cells: [MuscleMatrixCell]) -> String? {
        for group in MuscleMatrixGroup.allCases where group.category == .muscle {
            let rowCells = TrainingDay.allCases.map { day in
                cells.first { $0.muscleGroup == group && $0.day == day } ?? .empty(muscleGroup: group, day: day)
            }
            for index in rowCells.indices.dropFirst() {
                guard rowCells[index - 1].intensity == .high, rowCells[index].intensity == .high else { continue }
                return group.displayName
            }
        }
        return nil
    }

    private static func lowestRecommendation(
        from familyLoads: [MuscleTrainingFamily: Int],
        excluding dominant: MuscleTrainingFamily
    ) -> String {
        let lowest = [MuscleTrainingFamily.push, .pull, .legs, .core]
            .filter { $0 != dominant }
            .min { familyLoads[$0, default: 0] < familyLoads[$1, default: 0] }

        switch lowest {
        case .push: return "chest or shoulder work"
        case .pull: return "back or biceps work"
        case .legs: return "quad or hamstring work"
        case .core: return "2-3 core sets"
        case .none: return "a complementary area"
        }
    }
}

private extension MuscleMatrixCell {
    var metricValue: Int {
        muscleGroup.category == .cardio ? (minutes ?? 0) : sets
    }
}

private extension WeeklyActivity {
    var contributesToCardioMatrix: Bool {
        if category.isCardioTraining {
            return durationMinutes > 0
        }

        let searchText = "\(workoutType) \(displayName)"
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        let cardioKeywords = [
            "cardio",
            "conditioning",
            "elliptical",
            "row",
            "rowing",
            "stair",
            "stairs",
            "stepper",
            "bike",
            "cycling",
            "cycle",
            "swim",
            "dance",
            "aerobic"
        ]
        return durationMinutes > 0 && cardioKeywords.contains { searchText.contains($0) }
    }
}
