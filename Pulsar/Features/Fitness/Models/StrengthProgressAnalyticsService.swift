//
//  StrengthProgressAnalyticsService.swift
//  Pulsar
//

import Foundation

enum StrengthProgressTimeRange: String, CaseIterable, Identifiable, Hashable {
    case fourWeeks
    case threeMonths
    case allTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fourWeeks: "4W"
        case .threeMonths: "3M"
        case .allTime: "All"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .fourWeeks: "4 weeks"
        case .threeMonths: "3 months"
        case .allTime: "All time"
        }
    }

    func startDate(now: Date, calendar: Calendar) -> Date? {
        switch self {
        case .fourWeeks:
            calendar.date(byAdding: .day, value: -28, to: now)
        case .threeMonths:
            calendar.date(byAdding: .month, value: -3, to: now)
        case .allTime:
            nil
        }
    }
}

enum StrengthProgressState: String, Codable, Hashable {
    case improving
    case stable
    case needsAttention

    var title: String {
        switch self {
        case .improving: "Improving"
        case .stable: "Stable"
        case .needsAttention: "Needs attention"
        }
    }

    var symbolName: String {
        switch self {
        case .improving: "arrow.up.right"
        case .stable: "equal"
        case .needsAttention: "exclamationmark.triangle.fill"
        }
    }
}

enum RoutineProgressionSuggestionKind: String, Codable, Hashable {
    case addLoad
    case repeatLoad
    case easeBackIn
    case holdForm
}

struct RoutineProgressionSuggestion: Codable, Hashable {
    var kind: RoutineProgressionSuggestionKind
    var title: String
    var detail: String
    var suggestedWeight: Double?
    var weightUnit: PulsarWeightUnit?
}

struct RoutinePerformanceSnapshot: Identifiable, Codable, Hashable {
    var routineId: UUID
    var exerciseKey: String
    var exerciseId: String?
    var exerciseName: String
    var lastPerformedAt: Date
    var lastSets: Int
    var lastReps: Int
    var lastWeight: Double
    var weightUnit: PulsarWeightUnit
    var lastRestSeconds: Int
    var bestWeight: Double
    var bestEstimatedOneRepMax: Double?
    var bestVolume: Double
    var completedAllPlannedSets: Bool
    var suggestion: RoutineProgressionSuggestion?

    var id: String { "\(routineId.uuidString)-\(exerciseKey)" }

    var lastPerformanceText: String {
        if lastWeight > 0 {
            return "\(lastWeight.formattedGymDecimal) \(weightUnit.displayName) x \(lastReps)"
        }
        return "\(lastReps) reps"
    }

    var bestPerformanceText: String {
        if bestWeight > 0 {
            return "\(bestWeight.formattedGymDecimal) \(weightUnit.displayName)"
        }
        return "\(Int(bestVolume.rounded())) reps"
    }
}

struct StrengthProgressPoint: Identifiable, Hashable {
    var id: String
    var date: Date
    var bestWeight: Double
    var estimatedOneRepMax: Double?
    var volume: Double
    var reps: Int
    var sets: Int
}

struct ExerciseProgressMetric: Identifiable, Hashable {
    var id: String
    var exerciseId: String?
    var name: String
    var muscleGroup: MuscleMatrixGroup?
    var muscleGroupName: String
    var equipment: String
    var isBodyweight: Bool
    var displayUnit: PulsarWeightUnit
    var bestWeightEver: Double
    var latestBestWeight: Double
    var previousBestWeight: Double?
    var weightDelta: Double?
    var latestEstimatedOneRepMax: Double?
    var bestEstimatedOneRepMax: Double?
    var latestVolume: Double
    var previousVolume: Double?
    var volumeDelta: Double?
    var latestReps: Int
    var previousReps: Int?
    var repsDelta: Int?
    var latestSets: Int
    var previousSets: Int?
    var setsDelta: Int?
    var lastPerformedAt: Date
    var performedCount: Int
    var state: StrengthProgressState
    var trendPoints: [StrengthProgressPoint]

    var latestPerformanceText: String {
        if isBodyweight {
            return "\(latestReps) reps"
        }
        return "\(latestBestWeight.formattedGymDecimal) \(displayUnit.displayName)"
    }

