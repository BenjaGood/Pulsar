//
//  CompletedWorkoutExerciseResolver.swift
//  Pulsar
//

import Foundation

struct CompletedWorkoutSetPresentation: Identifiable, Hashable {
    var id: UUID
    var setNumber: Int
    var reps: Int
    var weight: Double
    var estimatedOneRepMax: Double?
}

struct CompletedWorkoutExercisePresentation: Identifiable, Hashable {
    var id: UUID
    var index: Int
    var summary: PulsarGymCompletedExerciseSummary
    var sourceExercise: PulsarGymWorkoutExerciseSession?
    var catalogExercise: PulsarExercise?
    var exerciseName: String
    var exerciseId: String?
    var thumbnailURL: String?
    var instructionsPreview: String?
    var instructionsFull: String?
    var instructionsAreTruncated: Bool
    var primaryMuscleGroup: PulsarMuscleGroup
    var equipment: String
    var weightUnit: PulsarWeightUnit
    var sets: [CompletedWorkoutSetPresentation]

    var setCountText: String {
        "\(sets.count) \(sets.count == 1 ? "set" : "sets")"
    }
}

enum CompletedWorkoutExerciseResolver {
    static func presentations(
        summaries: [PulsarGymCompletedExerciseSummary],
        sourceSession: PulsarGymWorkoutSession?,
        catalogExercises: [PulsarExercise]
    ) -> [CompletedWorkoutExercisePresentation] {
        let sourceExercises = sourceSession?.exercises ?? []
        return summaries.enumerated().map { offset, summary in
            let sourceExercise = sourceExercise(for: summary, in: sourceExercises)
            let catalogExercise = catalogExercise(
                for: summary,
                sourceExercise: sourceExercise,
                catalogExercises: catalogExercises
            )
            let instructionsFull = catalogExercise?.instructions?.completedWorkoutInstructionsFull()
                ?? sourceExercise?.instructionsPreview?.completedWorkoutInstructionsFull()
            let instructionsPreview = instructionsFull?.completedWorkoutInstructionsPreview()
            let instructionsAreTruncated = instructionsFull.map { fullText in
                guard let instructionsPreview else { return false }
                return instructionsPreview.hasSuffix("...") || instructionsPreview.count < fullText.count
            } ?? false
            let thumbnail = sourceExercise?.thumbnailURL
                ?? summary.thumbnailURL
                ?? catalogExercise?.thumbnailURL
            let muscleGroup = sourceExercise?.primaryMuscleGroup
                ?? normalizedMuscleGroup(summary.primaryMuscleGroup, catalogExercise: catalogExercise)
            let equipment = sourceExercise?.equipment
                ?? normalizedEquipment(summary.equipment, catalogExercise: catalogExercise)
            let weightUnit = sourceExercise?.weightUnit ?? summary.weightUnit
            let sets = summary.sets.map { set in
                CompletedWorkoutSetPresentation(
                    id: set.id,
                    setNumber: set.setNumber,
                    reps: set.reps,
                    weight: set.weight,
                    estimatedOneRepMax: ExerciseProgressService.calculateEstimated1RM(weight: set.weight, reps: set.reps)
                )
            }

            return CompletedWorkoutExercisePresentation(
                id: summary.id,
                index: offset + 1,
                summary: summary,
                sourceExercise: sourceExercise,
                catalogExercise: catalogExercise,
                exerciseName: sourceExercise?.exerciseName ?? summary.exerciseName,
                exerciseId: sourceExercise?.exerciseId ?? summary.exerciseId ?? catalogExercise?.id,
                thumbnailURL: thumbnail,
                instructionsPreview: instructionsPreview,
                instructionsFull: instructionsFull,
                instructionsAreTruncated: instructionsAreTruncated,
                primaryMuscleGroup: muscleGroup,
                equipment: equipment,
                weightUnit: weightUnit,
                sets: sets
            )
        }
    }

    private static func sourceExercise(
        for summary: PulsarGymCompletedExerciseSummary,
        in exercises: [PulsarGymWorkoutExerciseSession]
    ) -> PulsarGymWorkoutExerciseSession? {
        if let match = exercises.first(where: { $0.id == summary.id }) {
            return match
        }
        let summaryKey = StrengthProgressAnalyticsService.exerciseKey(id: summary.exerciseId, name: summary.exerciseName)
        return exercises.first {
            StrengthProgressAnalyticsService.exerciseKey(id: $0.exerciseId, name: $0.exerciseName) == summaryKey
        }
    }

    private static func catalogExercise(
        for summary: PulsarGymCompletedExerciseSummary,
        sourceExercise: PulsarGymWorkoutExerciseSession?,
        catalogExercises: [PulsarExercise]
    ) -> PulsarExercise? {
        if let id = sourceExercise?.exerciseId ?? summary.exerciseId,
           let exercise = catalogExercises.first(where: { $0.id == id }) {
            return exercise
        }

        let summaryNameKey = StrengthProgressAnalyticsService.exerciseKey(id: nil, name: sourceExercise?.exerciseName ?? summary.exerciseName)
        return catalogExercises.first {
            StrengthProgressAnalyticsService.exerciseKey(id: nil, name: $0.name) == summaryNameKey
        }
    }

    private static func normalizedEquipment(_ equipment: String, catalogExercise: PulsarExercise?) -> String {
        let trimmed = equipment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != "Bodyweight" {
            return trimmed
        }
        return catalogExercise?.equipmentSummary ?? (trimmed.isEmpty ? "Bodyweight" : trimmed)
    }

    private static func normalizedMuscleGroup(
        _ muscleGroup: PulsarMuscleGroup,
        catalogExercise: PulsarExercise?
    ) -> PulsarMuscleGroup {
        guard muscleGroup == .other else { return muscleGroup }
        return catalogExercise?.primaryMuscleGroup ?? muscleGroup
    }
}

private extension String {
    func completedWorkoutInstructionsFull() -> String? {
        let normalized = components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return normalized.isEmpty ? nil : normalized
    }

    func completedWorkoutInstructionsPreview(maxLength: Int = 220) -> String? {
        guard let normalized = completedWorkoutInstructionsFull() else { return nil }
        if normalized.count <= maxLength { return normalized }
        return String(normalized.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
