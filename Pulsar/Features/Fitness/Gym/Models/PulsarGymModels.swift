//
//  PulsarGymModels.swift
//  Pulsar
//

import Foundation

enum PulsarMuscleGroup: String, CaseIterable, Identifiable, Codable, Hashable {
    case chest
    case back
    case shoulders
    case biceps
    case triceps
    case forearms
    case absCore
    case glutes
    case quadriceps
    case hamstrings
    case calves
    case adductors
    case abductors
    case fullBody
    case cardioConditioning
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest: "Chest"
        case .back: "Back"
        case .shoulders: "Shoulders"
        case .biceps: "Biceps"
        case .triceps: "Triceps"
        case .forearms: "Forearms"
        case .absCore: "Abs/Core"
        case .glutes: "Glutes"
        case .quadriceps: "Quadriceps"
        case .hamstrings: "Hamstrings"
        case .calves: "Calves"
        case .adductors: "Adductors"
        case .abductors: "Abductors"
        case .fullBody: "Full Body"
        case .cardioConditioning: "Cardio/Conditioning"
        case .other: "Other"
        }
    }
}

struct PulsarEquipment: Identifiable, Codable, Hashable {
    var id: String
    var wgerID: Int?
    var name: String

    init(wgerID: Int? = nil, name: String) {
        self.wgerID = wgerID
        self.name = name
        self.id = wgerID.map { "wger-equipment-\($0)" } ?? name.normalizedPulsarIdentifier(prefix: "equipment")
    }
}

struct PulsarMuscle: Identifiable, Codable, Hashable {
    var id: String
    var wgerID: Int?
    var name: String
    var englishName: String?
    var group: PulsarMuscleGroup

    init(wgerID: Int? = nil, name: String, englishName: String? = nil, group: PulsarMuscleGroup) {
        self.wgerID = wgerID
        self.name = name
        self.englishName = englishName
        self.group = group
        self.id = wgerID.map { "wger-muscle-\($0)" } ?? name.normalizedPulsarIdentifier(prefix: "muscle")
    }
}

struct PulsarExerciseAttribution: Codable, Hashable {
    var sourceName: String
    var sourceURL: String
    var sourceExerciseID: String?
    var licenseTitle: String?
    var licenseObjectURL: String?
    var licenseAuthor: String?
    var licenseAuthorURL: String?

    static func wger(
        sourceExerciseID: String?,
        licenseTitle: String?,
        licenseObjectURL: String?,
        licenseAuthor: String?,
        licenseAuthorURL: String?
    ) -> PulsarExerciseAttribution {
        PulsarExerciseAttribution(
            sourceName: "wger",
            sourceURL: "https://wger.de",
            sourceExerciseID: sourceExerciseID,
            licenseTitle: licenseTitle,
            licenseObjectURL: licenseObjectURL,
            licenseAuthor: licenseAuthor,
            licenseAuthorURL: licenseAuthorURL
        )
    }
}

struct PulsarExercise: Identifiable, Codable, Hashable {
    var id: String
    var wgerID: Int?
    var wgerUUID: String?
    var name: String
    var instructions: String?
    var primaryMuscles: [PulsarMuscle]
    var secondaryMuscles: [PulsarMuscle]
    var primaryMuscleGroup: PulsarMuscleGroup
    var equipment: [PulsarEquipment]
    var imageURLs: [String]
    var thumbnailURL: String?
    var attribution: PulsarExerciseAttribution

    var primaryMuscleSummary: String {
        if primaryMuscles.isEmpty {
            return primaryMuscleGroup.displayName
        }
        return primaryMuscles.map(\.name).joined(separator: ", ")
    }

    var equipmentSummary: String {
        guard !equipment.isEmpty else { return "Bodyweight" }
        return equipment.map(\.name).joined(separator: ", ")
    }
}

enum PulsarWeightUnit: String, CaseIterable, Identifiable, Codable, Hashable {
    case kilograms = "kg"
    case pounds = "lb"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .kilograms: "kg"
        case .pounds: "lb"
        }
    }
}

struct PulsarRoutineExercise: Identifiable, Codable, Hashable {
    var id: UUID
    var exercise: PulsarExercise
    var order: Int
    var plannedSets: Int
    var plannedReps: Int
    var plannedWeight: Double
    var weightUnit: PulsarWeightUnit
    var plannedRestSeconds: Int
    var notes: String?