    var deltaText: String {
        if isBodyweight {
            guard let repsDelta else { return "New signal" }
            if repsDelta > 0 { return "+\(repsDelta) reps" }
            if repsDelta < 0 { return "\(repsDelta) reps" }
            return "Flat reps"
        }

        guard let weightDelta else { return "New signal" }
        if abs(weightDelta) < 0.05 { return "Flat load" }
        let prefix = weightDelta > 0 ? "+" : ""
        return "\(prefix)\(weightDelta.formattedGymDecimal) \(displayUnit.displayName)"
    }

    var volumeDeltaText: String {
        guard let volumeDelta else { return "First session" }
        if abs(volumeDelta) < 0.05 { return "Even volume" }
        let prefix = volumeDelta > 0 ? "+" : ""
        let suffix = isBodyweight ? " reps" : " \(displayUnit.displayName)"
        return "\(prefix)\(volumeDelta.formattedGymDecimal)\(suffix)"
    }
}

struct MuscleGroupProgressMetric: Identifiable, Hashable {
    var id: String { group.rawValue }
    var group: MuscleMatrixGroup
    var currentVolume: Double
    var previousVolume: Double
    var volumeDeltaPercent: Double
    var sessionsCount: Int
    var lastTrainedAt: Date?
    var consistencyScore: Int
    var state: StrengthProgressState

    var statusTitle: String { state.title }
}

struct RoutineProgressMetric: Identifiable, Hashable {
    var id: UUID { routineId }
    var routineId: UUID
    var routineName: String
    var latestDate: Date
    var previousDate: Date?
    var latestVolume: Double
    var previousVolume: Double?
    var volumeDelta: Double?
    var completedSetsDelta: Int?
    var averageWeightDelta: Double?
    var durationDeltaSeconds: Int?
}

struct StrengthProgressInsight: Hashable {
    var title: String
    var message: String
    var symbolName: String
    var state: StrengthProgressState

    static let empty = StrengthProgressInsight(
        title: "Progress intelligence locked",
        message: "Complete a few gym workouts to unlock progression insights.",
        symbolName: "lock.fill",
        state: .stable
    )
}

struct StrengthProgressDashboard: Hashable {
    var timeRange: StrengthProgressTimeRange
    var displayUnit: PulsarWeightUnit
    var sessionsAnalyzed: Int
    var generatedAt: Date
    var exercises: [ExerciseProgressMetric]
    var muscles: [MuscleGroupProgressMetric]
    var routines: [RoutineProgressMetric]
    var insight: StrengthProgressInsight

    static func empty(timeRange: StrengthProgressTimeRange = .threeMonths, displayUnit: PulsarWeightUnit = .kilograms) -> StrengthProgressDashboard {
        StrengthProgressDashboard(
            timeRange: timeRange,
            displayUnit: displayUnit,
            sessionsAnalyzed: 0,
            generatedAt: Date(),
            exercises: [],
            muscles: [],
            routines: [],
            insight: .empty
        )
    }

    var hasProgressData: Bool {
        sessionsAnalyzed > 0 && !exercises.isEmpty
    }

    var topExercise: ExerciseProgressMetric? {
        exercises.max { lhs, rhs in
            lhs.progressScore < rhs.progressScore
        }
    }

    var topMuscle: MuscleGroupProgressMetric? {
        muscles
            .filter { $0.state == .improving }
            .max { lhs, rhs in
                lhs.volumeDeltaPercent < rhs.volumeDeltaPercent
            }
    }
}

private extension ExerciseProgressMetric {
    var progressScore: Double {
        if isBodyweight {
            return Double(repsDelta ?? 0)
        }
        return weightDelta ?? 0
    }
}

