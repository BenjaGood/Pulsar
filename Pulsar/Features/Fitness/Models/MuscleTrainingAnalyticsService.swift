//
//  MuscleTrainingAnalyticsService.swift
//  Pulsar
//

import Foundation

struct WeeklyMuscleTrainingSummary: Hashable {
    var loadByGroup: [PulsarMuscleGroup: Double]
    var loadByBodyMapRegion: [BodyZone: Double]
    var exercisesByBodyMapRegion: [BodyZone: [String]]
    var completedSets: Int
    var totalSets: Int
    var completedExercises: Int

    static let empty = WeeklyMuscleTrainingSummary(
        loadByGroup: [:],
        loadByBodyMapRegion: [:],
        exercisesByBodyMapRegion: [:],
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
        var loadByBodyMapRegion: [BodyZone: Double] = [:]
        var exercisesByRegion: [BodyZone: Set<String>] = [:]
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
                    loadByBodyMapRegion: &loadByBodyMapRegion,
                    exercisesByRegion: &exercisesByRegion
                )

                if !exercise.secondaryMuscles.isEmpty {
                    apply(
                        exerciseName: exercise.exerciseName,
                        muscles: exercise.secondaryMuscles,
                        fallbackGroup: nil,
                        score: setScore * 0.5,
                        loadByGroup: &loadByGroup,
                        loadByBodyMapRegion: &loadByBodyMapRegion,
                        exercisesByRegion: &exercisesByRegion
                    )
                }
            }
        }

        return WeeklyMuscleTrainingSummary(
            loadByGroup: loadByGroup,
            loadByBodyMapRegion: loadByBodyMapRegion,
            exercisesByBodyMapRegion: exercisesByRegion.mapValues { Array($0).sorted() },
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
        loadByBodyMapRegion: inout [BodyZone: Double],
        exercisesByRegion: inout [BodyZone: Set<String>]
    ) {
        guard score > 0 else { return }

        if muscles.isEmpty, let fallbackGroup {
            loadByGroup[fallbackGroup, default: 0] += score
            for zone in WgerMuscleToPulsarBodyMapRegionMapper.zones(for: fallbackGroup) {
                loadByBodyMapRegion[zone, default: 0] += score
                exercisesByRegion[zone, default: []].insert(exerciseName)
            }
            return
        }

        for muscle in muscles {
            loadByGroup[muscle.group, default: 0] += score
            let zones = WgerMuscleToPulsarBodyMapRegionMapper.zones(for: muscle)
            for zone in zones {
                loadByBodyMapRegion[zone, default: 0] += score
                exercisesByRegion[zone, default: []].insert(exerciseName)
            }
        }
    }
}

enum WgerMuscleToPulsarBodyMapRegionMapper {
    static func zones(for muscle: PulsarMuscle) -> [BodyZone] {
        if let wgerID = muscle.wgerID, let mapped = zonesByWgerID[wgerID] {
            return mapped
        }

        let name = "\(muscle.name) \(muscle.englishName ?? "")"
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        if name.contains("pector") || name.contains("chest") || name.contains("serratus") {
            return BodyZone.chest.expandedZones
        }
        if name.contains("latissimus") || name.contains("lat ") || name.contains("lats") {
            return [.latsLeft, .latsRight]
        }
        if name.contains("trapezius") || name.contains("trap") {
            return [.upperBack]
        }
        if name.contains("deltoid") || name.contains("shoulder") {
            return BodyZone.shoulders.expandedZones
        }
        if name.contains("biceps") || name.contains("brachialis") {
            return BodyZone.biceps.expandedZones
        }
        if name.contains("triceps") {
            return BodyZone.triceps.expandedZones
        }
        if name.contains("forearm") || name.contains("brachioradialis") {
            return [.forearmsLeft, .forearmsRight]
        }
        if name.contains("oblique") {
            return [.obliquesLeft, .obliquesRight]
        }
        if name.contains("abdom") || name.contains("core") {
            return [.abs]
        }
        if name.contains("glute") || name.contains("abductor") {
            return BodyZone.glutes.expandedZones
        }
        if name.contains("quadriceps") || name.contains("quad") {
            return BodyZone.quads.expandedZones
        }
        if name.contains("hamstring") || name.contains("femoris") {
            return BodyZone.hamstrings.expandedZones
        }
        if name.contains("gastrocnemius") || name.contains("soleus") || name.contains("calf") {
            return BodyZone.calves.expandedZones
        }
        if name.contains("adductor") {
            return [.adductorsLeft, .adductorsRight]
        }
        if name.contains("lower back") || name.contains("erector") || name.contains("lumbar") {
            return [.lowerBack]
        }

        return zones(for: muscle.group)
    }

    static func zones(for group: PulsarMuscleGroup) -> [BodyZone] {
        switch group {
        case .chest:
            return BodyZone.chest.expandedZones
        case .back:
            return [.upperBack, .latsLeft, .latsRight, .lowerBack]
        case .shoulders:
            return BodyZone.shoulders.expandedZones
        case .biceps:
            return BodyZone.biceps.expandedZones
        case .triceps:
            return BodyZone.triceps.expandedZones
        case .forearms:
            return [.forearmsLeft, .forearmsRight]
        case .absCore:
            return BodyZone.core.expandedZones
        case .glutes:
            return BodyZone.glutes.expandedZones
        case .quadriceps:
            return BodyZone.quads.expandedZones
        case .hamstrings:
            return BodyZone.hamstrings.expandedZones
        case .calves:
            return BodyZone.calves.expandedZones
        case .adductors:
            return [.adductorsLeft, .adductorsRight]
        case .abductors:
            return BodyZone.glutes.expandedZones
        case .fullBody:
            return BodyZone.chest.expandedZones
                + [.upperBack, .latsLeft, .latsRight]
                + BodyZone.shoulders.expandedZones
                + BodyZone.core.expandedZones
                + BodyZone.glutes.expandedZones
                + BodyZone.quads.expandedZones
                + BodyZone.hamstrings.expandedZones
        case .cardioConditioning:
            return [.heart]
        case .other:
            return []
        }
    }

    private static let zonesByWgerID: [Int: [BodyZone]] = [
        1: BodyZone.biceps.expandedZones,
        2: BodyZone.shoulders.expandedZones,
        3: BodyZone.chest.expandedZones + [.obliquesLeft, .obliquesRight],
        4: BodyZone.chest.expandedZones,
        5: [.abs],
        6: BodyZone.calves.expandedZones,
        7: [.obliquesLeft, .obliquesRight],
        8: BodyZone.glutes.expandedZones,
        9: [.upperBack],
        10: BodyZone.quads.expandedZones,
        11: BodyZone.hamstrings.expandedZones,
        12: [.latsLeft, .latsRight],
        13: BodyZone.biceps.expandedZones,
        14: BodyZone.triceps.expandedZones,
        15: BodyZone.calves.expandedZones
    ]
}