    init(
        id: UUID = UUID(),
        exercise: PulsarExercise,
        order: Int,
        plannedSets: Int = 3,
        plannedReps: Int = 10,
        plannedWeight: Double = 0,
        weightUnit: PulsarWeightUnit = .kilograms,
        plannedRestSeconds: Int = 60,
        notes: String? = nil
    ) {
        self.id = id
        self.exercise = exercise
        self.order = order
        self.plannedSets = max(1, plannedSets)
        self.plannedReps = max(1, plannedReps)
        self.plannedWeight = max(0, plannedWeight)
        self.weightUnit = weightUnit
        self.plannedRestSeconds = max(0, plannedRestSeconds)
        self.notes = notes
    }

    var exerciseID: String { exercise.id }
    var exerciseName: String { exercise.name }
    var primaryMuscleGroup: PulsarMuscleGroup { exercise.primaryMuscleGroup }
    var equipmentSummary: String { exercise.equipmentSummary }
    var orderIndex: Int { order }

    var planSummary: String {
        "\(plannedSets) sets / \(plannedReps) reps / \(formattedWeight) \(weightUnit.displayName) / \(formattedRest) rest"
    }

    var formattedWeight: String {
        plannedWeight.formattedGymDecimal
    }

    var formattedRest: String {
        if plannedRestSeconds >= 60, plannedRestSeconds.isMultiple(of: 60) {
            return "\(plannedRestSeconds / 60)m"
        }
        return "\(plannedRestSeconds)s"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case exercise
        case order
        case plannedSets
        case plannedReps
        case plannedWeight
        case weightUnit
        case plannedRestSeconds
        case notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        exercise = try container.decode(PulsarExercise.self, forKey: .exercise)
        order = (try? container.decode(Int.self, forKey: .order)) ?? 0
        plannedSets = max(1, (try? container.decode(Int.self, forKey: .plannedSets)) ?? 3)
        plannedReps = max(1, (try? container.decode(Int.self, forKey: .plannedReps)) ?? 10)
        plannedWeight = max(0, (try? container.decode(Double.self, forKey: .plannedWeight)) ?? 0)
        weightUnit = (try? container.decode(PulsarWeightUnit.self, forKey: .weightUnit)) ?? .kilograms
        plannedRestSeconds = max(0, (try? container.decode(Int.self, forKey: .plannedRestSeconds)) ?? 60)
        notes = try? container.decodeIfPresent(String.self, forKey: .notes)
    }
}

struct PulsarRoutine: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var exercises: [PulsarRoutineExercise]

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        exercises: [PulsarRoutineExercise]
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.exercises = exercises
    }

    static func emptyGymWorkout(startedAt: Date = .now) -> PulsarRoutine {
        PulsarRoutine(
            name: "Empty Gym Workout",
            createdAt: startedAt,
            updatedAt: startedAt,
            exercises: []
        )
    }
}

struct PulsarExerciseCatalogSnapshot: Codable, Hashable {
    var exercises: [PulsarExercise]
    var sourceName: String
    var refreshedAt: Date
    var schemaVersion: Int
}

struct PulsarGymWorkoutSession: Identifiable, Codable, Hashable {
    var id: UUID
    var routineId: UUID
    var routineName: String
    var startedAt: Date
    var finishedAt: Date?
    var elapsedSeconds: Int
    var healthKitWorkoutUUID: UUID?
    var activeEnergyKilocalories: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var healthKitStatusMessage: String?
    var trainedMuscleGroups: [PulsarMuscleGroup]
    var muscleLoadByGroup: [String: Double]
    var muscleLoadByBodyMapRegion: [String: Double]
    var exercises: [PulsarGymWorkoutExerciseSession]

    nonisolated init(
        id: UUID = UUID(),
        routine: PulsarRoutine,
        startedAt: Date = .now
    ) {
        self.id = id
        self.routineId = routine.id
        self.routineName = routine.name
        self.startedAt = startedAt
        self.finishedAt = nil
        self.elapsedSeconds = 0
        self.healthKitWorkoutUUID = nil
        self.activeEnergyKilocalories = nil
        self.averageHeartRate = nil
        self.maxHeartRate = nil
        self.healthKitStatusMessage = nil
        self.trainedMuscleGroups = []
        self.muscleLoadByGroup = [:]
        self.muscleLoadByBodyMapRegion = [:]
        self.exercises = routine.exercises
            .sorted { $0.order < $1.order }
            .map(PulsarGymWorkoutExerciseSession.init(routineExercise:))
    }