enum StrengthProgressAnalyticsService {
    static func dashboard(
        sessions: [PulsarGymWorkoutSession],
        timeRange: StrengthProgressTimeRange,
        displayUnit: PulsarWeightUnit,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> StrengthProgressDashboard {
        let completedSessions = completedGymSessions(from: sessions)
        let startDate = timeRange.startDate(now: now, calendar: calendar)
        let filteredSessions = completedSessions.filter { session in
            guard let startDate else { return true }
            return session.startedAt >= startDate
        }
        let allRollups = makeExerciseRollups(from: completedSessions, displayUnit: displayUnit)
        let filteredRollups = allRollups.filter { rollup in
            guard let startDate else { return true }
            return rollup.date >= startDate
        }

        let exercises = makeExerciseMetrics(
            allRollups: allRollups,
            filteredRollups: filteredRollups,
            displayUnit: displayUnit,
            now: now
        )
        let muscles = makeMuscleMetrics(
            rollups: filteredRollups,
            startDate: startDate,
            now: now,
            calendar: calendar
        )
        let routines = makeRoutineMetrics(
            sessions: filteredSessions,
            displayUnit: displayUnit
        )
        let insight = makeInsight(exercises: exercises, muscles: muscles, routines: routines)

        return StrengthProgressDashboard(
            timeRange: timeRange,
            displayUnit: displayUnit,
            sessionsAnalyzed: filteredSessions.count,
            generatedAt: now,
            exercises: exercises,
            muscles: muscles,
            routines: routines,
            insight: insight
        )
    }

    static func routineWithLatestPerformanceOverlay(
        _ routine: PulsarRoutine,
        sessions: [PulsarGymWorkoutSession],
        displayUnit: PulsarWeightUnit,
        now: Date = Date()
    ) -> PulsarRoutine {
        let snapshots = performanceSnapshots(
            for: routine,
            sessions: sessions,
            displayUnit: displayUnit,
            now: now
        )
        guard !snapshots.isEmpty else { return routine }

        var nextRoutine = routine
        nextRoutine.exercises = routine.exercises.map { routineExercise in
            let key = exerciseKey(id: routineExercise.exercise.id, name: routineExercise.exercise.name)
            guard let snapshot = snapshots[key] else { return routineExercise }

            var nextExercise = routineExercise
            nextExercise.plannedSets = max(1, snapshot.lastSets)
            nextExercise.plannedReps = max(1, snapshot.lastReps)
            nextExercise.plannedWeight = max(0, snapshot.lastWeight)
            nextExercise.weightUnit = snapshot.weightUnit
            nextExercise.plannedRestSeconds = max(0, snapshot.lastRestSeconds)
            return nextExercise
        }
        nextRoutine.supersetGroups = PulsarRoutine.normalizedSupersetGroups(nextRoutine.supersetGroups, for: nextRoutine.exercises)
        for group in nextRoutine.supersetGroups {
            for exerciseID in group.exerciseIds {
                guard let exerciseIndex = nextRoutine.exercises.firstIndex(where: { $0.id == exerciseID }) else { continue }
                nextRoutine.exercises[exerciseIndex].plannedSets = group.sharedSetCount
                nextRoutine.exercises[exerciseIndex].supersetGroupId = group.id
                nextRoutine.exercises[exerciseIndex].supersetOrder = group.exerciseIds.firstIndex(of: exerciseID)
            }
        }
        return nextRoutine
    }

    static func performanceSnapshots(
        for routine: PulsarRoutine,
        sessions: [PulsarGymWorkoutSession],
        displayUnit: PulsarWeightUnit,
        now: Date = Date()
    ) -> [String: RoutinePerformanceSnapshot] {
        let routineSessions = completedGymSessions(from: sessions)
            .filter { $0.routineId == routine.id }
        guard !routineSessions.isEmpty else { return [:] }

        let rollups = makeExerciseRollups(from: routineSessions, displayUnit: displayUnit)
        var snapshots: [String: RoutinePerformanceSnapshot] = [:]

        for routineExercise in routine.exercises {
            let key = exerciseKey(id: routineExercise.exercise.id, name: routineExercise.exercise.name)
            let exerciseRollups = rollups
                .filter { $0.exerciseKey == key }
                .sorted { $0.date < $1.date }
            guard let latest = exerciseRollups.last else { continue }

            let previous = exerciseRollups.dropLast().last
            let bestWeight = exerciseRollups.map(\.bestWeightDisplay).max() ?? 0
            let bestOneRepMax = exerciseRollups.compactMap(\.estimatedOneRepMaxDisplay).max()
            let bestVolume = exerciseRollups.map(\.progressVolume).max() ?? 0
            let suggestion = makeSuggestion(
                latest: latest,
                previous: previous,
                displayUnit: displayUnit,
                now: now
            )

            snapshots[key] = RoutinePerformanceSnapshot(
                routineId: routine.id,
                exerciseKey: key,
                exerciseId: routineExercise.exercise.id,
                exerciseName: routineExercise.exercise.name,
                lastPerformedAt: latest.date,
                lastSets: latest.completedSets,
                lastReps: max(1, latest.lastSetReps),
                lastWeight: latest.lastSetWeightDisplay,
                weightUnit: displayUnit,
                lastRestSeconds: latest.plannedRestSeconds,
                bestWeight: bestWeight,
                bestEstimatedOneRepMax: bestOneRepMax,
                bestVolume: bestVolume,
                completedAllPlannedSets: latest.completedSets >= latest.plannedSets,
                suggestion: suggestion
            )
        }

        return snapshots
    }

    static func exerciseKey(id: String?, name: String) -> String {
        if let id, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return id
        }
        return name.normalizedPulsarIdentifier(prefix: "exercise")
    }

