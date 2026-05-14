//
//  MuscleTrainingAnalyticsService.swift
//  Pulsar
//

import Foundation

struct WeeklyMuscleTrainingSummary: Hashable {
    var loadByGroup: [PulsarMuscleGroup: Double]
    var loadByMatrixGroup: [MuscleMatrixGroup: Double]
    var exercisesByMatrixGroup: [MuscleMatrixGroup: [String]]
    var completedSets: Int
    var totalSets: Int
    var completedExercises: Int

    static let empty = WeeklyMuscleTrainingSummary(
        loadByGroup: [:],
        loadByMatrixGroup: [:],
        exercisesByMatrixGroup: [:],
        completedSets: 0,
        totalSets: 0,
        completedExercises: 0
    )

    var trainedMuscleGroups: [PulsarMuscleGroup] {
        loadByGroup
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key.displayName < rhs.key.displayName
                }
                return lhs.value > rhs.value
            }
            .map(\.key)
    }

    var mainMuscleGroupNames: [String] {
        trainedMuscleGroups
            .filter { $0 != .other }
            .prefix(3)
            .map(\.displayName)
    }
}

enum MuscleTrainingAnalyticsService {
    static func summary(for session: PulsarGymWorkoutSession) -> WeeklyMuscleTrainingSummary {
        WeeklyMuscleLoadCalculator.calculate(sessions: [session])
    }

    static func weeklySummary(for sessions: [PulsarGymWorkoutSession]) -> WeeklyMuscleTrainingSummary {
        WeeklyMuscleLoadCalculator.calculate(sessions: sessions)
    }
}

enum WeeklyMuscleLoadCalculator {
    static func calculate(sessions: [PulsarGymWorkoutSession]) -> WeeklyMuscleTrainingSummary {
        var loadByGroup: [PulsarMuscleGroup: Double] = [:]
        var loadByMatrixGroup: [MuscleMatrixGroup: Double] = [:]
        var exercisesByMatrixGroup: [MuscleMatrixGroup: Set<String>] = [:]
        var completedSets = 0
        var totalSets = 0
        var completedExercises = 0

        for session in sessions {
            for exercise in session.exercises {
                let exerciseCompletedSets = exercise.sets.filter(\.isCompleted).count
                completedSets += exerciseCompletedSets
                totalSets += exercise.sets.count
                guard exerciseCompletedSets > 0 else { continue }

                completedExercises += 1
                let setScore = Double(exerciseCompletedSets)
                apply(
                    exerciseName: exercise.exerciseName,
                    muscles: exercise.primaryMuscles,
                    fallbackGroup: exercise.primaryMuscleGroup,
                    score: setScore,
                    loadByGroup: &loadByGroup,
                    loadByMatrixGroup: &loadByMatrixGroup,
                    exercisesByMatrixGroup: &exercisesByMatrixGroup
                )

                if !exercise.secondaryMuscles.isEmpty {
                    apply(
                        exerciseName: exercise.exerciseName,
                        muscles: exercise.secondaryMuscles,
                        fallbackGroup: nil,
                        score: setScore * 0.5,
                        loadByGroup: &loadByGroup,
                        loadByMatrixGroup: &loadByMatrixGroup,
                        exercisesByMatrixGroup: &exercisesByMatrixGroup
                    )
                }
            }
        }

        return WeeklyMuscleTrainingSummary(
            loadByGroup: loadByGroup,
            loadByMatrixGroup: loadByMatrixGroup,
            exercisesByMatrixGroup: exercisesByMatrixGroup.mapValues { Array($0).sorted() },
            completedSets: completedSets,
            totalSets: totalSets,
            completedExercises: completedExercises
        )
    }

    nonisolated static func normalizedIntensity(for score: Double) -> Double {
        switch score {
        case ..<1:
            return 0
        case ..<4:
            return 0.34
        case ..<8:
            return 0.68
        default:
            return 1.0
        }
    }

    nonisolated static func intensityLabel(for score: Double) -> String {
        switch score {
        case ..<1:
            return "Not trained"
        case ..<4:
            return "Light"
        case ..<8:
            return "Medium"
        default:
            return "High"
        }
    }

