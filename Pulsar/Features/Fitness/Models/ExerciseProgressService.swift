//
//  ExerciseProgressService.swift
//  Pulsar
//

import Foundation

struct ExerciseProgressLookup: Identifiable, Hashable {
    var exerciseKey: String
    var exerciseId: String?
    var exerciseName: String
    var primaryMuscleGroup: PulsarMuscleGroup
    var muscleGroupName: String
    var equipment: String
    var displayUnit: PulsarWeightUnit

    var id: String { exerciseKey }

    init(
        exerciseId: String?,
        exerciseName: String,
        primaryMuscleGroup: PulsarMuscleGroup = .other,
        muscleGroupName: String? = nil,
        equipment: String = "Bodyweight",
        displayUnit: PulsarWeightUnit
    ) {
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.primaryMuscleGroup = primaryMuscleGroup
        self.muscleGroupName = muscleGroupName ?? primaryMuscleGroup.displayName
        self.equipment = equipment
        self.displayUnit = displayUnit
        self.exerciseKey = StrengthProgressAnalyticsService.exerciseKey(id: exerciseId, name: exerciseName)
    }

    init(summary: DailyExerciseSummary) {
        self.init(
            exerciseId: summary.exerciseId,
            exerciseName: summary.exerciseName,
            primaryMuscleGroup: summary.primaryMuscleGroup,
            muscleGroupName: summary.muscleGroupName,
            equipment: summary.equipment,
            displayUnit: summary.displayUnit
        )
    }

    init(exercise: PulsarGymWorkoutExerciseSession, displayUnit: PulsarWeightUnit? = nil) {
        self.init(
            exerciseId: exercise.exerciseId,
            exerciseName: exercise.exerciseName,
            primaryMuscleGroup: exercise.primaryMuscleGroup,
            muscleGroupName: exercise.primaryMuscleGroup.displayName,
            equipment: exercise.equipment,
            displayUnit: displayUnit ?? exercise.weightUnit
        )
    }
}

struct ExerciseSetProgressPoint: Identifiable, Hashable {
    var id: String
    var setNumber: Int
    var reps: Int
    var weight: Double
    var volume: Double
    var estimatedOneRepMax: Double?
}

struct ExerciseBestSet: Hashable {
    var reps: Int
    var weight: Double
    var volume: Double
    var estimatedOneRepMax: Double?

    func displayText(unit: PulsarWeightUnit, isBodyweight: Bool) -> String {
        if isBodyweight || weight <= 0.05 {
            return "\(reps) reps"
        }
        return "\(weight.formattedGymDecimal) \(unit.displayName) x \(reps)"
    }
}

struct DailyExerciseSummary: Identifiable, Hashable {
    var exerciseKey: String
    var exerciseId: String?
    var exerciseName: String
    var primaryMuscleGroup: PulsarMuscleGroup
    var muscleGroupName: String
    var matrixGroup: MuscleMatrixGroup?
    var equipment: String
    var displayUnit: PulsarWeightUnit
    var date: Date
    var sessionCount: Int
    var completedSets: Int
    var totalReps: Int
    var maxWeight: Double
    var bestSet: ExerciseBestSet?
    var totalVolume: Double
    var bestEstimatedOneRepMax: Double?
    var isBodyweight: Bool
    var setPoints: [ExerciseSetProgressPoint]

    var id: String { exerciseKey }
}

struct ExerciseHistoryPoint: Identifiable, Hashable {
    var id: String
    var date: Date
    var sessionCount: Int
    var completedSets: Int
    var totalReps: Int
    var maxWeight: Double
    var totalVolume: Double
    var bestSet: ExerciseBestSet?
    var bestEstimatedOneRepMax: Double?
}