    static func completedVolume(
        for session: PulsarGymWorkoutSession,
        displayUnit: PulsarWeightUnit
    ) -> Double {
        session.exercises.reduce(0) { partial, exercise in
            partial + exercise.sets.reduce(0) { setPartial, set in
                guard set.isCompleted else { return setPartial }
                let reps = Double(set.completedReps ?? set.targetReps)
                let weight = exercise.weightUnit.convert(set.completedWeight ?? set.targetWeight, to: displayUnit)
                return setPartial + reps * max(0, weight)
            }
        }
    }
}

private extension StrengthProgressAnalyticsService {
    static func completedGymSessions(from sessions: [PulsarGymWorkoutSession]) -> [PulsarGymWorkoutSession] {
        sessions
            .filter { $0.finishedAt != nil }
            .sorted { $0.startedAt < $1.startedAt }
    }

    static func makeExerciseRollups(
        from sessions: [PulsarGymWorkoutSession],
        displayUnit: PulsarWeightUnit
    ) -> [ExerciseSessionRollup] {
        sessions.flatMap { session in
            session.exercises.compactMap { exercise in
                ExerciseSessionRollup(
                    session: session,
                    exercise: exercise,
                    displayUnit: displayUnit
                )
            }
        }
    }

    static func makeExerciseMetrics(
        allRollups: [ExerciseSessionRollup],
        filteredRollups: [ExerciseSessionRollup],
        displayUnit: PulsarWeightUnit,
        now: Date
    ) -> [ExerciseProgressMetric] {
        let filteredByExercise = Dictionary(grouping: filteredRollups, by: \.exerciseKey)
        let allByExercise = Dictionary(grouping: allRollups, by: \.exerciseKey)

        return filteredByExercise.compactMap { key, filteredValues -> ExerciseProgressMetric? in
            let filtered = filteredValues.sorted { $0.date < $1.date }
            guard let latest = filtered.last else { return nil }
            let all = (allByExercise[key] ?? filtered).sorted { $0.date < $1.date }
            let previous = filtered.dropLast().last
            let isBodyweight = latest.isBodyweight
            let weightDelta = previous.map { latest.bestWeightDisplay - $0.bestWeightDisplay }
            let repsDelta = previous.map { latest.totalReps - $0.totalReps }
            let volumeDelta = previous.map { latest.progressVolume - $0.progressVolume }
            let setsDelta = previous.map { latest.completedSets - $0.completedSets }
            let lastPerformedAge = now.timeIntervalSince(latest.date)
            let state = exerciseState(
                isBodyweight: isBodyweight,
                weightDelta: weightDelta,
                repsDelta: repsDelta,
                performedCount: filtered.count,
                lastPerformedAge: lastPerformedAge
            )
            let matrixGroups = latest.matrixGroups
            let primaryMatrixGroup = matrixGroups.first

            return ExerciseProgressMetric(
                id: key,
                exerciseId: latest.exerciseId,
                name: latest.exerciseName,
                muscleGroup: primaryMatrixGroup,
                muscleGroupName: primaryMatrixGroup?.displayName ?? latest.primaryMuscleGroup.displayName,
                equipment: latest.equipment,
                isBodyweight: isBodyweight,
                displayUnit: displayUnit,
                bestWeightEver: all.map(\.bestWeightDisplay).max() ?? latest.bestWeightDisplay,
                latestBestWeight: latest.bestWeightDisplay,
                previousBestWeight: previous?.bestWeightDisplay,
                weightDelta: weightDelta,
                latestEstimatedOneRepMax: latest.estimatedOneRepMaxDisplay,
                bestEstimatedOneRepMax: all.compactMap(\.estimatedOneRepMaxDisplay).max(),
                latestVolume: latest.progressVolume,
                previousVolume: previous?.progressVolume,
                volumeDelta: volumeDelta,
                latestReps: latest.totalReps,
                previousReps: previous?.totalReps,
                repsDelta: repsDelta,
                latestSets: latest.completedSets,
                previousSets: previous?.completedSets,
                setsDelta: setsDelta,
                lastPerformedAt: latest.date,
                performedCount: filtered.count,
                state: state,
                trendPoints: filtered.suffix(12).map { $0.progressPoint }
            )
        }
        .sorted { lhs, rhs in
            if lhs.state != rhs.state {
                return lhs.state.sortRank > rhs.state.sortRank
            }
            return lhs.lastPerformedAt > rhs.lastPerformedAt
        }
    }