    enum CodingKeys: String, CodingKey {
        case id
        case routineId
        case routineName
        case startedAt
        case finishedAt
        case elapsedSeconds
        case healthKitWorkoutUUID
        case activeEnergyKilocalories
        case averageHeartRate
        case maxHeartRate
        case healthKitStatusMessage
        case trainedMuscleGroups
        case muscleLoadByGroup
        case muscleLoadByBodyMapRegion
        case exercises
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        routineId = (try? container.decode(UUID.self, forKey: .routineId)) ?? UUID()
        routineName = (try? container.decode(String.self, forKey: .routineName)) ?? "Gym Workout"
        startedAt = (try? container.decode(Date.self, forKey: .startedAt)) ?? Date()
        finishedAt = try? container.decodeIfPresent(Date.self, forKey: .finishedAt)
        elapsedSeconds = (try? container.decode(Int.self, forKey: .elapsedSeconds)) ?? 0
        healthKitWorkoutUUID = try? container.decodeIfPresent(UUID.self, forKey: .healthKitWorkoutUUID)
        activeEnergyKilocalories = try? container.decodeIfPresent(Double.self, forKey: .activeEnergyKilocalories)
        averageHeartRate = try? container.decodeIfPresent(Double.self, forKey: .averageHeartRate)
        maxHeartRate = try? container.decodeIfPresent(Double.self, forKey: .maxHeartRate)
        healthKitStatusMessage = try? container.decodeIfPresent(String.self, forKey: .healthKitStatusMessage)
        trainedMuscleGroups = (try? container.decodeIfPresent([PulsarMuscleGroup].self, forKey: .trainedMuscleGroups)) ?? []
        muscleLoadByGroup = (try? container.decodeIfPresent([String: Double].self, forKey: .muscleLoadByGroup)) ?? [:]
        muscleLoadByBodyMapRegion = (try? container.decodeIfPresent([String: Double].self, forKey: .muscleLoadByBodyMapRegion)) ?? [:]
        exercises = (try? container.decode([PulsarGymWorkoutExerciseSession].self, forKey: .exercises)) ?? []
    }
}

struct PulsarGymWorkoutExerciseSession: Identifiable, Codable, Hashable {
    var id: UUID
    var routineExerciseId: UUID
    var exerciseId: String?
    var exerciseName: String
    var primaryMuscleGroup: PulsarMuscleGroup
    var primaryMuscles: [PulsarMuscle]
    var secondaryMuscles: [PulsarMuscle]
    var equipment: String
    var plannedSets: Int
    var plannedReps: Int
    var plannedWeight: Double
    var weightUnit: PulsarWeightUnit
    var plannedRestSeconds: Int
    var notes: String?
    var orderIndex: Int
    var sets: [PulsarGymWorkoutSetSession]

    nonisolated init(routineExercise: PulsarRoutineExercise) {
        id = UUID()
        routineExerciseId = routineExercise.id
        exerciseId = routineExercise.exercise.id
        exerciseName = routineExercise.exercise.name
        primaryMuscleGroup = routineExercise.exercise.primaryMuscleGroup
        primaryMuscles = routineExercise.exercise.primaryMuscles
        secondaryMuscles = routineExercise.exercise.secondaryMuscles
        equipment = routineExercise.exercise.equipment.isEmpty
            ? "Bodyweight"
            : routineExercise.exercise.equipment.map(\.name).joined(separator: ", ")
        plannedSets = routineExercise.plannedSets
        plannedReps = routineExercise.plannedReps
        plannedWeight = routineExercise.plannedWeight
        weightUnit = routineExercise.weightUnit
        plannedRestSeconds = routineExercise.plannedRestSeconds
        notes = routineExercise.notes
        orderIndex = routineExercise.order
        sets = (1...routineExercise.plannedSets).map { setNumber in
            PulsarGymWorkoutSetSession(
                setNumber: setNumber,
                targetReps: routineExercise.plannedReps,
                targetWeight: routineExercise.plannedWeight
            )
        }
    }

    var completedSetCount: Int {
        sets.filter(\.isCompleted).count
    }

    var isCompleted: Bool {
        !sets.isEmpty && completedSetCount == sets.count
    }