    private static func apply(
        exerciseName: String,
        muscles: [PulsarMuscle],
        fallbackGroup: PulsarMuscleGroup?,
        score: Double,
        loadByGroup: inout [PulsarMuscleGroup: Double],
        loadByMatrixGroup: inout [MuscleMatrixGroup: Double],
        exercisesByMatrixGroup: inout [MuscleMatrixGroup: Set<String>]
    ) {
        guard score > 0 else { return }

        if muscles.isEmpty, let fallbackGroup {
            loadByGroup[fallbackGroup, default: 0] += score
            for group in PulsarMuscleMatrixGroupMapper.groups(for: fallbackGroup) {
                loadByMatrixGroup[group, default: 0] += score
                exercisesByMatrixGroup[group, default: []].insert(exerciseName)
            }
            return
        }

        for muscle in muscles {
            loadByGroup[muscle.group, default: 0] += score
            let groups = PulsarMuscleMatrixGroupMapper.groups(for: muscle)
            for group in groups {
                loadByMatrixGroup[group, default: 0] += score
                exercisesByMatrixGroup[group, default: []].insert(exerciseName)
            }
        }
    }
}

enum PulsarMuscleMatrixGroupMapper {
    static func groups(for muscle: PulsarMuscle) -> [MuscleMatrixGroup] {
        if let wgerID = muscle.wgerID, let mapped = legacyGroupsByWgerID[wgerID] {
            return mapped
        }

        let name = "\(muscle.name) \(muscle.englishName ?? "")"
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        if name.contains("pector") || name.contains("chest") || name.contains("serratus") {
            return [.chest]
        }
        if name.contains("latissimus") || name.contains("lat ") || name.contains("lats") {
            return [.back]
        }
        if name.contains("middle back") {
            return [.back]
        }
        if name.contains("lower back") || name.contains("erector") || name.contains("lumbar") {
            return [.back]
        }
        if name.contains("trapezius") || name.contains("trap") {
            return [.back, .shoulders]
        }
        if name.contains("neck") {
            return [.shoulders]
        }
        if name.contains("deltoid") || name.contains("shoulder") {
            return [.shoulders]
        }
        if name.contains("biceps") || name.contains("brachialis") {
            return [.biceps]
        }
        if name.contains("triceps") {
            return [.triceps]
        }
        if name.contains("forearm") || name.contains("brachioradialis") {
            return [.biceps]
        }
        if name.contains("oblique") {
            return [.core]
        }
        if name.contains("abdom") || name.contains("core") {
            return [.core]
        }
        if name.contains("glute") || name.contains("abductor") {
            return [.glutes]
        }
        if name.contains("quadriceps") || name.contains("quad") {
            return [.quads]
        }
        if name.contains("hamstring") || name.contains("femoris") {
            return [.hamstrings]
        }
        if name.contains("gastrocnemius") || name.contains("soleus") || name.contains("calf") {
            return [.calves]
        }
        if name.contains("adductor") {
            return [.glutes, .quads]
        }
        return groups(for: muscle.group)
    }

    static func groups(for group: PulsarMuscleGroup) -> [MuscleMatrixGroup] {
        switch group {
        case .chest:
            return [.chest]
        case .back, .lats, .upperMiddleBack, .lowerBack:
            return [.back]
        case .shoulders:
            return [.shoulders]
        case .traps:
            return [.back, .shoulders]
        case .neckTraps:
            return [.shoulders]
        case .biceps:
            return [.biceps]
        case .triceps:
            return [.triceps]
        case .forearms:
            return [.biceps]
        case .absCore:
            return [.core]
        case .glutes:
            return [.glutes]
        case .quadriceps:
            return [.quads]
        case .hamstrings:
            return [.hamstrings]
        case .calves:
            return [.calves]
        case .adductors:
            return [.quads, .glutes]
        case .abductors:
            return [.glutes]
        case .fullBody:
            return MuscleMatrixGroup.allCases.filter { $0.category == .muscle }
        case .cardioConditioning:
            return []
        case .other:
            return []
        }
    }

    private static let legacyGroupsByWgerID: [Int: [MuscleMatrixGroup]] = [
        1: [.biceps],
        2: [.shoulders],
        3: [.chest, .core],
        4: [.chest],
        5: [.core],
        6: [.calves],
        7: [.core],
        8: [.glutes],
        9: [.back, .shoulders],
        10: [.quads],
        11: [.hamstrings],
        12: [.back],
        13: [.biceps],
        14: [.triceps],
        15: [.calves]
    ]
}