    static func makeMuscleMetrics(
        rollups: [ExerciseSessionRollup],
        startDate: Date?,
        now: Date,
        calendar: Calendar
    ) -> [MuscleGroupProgressMetric] {
        let activeGroups = MuscleMatrixGroup.allCases.filter { $0.category == .muscle }
        let comparisonStart = calendar.date(byAdding: .day, value: -28, to: now) ?? now
        let previousStart = calendar.date(byAdding: .day, value: -56, to: now) ?? now
        let effectiveStart = startDate ?? rollups.first?.date ?? previousStart
        let weeksInRange = max(1, numberOfWeeks(from: effectiveStart, to: now, calendar: calendar))

        return activeGroups.map { group in
            let groupRollups = rollups.filter { $0.matrixGroups.contains(group) }
            let recentVolume = groupRollups
                .filter { $0.date >= comparisonStart }
                .reduce(0) { $0 + $1.progressVolume }
            let previousVolume = groupRollups
                .filter { $0.date >= previousStart && $0.date < comparisonStart }
                .reduce(0) { $0 + $1.progressVolume }
            let deltaPercent = percentDelta(current: recentVolume, previous: previousVolume)
            let weeksTrained = Set(groupRollups.map { weekKey(for: $0.date, calendar: calendar) }).count
            let consistency = min(100, Int((Double(weeksTrained) / Double(weeksInRange) * 100).rounded()))
            let lastTrained = groupRollups.map(\.date).max()
            let age = lastTrained.map { now.timeIntervalSince($0) } ?? .greatestFiniteMagnitude
            let state = muscleState(recentVolume: recentVolume, previousVolume: previousVolume, lastTrainedAge: age)

            return MuscleGroupProgressMetric(
                group: group,
                currentVolume: recentVolume,
                previousVolume: previousVolume,
                volumeDeltaPercent: deltaPercent,
                sessionsCount: Set(groupRollups.map(\.sessionId)).count,
                lastTrainedAt: lastTrained,
                consistencyScore: consistency,
                state: state
            )
        }
    }