    var planSummary: String {
        "\(plannedSets) sets / \(plannedReps) reps / \(plannedWeight.formattedGymDecimal) \(weightUnit.displayName)"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case routineExerciseId
        case exerciseId
        case exerciseName
        case primaryMuscleGroup
        case primaryMuscles
        case secondaryMuscles
        case equipment
        case plannedSets
        case plannedReps
        case plannedWeight
        case weightUnit
        case plannedRestSeconds
        case notes
        case orderIndex
        case sets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        routineExerciseId = (try? container.decode(UUID.self, forKey: .routineExerciseId)) ?? UUID()
        exerciseId = try? container.decodeIfPresent(String.self, forKey: .exerciseId)
        exerciseName = (try? container.decode(String.self, forKey: .exerciseName)) ?? "Exercise"
        primaryMuscleGroup = (try? container.decode(PulsarMuscleGroup.self, forKey: .primaryMuscleGroup)) ?? .other
        primaryMuscles = (try? container.decodeIfPresent([PulsarMuscle].self, forKey: .primaryMuscles)) ?? []
        secondaryMuscles = (try? container.decodeIfPresent([PulsarMuscle].self, forKey: .secondaryMuscles)) ?? []
        equipment = (try? container.decode(String.self, forKey: .equipment)) ?? "Bodyweight"
        plannedSets = max(1, (try? container.decode(Int.self, forKey: .plannedSets)) ?? 1)
        plannedReps = max(1, (try? container.decode(Int.self, forKey: .plannedReps)) ?? 1)
        plannedWeight = max(0, (try? container.decode(Double.self, forKey: .plannedWeight)) ?? 0)
        weightUnit = (try? container.decode(PulsarWeightUnit.self, forKey: .weightUnit)) ?? .kilograms
        plannedRestSeconds = max(0, (try? container.decode(Int.self, forKey: .plannedRestSeconds)) ?? 0)
        notes = try? container.decodeIfPresent(String.self, forKey: .notes)
        orderIndex = (try? container.decode(Int.self, forKey: .orderIndex)) ?? 0
        sets = (try? container.decode([PulsarGymWorkoutSetSession].self, forKey: .sets)) ?? []
    }
}

struct PulsarGymWorkoutSetSession: Identifiable, Codable, Hashable {
    var id: UUID
    var setNumber: Int
    var targetReps: Int
    var targetWeight: Double
    var completedReps: Int?
    var completedWeight: Double?
    var isCompleted: Bool
    var completedAt: Date?

    nonisolated init(
        id: UUID = UUID(),
        setNumber: Int,
        targetReps: Int,
        targetWeight: Double,
        completedReps: Int? = nil,
        completedWeight: Double? = nil,
        isCompleted: Bool = false,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.setNumber = setNumber
        self.targetReps = targetReps
        self.targetWeight = targetWeight
        self.completedReps = completedReps
        self.completedWeight = completedWeight
        self.isCompleted = isCompleted
        self.completedAt = completedAt
    }
}

struct PulsarGymWorkoutSummary: Identifiable, Codable, Hashable {
    var id: UUID
    var sessionId: UUID
    var routineName: String
    var durationSeconds: Int
    var exercisesCompleted: Int
    var totalExercises: Int
    var setsCompleted: Int
    var totalSets: Int
    var totalVolume: Double
    var weightUnit: PulsarWeightUnit
    var healthKitWorkoutUUID: UUID?
    var activeEnergyKilocalories: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var healthKitStatusMessage: String?

    init(session: PulsarGymWorkoutSession) {
        id = UUID()
        sessionId = session.id
        routineName = session.routineName
        durationSeconds = session.elapsedSeconds
        exercisesCompleted = session.exercises.filter(\.isCompleted).count
        totalExercises = session.exercises.count
        setsCompleted = session.exercises.flatMap(\.sets).filter(\.isCompleted).count
        totalSets = session.exercises.flatMap(\.sets).count
        weightUnit = session.exercises.first?.weightUnit ?? .kilograms
        healthKitWorkoutUUID = session.healthKitWorkoutUUID
        activeEnergyKilocalories = session.activeEnergyKilocalories
        averageHeartRate = session.averageHeartRate
        maxHeartRate = session.maxHeartRate
        healthKitStatusMessage = session.healthKitStatusMessage
        totalVolume = session.exercises.flatMap(\.sets).reduce(0) { partialResult, set in
            guard set.isCompleted else { return partialResult }
            let reps = Double(set.completedReps ?? set.targetReps)
            let weight = set.completedWeight ?? set.targetWeight
            return partialResult + reps * weight
        }
    }
}

extension String {
    func normalizedPulsarIdentifier(prefix: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let scalars = unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let slug = String(scalars)
            .lowercased()
            .split(separator: "-")
            .joined(separator: "-")
        return "\(prefix)-\(slug.isEmpty ? UUID().uuidString.lowercased() : slug)"
    }
}

extension Double {
    var formattedGymDecimal: String {
        if rounded() == self {
            return String(Int(self))
        }
        return String(format: "%.1f", self)
    }
}

extension Int {
    var formattedGymDuration: String {
        let clamped = Swift.max(0, self)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let seconds = clamped % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