struct ExerciseProgressHistory: Identifiable, Hashable {
    var target: ExerciseProgressLookup
    var primaryMuscleGroup: PulsarMuscleGroup
    var muscleGroupName: String
    var matrixGroup: MuscleMatrixGroup?
    var equipment: String
    var displayUnit: PulsarWeightUnit
    var isBodyweight: Bool
    var totalTimesTrained: Int
    var currentBestWeight: Double
    var bestWeightEver: Double
    var lifetimeBestSet: ExerciseBestSet?
    var lastPerformedAt: Date?
    var totalLifetimeVolume: Double
    var improvementPercent: Double?
    var points: [ExerciseHistoryPoint]

    var id: String { target.id }
    var hasTrendData: Bool { points.count > 1 }

    static func empty(target: ExerciseProgressLookup, displayUnit: PulsarWeightUnit) -> ExerciseProgressHistory {
        ExerciseProgressHistory(
            target: target,
            primaryMuscleGroup: target.primaryMuscleGroup,
            muscleGroupName: target.muscleGroupName,
            matrixGroup: ExerciseProgressService.primaryMatrixGroup(for: target.primaryMuscleGroup),
            equipment: target.equipment,
            displayUnit: displayUnit,
            isBodyweight: target.equipment.localizedCaseInsensitiveContains("bodyweight"),
            totalTimesTrained: 0,
            currentBestWeight: 0,
            bestWeightEver: 0,
            lifetimeBestSet: nil,
            lastPerformedAt: nil,
            totalLifetimeVolume: 0,
            improvementPercent: nil,
            points: []
        )
    }
}