    static func makeRoutineMetrics(
        sessions: [PulsarGymWorkoutSession],
        displayUnit: PulsarWeightUnit
    ) -> [RoutineProgressMetric] {
        Dictionary(grouping: sessions, by: \.routineId)
            .compactMap { routineId, routineSessions -> RoutineProgressMetric? in
                let sorted = routineSessions.sorted { $0.startedAt < $1.startedAt }
                guard let latest = sorted.last else { return nil }
                let previous = sorted.dropLast().last
                let latestVolume = completedVolume(for: latest, displayUnit: displayUnit)
                let previousVolume = previous.map { completedVolume(for: $0, displayUnit: displayUnit) }
                let latestSets = completedSetCount(for: latest)
                let previousSets = previous.map(completedSetCount)
                let latestAverageWeight = averageCompletedWeight(for: latest, displayUnit: displayUnit)
                let previousAverageWeight = previous.map { averageCompletedWeight(for: $0, displayUnit: displayUnit) }

                return RoutineProgressMetric(
                    routineId: routineId,
                    routineName: latest.routineName,
                    latestDate: latest.startedAt,
                    previousDate: previous?.startedAt,
                    latestVolume: latestVolume,
                    previousVolume: previousVolume,
                    volumeDelta: previousVolume.map { latestVolume - $0 },
                    completedSetsDelta: previousSets.map { latestSets - $0 },
                    averageWeightDelta: previousAverageWeight.map { latestAverageWeight - $0 },
                    durationDeltaSeconds: previous.map { latest.elapsedSeconds - $0.elapsedSeconds }
                )
            }
            .sorted { $0.latestDate > $1.latestDate }
    }

    static func makeInsight(
        exercises: [ExerciseProgressMetric],
        muscles: [MuscleGroupProgressMetric],
        routines: [RoutineProgressMetric]
    ) -> StrengthProgressInsight {
        guard !exercises.isEmpty else { return .empty }

        if let top = exercises.max(by: { $0.progressScore < $1.progressScore }),
           top.progressScore > 0 {
            return StrengthProgressInsight(
                title: "Top progression",
                message: "\(top.name) is trending up. Last session moved \(top.deltaText.lowercased()).",
                symbolName: "chart.line.uptrend.xyaxis",
                state: .improving
            )
        }

        if let undertrained = muscles.first(where: { $0.state == .needsAttention }) {
            return StrengthProgressInsight(
                title: "\(undertrained.group.displayName) is quiet",
                message: "You have not trained \(undertrained.group.displayName.lowercased()) recently. A light stimulus session would refresh the signal.",
                symbolName: "scope",
                state: .needsAttention
            )
        }

        if let routine = routines.first(where: { ($0.volumeDelta ?? 0) < 0 }) {
            return StrengthProgressInsight(
                title: "Routine volume dipped",
                message: "\(routine.routineName) is below the previous session. Repeat the load or add one clean set if it feels controlled.",
                symbolName: "waveform.path",
                state: .stable
            )
        }

        return StrengthProgressInsight(
            title: "Consistent signal",
            message: "Your recent lifts are steady. Look for one exercise where form feels crisp and nudge load or reps gradually.",
            symbolName: "sparkles",
            state: .stable
        )
    }

    static func makeSuggestion(
        latest: ExerciseSessionRollup,
        previous: ExerciseSessionRollup?,
        displayUnit: PulsarWeightUnit,
        now: Date
    ) -> RoutineProgressionSuggestion? {
        let daysSinceLast = now.timeIntervalSince(latest.date) / 86_400
        if daysSinceLast >= 14 {
            return RoutineProgressionSuggestion(
                kind: .easeBackIn,
                title: "Suggested today",
                detail: "Consider easing back in.",
                suggestedWeight: latest.lastSetWeightDisplay,
                weightUnit: displayUnit
            )
        }

        if latest.completedSets < latest.plannedSets {
            return RoutineProgressionSuggestion(
                kind: .repeatLoad,
                title: "Suggested today",
                detail: "Repeat last weight until all sets feel solid.",
                suggestedWeight: latest.lastSetWeightDisplay,
                weightUnit: displayUnit
            )
        }

        if latest.lastSetWeightDisplay > 0 {
            let increment = displayUnit == .pounds ? 5.0 : 2.5
            return RoutineProgressionSuggestion(
                kind: .addLoad,
                title: "Suggested today",
                detail: "You completed all sets last time. Try +\(increment.formattedGymDecimal) \(displayUnit.displayName).",
                suggestedWeight: latest.lastSetWeightDisplay + increment,
                weightUnit: displayUnit
            )
        }

        if let previous,
           previous.progressVolume > 0,
           latest.progressVolume > previous.progressVolume * 1.20 {
            return RoutineProgressionSuggestion(
                kind: .holdForm,
                title: "Suggested today",
                detail: "Good progress. Keep form controlled.",
                suggestedWeight: latest.lastSetWeightDisplay,
                weightUnit: displayUnit
            )
        }

        return nil
    }

    static func exerciseState(
        isBodyweight: Bool,
        weightDelta: Double?,
        repsDelta: Int?,
        performedCount: Int,
        lastPerformedAge: TimeInterval
    ) -> StrengthProgressState {
        if lastPerformedAge > 21 * 86_400 {
            return .needsAttention
        }

        if isBodyweight {
            if (repsDelta ?? 0) > 0 { return .improving }
        } else if (weightDelta ?? 0) > 0.05 {
            return .improving
        }

        if performedCount >= 3 {
            return .stable
        }
        return .needsAttention
    }

    static func muscleState(
        recentVolume: Double,
        previousVolume: Double,
        lastTrainedAge: TimeInterval
    ) -> StrengthProgressState {
        if lastTrainedAge > 14 * 86_400 || recentVolume <= 0 {
            return .needsAttention
        }
        if recentVolume > previousVolume * 1.08 {
            return .improving
        }
        return .stable
    }

    static func percentDelta(current: Double, previous: Double) -> Double {
        guard previous > 0 else {
            return current > 0 ? 100 : 0
        }
        return ((current - previous) / previous) * 100
    }

    static func completedSetCount(for session: PulsarGymWorkoutSession) -> Int {
        session.exercises.flatMap(\.sets).filter(\.isCompleted).count
    }

    static func averageCompletedWeight(
        for session: PulsarGymWorkoutSession,
        displayUnit: PulsarWeightUnit
    ) -> Double {
        let weights = session.exercises.flatMap { exercise in
            exercise.sets.compactMap { set -> Double? in
                guard set.isCompleted else { return nil }
                let weight = exercise.weightUnit.convert(set.completedWeight ?? set.targetWeight, to: displayUnit)
                return weight > 0 ? weight : nil
            }
        }
        guard !weights.isEmpty else { return 0 }
        return weights.reduce(0, +) / Double(weights.count)
    }

    static func numberOfWeeks(from start: Date, to end: Date, calendar: Calendar) -> Int {
        let calendar = FitnessWeekCalculator.fitnessCalendar(from: calendar)
        let startWeek = FitnessWeekCalculator.getFitnessWeekRange(for: start, calendar: calendar)
        let endWeek = FitnessWeekCalculator.getFitnessWeekRange(for: end, calendar: calendar)
        let days = calendar.dateComponents([.day], from: startWeek.startOfWeekMonday, to: endWeek.startOfWeekMonday).day ?? 0
        return max(1, days / 7 + 1)
    }

    static func weekKey(for date: Date, calendar: Calendar) -> String {
        FitnessWeekCalculator.getWeekPeriod(for: date, calendar: calendar).id
    }
}

private struct ExerciseSessionRollup: Hashable {
    var sessionId: UUID
    var routineId: UUID
    var routineName: String
    var date: Date
    var durationSeconds: Int
    var exerciseKey: String
    var exerciseId: String?
    var exerciseName: String
    var primaryMuscleGroup: PulsarMuscleGroup
    var primaryMuscles: [PulsarMuscle]
    var secondaryMuscles: [PulsarMuscle]
    var matrixGroups: [MuscleMatrixGroup]
    var equipment: String
    var plannedSets: Int
    var plannedRestSeconds: Int
    var completedSets: Int
    var totalReps: Int
    var bestWeightDisplay: Double
    var lastSetWeightDisplay: Double
    var lastSetReps: Int
    var estimatedOneRepMaxDisplay: Double?
    var volumeDisplay: Double
    var repsVolume: Double
    var isBodyweight: Bool