enum ExerciseProgressService {
    static func getExercisesForDay(
        date: Date,
        sessions: [PulsarGymWorkoutSession],
        displayUnit: PulsarWeightUnit,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [DailyExerciseSummary] {
        getDailyExerciseSummary(
            date: date,
            sessions: sessions,
            displayUnit: displayUnit,
            calendar: calendar
        )
    }

    static func getDailyExerciseSummary(
        date: Date,
        sessions: [PulsarGymWorkoutSession],
        displayUnit: PulsarWeightUnit,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [DailyExerciseSummary] {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        let daySessions = completedSessions(from: sessions)
            .filter { $0.startedAt >= dayStart && $0.startedAt < dayEnd }

        let occurrences = exerciseOccurrences(from: daySessions, displayUnit: displayUnit)
        let grouped = Dictionary(grouping: occurrences, by: \.exerciseKey)

        return grouped.compactMap { _, values -> DailyExerciseSummary? in
            dailySummary(from: values, date: dayStart, displayUnit: displayUnit)
        }
        .sorted { lhs, rhs in
            if lhs.sessionCount != rhs.sessionCount {
                return lhs.sessionCount > rhs.sessionCount
            }
            if lhs.totalVolume != rhs.totalVolume {
                return lhs.totalVolume > rhs.totalVolume
            }
            return lhs.exerciseName.localizedCaseInsensitiveCompare(rhs.exerciseName) == .orderedAscending
        }
    }

    static func getExerciseHistory(
        target: ExerciseProgressLookup,
        sessions: [PulsarGymWorkoutSession],
        displayUnit: PulsarWeightUnit,
        calendar: Calendar = .autoupdatingCurrent
    ) -> ExerciseProgressHistory {
        let occurrences = exerciseOccurrences(from: completedSessions(from: sessions), displayUnit: displayUnit)
            .filter { $0.exerciseKey == target.exerciseKey }
        guard !occurrences.isEmpty else {
            return .empty(target: target, displayUnit: displayUnit)
        }

        let groupedByDay = Dictionary(grouping: occurrences) { occurrence in
            calendar.startOfDay(for: occurrence.sessionStartedAt)
        }

        let points = groupedByDay.compactMap { day, values -> ExerciseHistoryPoint? in
            historyPoint(from: values, date: day)
        }
        .sorted { $0.date < $1.date }

        let firstOccurrence = occurrences.sorted { $0.sessionStartedAt < $1.sessionStartedAt }.first
        let totalTimesTrained = Set(occurrences.map(\.sessionId)).count
        let currentBestWeight = points.last?.maxWeight ?? 0
        let bestWeightEver = points.map(\.maxWeight).max() ?? 0
        let lifetimeBestSet = calculateBestSet(occurrences.flatMap(\.sets))
        let lastPerformedAt = occurrences.map(\.sessionStartedAt).max()
        let totalLifetimeVolume = points.reduce(0) { $0 + $1.totalVolume }
        let isBodyweight = occurrences.allSatisfy(\.isBodyweight)
        let firstMetric = points.first.map { progressMetric(for: $0, isBodyweight: isBodyweight) } ?? 0
        let latestMetric = points.last.map { progressMetric(for: $0, isBodyweight: isBodyweight) } ?? 0
        let improvementPercent = percentDelta(current: latestMetric, previous: firstMetric)
        let resolvedGroup = firstOccurrence?.primaryMuscleGroup ?? target.primaryMuscleGroup
        let matrixGroup = firstOccurrence?.matrixGroup ?? primaryMatrixGroup(for: resolvedGroup)

        return ExerciseProgressHistory(
            target: target,
            primaryMuscleGroup: resolvedGroup,
            muscleGroupName: matrixGroup?.displayName ?? firstOccurrence?.muscleGroupName ?? target.muscleGroupName,
            matrixGroup: matrixGroup,
            equipment: firstOccurrence?.equipment ?? target.equipment,
            displayUnit: displayUnit,
            isBodyweight: isBodyweight,
            totalTimesTrained: totalTimesTrained,
            currentBestWeight: currentBestWeight,
            bestWeightEver: bestWeightEver,
            lifetimeBestSet: lifetimeBestSet,
            lastPerformedAt: lastPerformedAt,
            totalLifetimeVolume: totalLifetimeVolume,
            improvementPercent: improvementPercent,
            points: points
        )
    }

    static func getExerciseProgressSeries(
        target: ExerciseProgressLookup,
        sessions: [PulsarGymWorkoutSession],
        displayUnit: PulsarWeightUnit,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [ExerciseHistoryPoint] {
        getExerciseHistory(
            target: target,
            sessions: sessions,
            displayUnit: displayUnit,
            calendar: calendar
        ).points
    }

    static func exerciseCountsByDay(
        sessions: [PulsarGymWorkoutSession],
        week: WeekPeriod,
        displayUnit: PulsarWeightUnit,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [Date: Int] {
        let range = FitnessWeekCalculator.getFitnessWeekRange(for: week.startDate, calendar: calendar)
        let weekSessions = completedSessions(from: sessions)
            .filter { range.contains($0.startedAt) }
        let occurrences = exerciseOccurrences(from: weekSessions, displayUnit: displayUnit)
        let groupedByDay = Dictionary(grouping: occurrences) { occurrence in
            calendar.startOfDay(for: occurrence.sessionStartedAt)
        }
        return groupedByDay.mapValues { values in
            Set(values.map(\.exerciseKey)).count
        }
    }

    static func calculateBestSet(_ sets: [ExerciseSetProgressPoint]) -> ExerciseBestSet? {
        sets
            .filter { $0.reps > 0 }
            .map {
                ExerciseBestSet(
                    reps: $0.reps,
                    weight: $0.weight,
                    volume: $0.volume,
                    estimatedOneRepMax: $0.estimatedOneRepMax
                )
            }
            .max { lhs, rhs in
                let leftScore = bestSetScore(lhs)
                let rightScore = bestSetScore(rhs)
                if abs(leftScore - rightScore) > 0.001 {
                    return leftScore < rightScore
                }
                if abs(lhs.weight - rhs.weight) > 0.001 {
                    return lhs.weight < rhs.weight
                }
                return lhs.reps < rhs.reps
            }
    }

    static func calculateTotalVolume(_ sets: [ExerciseSetProgressPoint]) -> Double {
        sets.reduce(0) { $0 + max(0, $1.volume) }
    }

    static func calculateEstimated1RM(weight: Double, reps: Int) -> Double? {
        guard weight > 0, reps > 0 else { return nil }
        return weight * (1 + Double(reps) / 30)
    }

    static func primaryMatrixGroup(for group: PulsarMuscleGroup) -> MuscleMatrixGroup? {
        PulsarMuscleMatrixGroupMapper.groups(for: group).first { $0.category == .muscle }
    }
}

private extension ExerciseProgressService {
    static func completedSessions(from sessions: [PulsarGymWorkoutSession]) -> [PulsarGymWorkoutSession] {
        sessions
            .filter { $0.finishedAt != nil }
            .sorted { $0.startedAt < $1.startedAt }
    }

    static func exerciseOccurrences(
        from sessions: [PulsarGymWorkoutSession],
        displayUnit: PulsarWeightUnit
    ) -> [ExerciseOccurrence] {
        sessions.flatMap { session in
            session.exercises.compactMap { exercise in
                ExerciseOccurrence(session: session, exercise: exercise, displayUnit: displayUnit)
            }
        }
    }

    static func dailySummary(
        from occurrences: [ExerciseOccurrence],
        date: Date,
        displayUnit: PulsarWeightUnit
    ) -> DailyExerciseSummary? {
        guard let first = occurrences.sorted(by: { $0.sessionStartedAt < $1.sessionStartedAt }).first else { return nil }
        let setPoints = occurrences
            .sorted { $0.sessionStartedAt < $1.sessionStartedAt }
            .flatMap(\.sets)
        guard !setPoints.isEmpty else { return nil }
        let bestSet = calculateBestSet(setPoints)
        let totalVolume = calculateTotalVolume(setPoints)
        let maxWeight = setPoints.map(\.weight).max() ?? 0
        let totalReps = setPoints.reduce(0) { $0 + $1.reps }
        let isBodyweight = occurrences.allSatisfy(\.isBodyweight)

        return DailyExerciseSummary(
            exerciseKey: first.exerciseKey,
            exerciseId: first.exerciseId,
            exerciseName: first.exerciseName,
            primaryMuscleGroup: first.primaryMuscleGroup,
            muscleGroupName: first.matrixGroup?.displayName ?? first.muscleGroupName,
            matrixGroup: first.matrixGroup,
            equipment: first.equipment,
            displayUnit: displayUnit,
            date: date,
            sessionCount: Set(occurrences.map(\.sessionId)).count,
            completedSets: setPoints.count,
            totalReps: totalReps,
            maxWeight: maxWeight,
            bestSet: bestSet,
            totalVolume: totalVolume,
            bestEstimatedOneRepMax: setPoints.compactMap(\.estimatedOneRepMax).max(),
            isBodyweight: isBodyweight,
            setPoints: setPoints
        )
    }

    static func historyPoint(from occurrences: [ExerciseOccurrence], date: Date) -> ExerciseHistoryPoint? {
        let setPoints = occurrences.flatMap(\.sets)
        guard !setPoints.isEmpty else { return nil }
        let bestSet = calculateBestSet(setPoints)
        return ExerciseHistoryPoint(
            id: "\(Int(date.timeIntervalSince1970))-\(occurrences.first?.exerciseKey ?? UUID().uuidString)",
            date: date,
            sessionCount: Set(occurrences.map(\.sessionId)).count,
            completedSets: setPoints.count,
            totalReps: setPoints.reduce(0) { $0 + $1.reps },
            maxWeight: setPoints.map(\.weight).max() ?? 0,
            totalVolume: calculateTotalVolume(setPoints),
            bestSet: bestSet,
            bestEstimatedOneRepMax: setPoints.compactMap(\.estimatedOneRepMax).max()
        )
    }

    static func bestSetScore(_ bestSet: ExerciseBestSet) -> Double {
        if let estimatedOneRepMax = bestSet.estimatedOneRepMax, estimatedOneRepMax > 0 {
            return estimatedOneRepMax
        }
        if bestSet.volume > 0 {
            return bestSet.volume
        }
        return Double(bestSet.reps)
    }

    static func progressMetric(for point: ExerciseHistoryPoint, isBodyweight: Bool) -> Double {
        if isBodyweight {
            return Double(point.totalReps)
        }
        if let oneRepMax = point.bestEstimatedOneRepMax, oneRepMax > 0 {
            return oneRepMax
        }
        if point.maxWeight > 0 {
            return point.maxWeight
        }
        return point.totalVolume
    }

    static func percentDelta(current: Double, previous: Double) -> Double? {
        guard previous > 0, current > 0 else { return nil }
        return ((current - previous) / previous) * 100
    }
}

private struct ExerciseOccurrence: Hashable {
    var sessionId: UUID
    var sessionStartedAt: Date
    var exerciseKey: String
    var exerciseId: String?
    var exerciseName: String
    var primaryMuscleGroup: PulsarMuscleGroup
    var muscleGroupName: String
    var matrixGroup: MuscleMatrixGroup?
    var equipment: String
    var isBodyweight: Bool
    var sets: [ExerciseSetProgressPoint]

    init?(
        session: PulsarGymWorkoutSession,
        exercise: PulsarGymWorkoutExerciseSession,
        displayUnit: PulsarWeightUnit
    ) {
        let completedSets = exercise.sets
            .filter(\.isCompleted)
            .sorted { $0.setNumber < $1.setNumber }
        guard !completedSets.isEmpty else { return nil }

        let setPoints = completedSets.map { set -> ExerciseSetProgressPoint in
            let reps = max(0, set.completedReps ?? set.targetReps)
            let rawWeight = max(0, set.completedWeight ?? set.targetWeight)
            let displayWeight = exercise.weightUnit.convert(rawWeight, to: displayUnit)
            let volume = Double(reps) * displayWeight
            return ExerciseSetProgressPoint(
                id: "\(session.id.uuidString)-\(exercise.id.uuidString)-\(set.id.uuidString)",
                setNumber: set.setNumber,
                reps: reps,
                weight: displayWeight,
                volume: volume,
                estimatedOneRepMax: ExerciseProgressService.calculateEstimated1RM(weight: displayWeight, reps: reps)
            )
        }

        let matrixGroup = Self.matrixGroups(
            primaryMuscles: exercise.primaryMuscles,
            secondaryMuscles: exercise.secondaryMuscles,
            fallbackGroup: exercise.primaryMuscleGroup
        ).first
        let maxWeight = setPoints.map(\.weight).max() ?? 0

        self.sessionId = session.id
        self.sessionStartedAt = session.startedAt
        self.exerciseKey = StrengthProgressAnalyticsService.exerciseKey(id: exercise.exerciseId, name: exercise.exerciseName)
        self.exerciseId = exercise.exerciseId
        self.exerciseName = exercise.exerciseName
        self.primaryMuscleGroup = exercise.primaryMuscleGroup
        self.muscleGroupName = matrixGroup?.displayName ?? exercise.primaryMuscleGroup.displayName
        self.matrixGroup = matrixGroup
        self.equipment = exercise.equipment
        self.isBodyweight = maxWeight <= 0.05 || exercise.equipment.localizedCaseInsensitiveContains("bodyweight")
        self.sets = setPoints
    }

    private static func matrixGroups(
        primaryMuscles: [PulsarMuscle],
        secondaryMuscles: [PulsarMuscle],
        fallbackGroup: PulsarMuscleGroup
    ) -> [MuscleMatrixGroup] {
        var ordered: [MuscleMatrixGroup] = []

        func append(_ groups: [MuscleMatrixGroup]) {
            for group in groups where group.category == .muscle && !ordered.contains(group) {
                ordered.append(group)
            }
        }

        if primaryMuscles.isEmpty {
            append(PulsarMuscleMatrixGroupMapper.groups(for: fallbackGroup))
        } else {
            primaryMuscles.forEach { append(PulsarMuscleMatrixGroupMapper.groups(for: $0)) }
        }
        secondaryMuscles.forEach { append(PulsarMuscleMatrixGroupMapper.groups(for: $0)) }
        return ordered
    }
}