    init?(
        session: PulsarGymWorkoutSession,
        exercise: PulsarGymWorkoutExerciseSession,
        displayUnit: PulsarWeightUnit
    ) {
        let completedSets = exercise.sets
            .filter(\.isCompleted)
            .sorted { $0.setNumber < $1.setNumber }
        guard !completedSets.isEmpty else { return nil }

        let weightedSets = completedSets.map { set -> WeightedSet in
            let reps = max(0, set.completedReps ?? set.targetReps)
            let rawWeight = max(0, set.completedWeight ?? set.targetWeight)
            let displayWeight = exercise.weightUnit.convert(rawWeight, to: displayUnit)
            let oneRepMax = rawWeight > 0 && reps > 0
                ? displayWeight * (1 + (Double(reps) / 30))
                : nil
            return WeightedSet(
                setNumber: set.setNumber,
                reps: reps,
                weightDisplay: displayWeight,
                estimatedOneRepMaxDisplay: oneRepMax
            )
        }

        let bestWeightDisplay = weightedSets.map(\.weightDisplay).max() ?? 0
        let isBodyweight = bestWeightDisplay <= 0.05 || exercise.equipment.localizedCaseInsensitiveContains("bodyweight")
        let totalReps = weightedSets.reduce(0) { $0 + $1.reps }
        let volumeDisplay = weightedSets.reduce(0) { partial, set in
            partial + (Double(set.reps) * max(0, set.weightDisplay))
        }
        let lastSet = weightedSets.last
        let allMatrixGroups = Self.matrixGroups(
            primaryMuscles: exercise.primaryMuscles,
            secondaryMuscles: exercise.secondaryMuscles,
            fallbackGroup: exercise.primaryMuscleGroup
        )

        self.sessionId = session.id
        self.routineId = session.routineId
        self.routineName = session.routineName
        self.date = session.startedAt
        self.durationSeconds = session.elapsedSeconds
        self.exerciseKey = StrengthProgressAnalyticsService.exerciseKey(id: exercise.exerciseId, name: exercise.exerciseName)
        self.exerciseId = exercise.exerciseId
        self.exerciseName = exercise.exerciseName
        self.primaryMuscleGroup = exercise.primaryMuscleGroup
        self.primaryMuscles = exercise.primaryMuscles
        self.secondaryMuscles = exercise.secondaryMuscles
        self.matrixGroups = allMatrixGroups
        self.equipment = exercise.equipment
        self.plannedSets = exercise.plannedSets
        self.plannedRestSeconds = exercise.plannedRestSeconds
        self.completedSets = completedSets.count
        self.totalReps = totalReps
        self.bestWeightDisplay = bestWeightDisplay
        self.lastSetWeightDisplay = lastSet?.weightDisplay ?? 0
        self.lastSetReps = max(1, lastSet?.reps ?? exercise.plannedReps)
        self.estimatedOneRepMaxDisplay = weightedSets.compactMap(\.estimatedOneRepMaxDisplay).max()
        self.volumeDisplay = volumeDisplay
        self.repsVolume = Double(totalReps)
        self.isBodyweight = isBodyweight
    }

    var progressVolume: Double {
        isBodyweight ? repsVolume : volumeDisplay
    }

    var progressPoint: StrengthProgressPoint {
        StrengthProgressPoint(
            id: "\(sessionId.uuidString)-\(exerciseKey)",
            date: date,
            bestWeight: bestWeightDisplay,
            estimatedOneRepMax: estimatedOneRepMaxDisplay,
            volume: progressVolume,
            reps: totalReps,
            sets: completedSets
        )
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

private struct WeightedSet: Hashable {
    var setNumber: Int
    var reps: Int
    var weightDisplay: Double
    var estimatedOneRepMaxDisplay: Double?
}

private extension StrengthProgressState {
    var sortRank: Int {
        switch self {
        case .improving: 3
        case .stable: 2
        case .needsAttention: 1
        }
    }
}

extension PulsarWeightUnit {
    private static let poundsPerKilogram = 2.2046226218

    func convert(_ value: Double, to targetUnit: PulsarWeightUnit) -> Double {
        guard self != targetUnit else { return value }

        switch (self, targetUnit) {
        case (.kilograms, .pounds):
            return value * Self.poundsPerKilogram
        case (.pounds, .kilograms):
            return value / Self.poundsPerKilogram
        default:
            return value
        }
    }
}
