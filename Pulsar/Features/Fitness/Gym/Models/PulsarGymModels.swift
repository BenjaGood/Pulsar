//
//  PulsarGymModels.swift
//  Pulsar
//

import Foundation

enum PulsarMuscleGroup: String, CaseIterable, Identifiable, Codable, Hashable {
    case chest
    case back
    case lats
    case upperMiddleBack
    case lowerBack
    case shoulders
    case traps
    case neckTraps
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

    nonisolated var displayName: String {
        switch self {
        case .chest: "Chest"
        case .back: "Back"
        case .lats: "Lats/Back"
        case .upperMiddleBack: "Upper/Middle Back"
        case .lowerBack: "Lower Back"
        case .shoulders: "Shoulders"
        case .traps: "Traps"
        case .neckTraps: "Neck/Traps"
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

    nonisolated init(wgerID: Int? = nil, name: String) {
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

    nonisolated init(wgerID: Int? = nil, name: String, englishName: String? = nil, group: PulsarMuscleGroup) {
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

    var dataSource: String { sourceName }
    var dataSourceURL: String { sourceURL }
    var license: String? { licenseTitle }

    nonisolated static func freeExerciseDB(sourceExerciseID: String?) -> PulsarExerciseAttribution {
        PulsarExerciseAttribution(
            sourceName: "free-exercise-db",
            sourceURL: "https://github.com/yuhonas/free-exercise-db",
            sourceExerciseID: sourceExerciseID,
            licenseTitle: "Unlicense",
            licenseObjectURL: "https://github.com/yuhonas/free-exercise-db/blob/main/LICENSE",
            licenseAuthor: nil,
            licenseAuthorURL: nil
        )
    }

    nonisolated static func exercisesDataset(sourceExerciseID: String?) -> PulsarExerciseAttribution {
        PulsarExerciseAttribution(
            sourceName: "hasaneyldrm/exercises-dataset",
            sourceURL: "https://github.com/hasaneyldrm/exercises-dataset",
            sourceExerciseID: sourceExerciseID,
            licenseTitle: "Educational / non-commercial only",
            licenseObjectURL: "https://github.com/hasaneyldrm/exercises-dataset#-license",
            licenseAuthor: "hasaneyldrm",
            licenseAuthorURL: "https://github.com/hasaneyldrm"
        )
    }

    nonisolated static func wger(
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

    nonisolated static func custom(sourceExerciseID: String?) -> PulsarExerciseAttribution {
        PulsarExerciseAttribution(
            sourceName: "Pulsar Custom",
            sourceURL: "pulsar://custom-exercises",
            sourceExerciseID: sourceExerciseID,
            licenseTitle: nil,
            licenseObjectURL: nil,
            licenseAuthor: nil,
            licenseAuthorURL: nil
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
    var animationURL: String? = nil
    var attribution: PulsarExerciseAttribution
    var category: String? = nil
    var level: String? = nil
    var force: String? = nil
    var mechanic: String? = nil

    var dataSource: String { attribution.dataSource }
    var dataSourceURL: String { attribution.dataSourceURL }
    var license: String? { attribution.license }

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

    nonisolated static func custom(
        id: String,
        name: String,
        primaryMuscleGroup: PulsarMuscleGroup,
        thumbnailURL: String?
    ) -> PulsarExercise {
        let primaryMuscle = PulsarMuscle(
            name: primaryMuscleGroup.displayName,
            englishName: primaryMuscleGroup.displayName,
            group: primaryMuscleGroup
        )
        let imageURLs = thumbnailURL.map { [$0] } ?? []

        return PulsarExercise(
            id: id,
            wgerID: nil,
            wgerUUID: nil,
            name: name,
            instructions: nil,
            primaryMuscles: [primaryMuscle],
            secondaryMuscles: [],
            primaryMuscleGroup: primaryMuscleGroup,
            equipment: [PulsarEquipment(name: "Custom")],
            imageURLs: imageURLs,
            thumbnailURL: thumbnailURL,
            animationURL: nil,
            attribution: .custom(sourceExerciseID: id),
            category: "Custom",
            level: nil,
            force: nil,
            mechanic: nil
        )
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

enum PulsarSupersetType: String, Codable, Hashable {
    case biset
    case superset

    var displayName: String {
        switch self {
        case .biset: "Biset"
        case .superset: "Superset"
        }
    }
}

struct PulsarSupersetGroup: Identifiable, Codable, Hashable {
    var id: UUID
    var type: PulsarSupersetType
    var exerciseIds: [UUID]
    var sharedSetCount: Int
    var restTimeSeconds: Int

    nonisolated init(
        id: UUID = UUID(),
        type: PulsarSupersetType = .superset,
        exerciseIds: [UUID],
        sharedSetCount: Int,
        restTimeSeconds: Int = 90
    ) {
        self.id = id
        self.type = type
        self.exerciseIds = Array(exerciseIds.prefix(2))
        self.sharedSetCount = max(1, sharedSetCount)
        self.restTimeSeconds = max(0, restTimeSeconds)
    }

    var isCompletePair: Bool {
        exerciseIds.count == 2
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
    var supersetGroupId: UUID?
    var supersetOrder: Int?

    init(
        id: UUID = UUID(),
        exercise: PulsarExercise,
        order: Int,
        plannedSets: Int = 3,
        plannedReps: Int = 10,
        plannedWeight: Double = 0,
        weightUnit: PulsarWeightUnit = .kilograms,
        plannedRestSeconds: Int = 60,
        notes: String? = nil,
        supersetGroupId: UUID? = nil,
        supersetOrder: Int? = nil
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
        self.supersetGroupId = supersetGroupId
        self.supersetOrder = supersetOrder
    }

    var exerciseID: String { exercise.id }
    var exerciseName: String { exercise.name }
    nonisolated var primaryMuscleGroup: PulsarMuscleGroup { exercise.primaryMuscleGroup }
    var equipmentSummary: String { exercise.equipmentSummary }
    var orderIndex: Int { order }

    var planSummary: String {
        "\(plannedSets) sets / \(plannedReps) reps / \(formattedWeight) \(weightUnit.displayName) / Rest: \(formattedRest)"
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
        case supersetGroupId
        case supersetOrder
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
        supersetGroupId = try? container.decodeIfPresent(UUID.self, forKey: .supersetGroupId)
        supersetOrder = try? container.decodeIfPresent(Int.self, forKey: .supersetOrder)
    }
}

struct PulsarRoutine: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var emoji: String
    var createdAt: Date
    var updatedAt: Date
    var exercises: [PulsarRoutineExercise]
    var supersetGroups: [PulsarSupersetGroup]

    init(
        id: UUID = UUID(),
        name: String,
        emoji: String = "🏋️",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        exercises: [PulsarRoutineExercise],
        supersetGroups: [PulsarSupersetGroup] = []
    ) {
        self.id = id
        self.name = name
        self.emoji = PulsarRoutine.normalizedEmoji(emoji)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.exercises = exercises
        self.supersetGroups = Self.normalizedSupersetGroups(supersetGroups, for: exercises)
    }

    var exerciseCountText: String {
        "\(exercises.count) \(exercises.count == 1 ? "exercise" : "exercises")"
    }

    var mainMuscleGroupNames: [String] {
        let groups = exercises.map(\.primaryMuscleGroup)
        return PulsarMuscleGroup.allCases
            .filter { group in groups.contains(group) && group != .other }
            .prefix(3)
            .map(\.displayName)
    }

    var estimatedDurationSeconds: Int {
        let validGroups = Self.normalizedSupersetGroups(supersetGroups, for: exercises)
        let groupedExerciseIds = Set(validGroups.flatMap(\.exerciseIds))
        let standaloneSeconds = exercises.filter { !groupedExerciseIds.contains($0.id) }.reduce(0) { partial, exercise in
            let workSeconds = exercise.plannedSets * 45
            let restSeconds = max(0, exercise.plannedSets - 1) * exercise.plannedRestSeconds
            return partial + workSeconds + restSeconds
        }
        let supersetSeconds = validGroups.reduce(0) { partial, group in
            let workSeconds = group.sharedSetCount * group.exerciseIds.count * 45
            let restSeconds = max(0, group.sharedSetCount - 1) * group.restTimeSeconds
            return partial + workSeconds + restSeconds
        }
        return standaloneSeconds + supersetSeconds
    }

    nonisolated static func defaultEmoji(for exercises: [PulsarRoutineExercise]) -> String {
        let groups = Set(exercises.map(\.primaryMuscleGroup))
        if groups.contains(.cardioConditioning) { return "⚡️" }
        if groups.contains(.fullBody) || groups.count >= 4 { return "🔥" }
        if groups.contains(.quadriceps) || groups.contains(.hamstrings) || groups.contains(.calves) || groups.contains(.glutes) { return "🦵" }
        if groups.contains(.back) || groups.contains(.lats) || groups.contains(.biceps) { return "🏋️" }
        if groups.contains(.chest) || groups.contains(.shoulders) || groups.contains(.triceps) { return "💪" }
        return "🏋️"
    }

    nonisolated static func normalizedEmoji(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "🏋️" : String(trimmed.prefix(4))
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case emoji
        case createdAt
        case updatedAt
        case exercises
        case supersetGroups
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? container.decode(String.self, forKey: .name)) ?? "Gym Routine"
        emoji = Self.normalizedEmoji((try? container.decodeIfPresent(String.self, forKey: .emoji)) ?? "🏋️")
        createdAt = (try? container.decode(Date.self, forKey: .createdAt)) ?? Date()
        updatedAt = (try? container.decode(Date.self, forKey: .updatedAt)) ?? createdAt
        exercises = (try? container.decode([PulsarRoutineExercise].self, forKey: .exercises)) ?? []
        supersetGroups = Self.normalizedSupersetGroups(
            (try? container.decodeIfPresent([PulsarSupersetGroup].self, forKey: .supersetGroups)) ?? [],
            for: exercises
        )
    }

    static func emptyGymWorkout(startedAt: Date = .now) -> PulsarRoutine {
        PulsarRoutine(
            name: "Free Workout",
            emoji: "🏋️",
            createdAt: startedAt,
            updatedAt: startedAt,
            exercises: []
        )
    }

    nonisolated static func normalizedSupersetGroups(
        _ groups: [PulsarSupersetGroup],
        for exercises: [PulsarRoutineExercise]
    ) -> [PulsarSupersetGroup] {
        let orderByExerciseId = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0.order) })
        var seenGroupIds: Set<UUID> = []

        return groups.compactMap { group in
            guard seenGroupIds.insert(group.id).inserted else { return nil }
            var seenExerciseIds: Set<UUID> = []
            let memberIds = group.exerciseIds
                .filter { orderByExerciseId[$0] != nil && seenExerciseIds.insert($0).inserted }
                .sorted { (orderByExerciseId[$0] ?? 0) < (orderByExerciseId[$1] ?? 0) }

            guard memberIds.count >= 2 else { return nil }
            return PulsarSupersetGroup(
                id: group.id,
                type: group.type,
                exerciseIds: Array(memberIds.prefix(2)),
                sharedSetCount: group.sharedSetCount,
                restTimeSeconds: group.restTimeSeconds
            )
        }
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
    var routineEmoji: String
    var workoutKind: PulsarGymWorkoutKind
    var startedFrom: PulsarWorkoutStartedFrom?
    var startedAt: Date
    var finishedAt: Date?
    var elapsedSeconds: Int
    var healthKitWorkoutUUID: UUID?
    var activeEnergyKilocalories: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var healthKitStatusMessage: String?
    var heartRateSourceHistory: [WorkoutHeartRateSourceSegment]
    var heartRateSourceStatusMessage: String?
    var trainedMuscleGroups: [PulsarMuscleGroup]
    var muscleLoadByGroup: [String: Double]
    var muscleLoadByMatrixGroup: [String: Double]
    var supersetGroups: [PulsarSupersetGroup]
    var exercises: [PulsarGymWorkoutExerciseSession]

    nonisolated init(
        id: UUID = UUID(),
        routine: PulsarRoutine,
        startedAt: Date = .now
    ) {
        self.id = id
        self.routineId = routine.id
        self.routineName = routine.name
        self.routineEmoji = routine.emoji
        self.workoutKind = PulsarGymWorkoutKind.inferred(routineName: routine.name, exerciseCount: routine.exercises.count)
        self.startedFrom = .iPhone
        self.startedAt = startedAt
        self.finishedAt = nil
        self.elapsedSeconds = 0
        self.healthKitWorkoutUUID = nil
        self.activeEnergyKilocalories = nil
        self.averageHeartRate = nil
        self.maxHeartRate = nil
        self.healthKitStatusMessage = nil
        self.heartRateSourceHistory = []
        self.heartRateSourceStatusMessage = nil
        self.trainedMuscleGroups = []
        self.muscleLoadByGroup = [:]
        self.muscleLoadByMatrixGroup = [:]
        let routineExercises = routine.exercises.sorted { $0.order < $1.order }
        var exerciseSessions = routineExercises.map(PulsarGymWorkoutExerciseSession.init(routineExercise:))
        let sessionIdByRoutineExerciseId = Dictionary(uniqueKeysWithValues: exerciseSessions.map { ($0.routineExerciseId, $0.id) })
        let sessionGroups = PulsarRoutine.normalizedSupersetGroups(routine.supersetGroups, for: routineExercises).compactMap { group -> PulsarSupersetGroup? in
            let sessionExerciseIds = group.exerciseIds.compactMap { sessionIdByRoutineExerciseId[$0] }
            guard sessionExerciseIds.count == 2 else { return nil }
            return PulsarSupersetGroup(
                id: group.id,
                type: group.type,
                exerciseIds: sessionExerciseIds,
                sharedSetCount: group.sharedSetCount,
                restTimeSeconds: group.restTimeSeconds
            )
        }

        for index in exerciseSessions.indices {
            guard let group = sessionGroups.first(where: { $0.exerciseIds.contains(exerciseSessions[index].id) }) else {
                exerciseSessions[index].supersetGroupId = nil
                exerciseSessions[index].supersetOrder = nil
                continue
            }
            exerciseSessions[index].supersetGroupId = group.id
            exerciseSessions[index].supersetOrder = group.exerciseIds.firstIndex(of: exerciseSessions[index].id) ?? 0
            exerciseSessions[index].supersetRestSeconds = group.restTimeSeconds
            exerciseSessions[index].alignSetCount(to: group.sharedSetCount)
        }

        self.supersetGroups = sessionGroups
        self.exercises = exerciseSessions
    }

    nonisolated init(activeGymState state: ActiveGymWorkoutState) {
        self.id = state.sessionId
        self.routineId = state.routineId
        self.routineName = state.routineName
        self.routineEmoji = PulsarRoutine.normalizedEmoji(state.routineEmoji ?? "🏋️")
        self.workoutKind = state.workoutKind ?? PulsarGymWorkoutKind.inferred(routineName: state.routineName, exerciseCount: state.exercises.count)
        self.startedFrom = state.startedFrom
        self.startedAt = state.startedAt
        self.finishedAt = state.isFinished ? state.updatedAt : nil
        self.elapsedSeconds = max(state.elapsedSeconds, Int(state.updatedAt.timeIntervalSince(state.startedAt)))
        self.healthKitWorkoutUUID = state.healthKitWorkoutUUID
        self.activeEnergyKilocalories = state.activeEnergyKilocalories
        self.averageHeartRate = state.averageHeartRate
        self.maxHeartRate = state.maxHeartRate
        self.healthKitStatusMessage = state.healthKitStatusMessage
        self.heartRateSourceHistory = []
        self.heartRateSourceStatusMessage = nil
        self.trainedMuscleGroups = []
        self.muscleLoadByGroup = [:]
        self.muscleLoadByMatrixGroup = [:]
        self.exercises = state.exercises
            .sorted { $0.orderIndex < $1.orderIndex }
            .map(PulsarGymWorkoutExerciseSession.init(activeGymExerciseState:))
        self.supersetGroups = Self.supersetGroups(from: self.exercises)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case routineId
        case routineName
        case routineEmoji
        case workoutKind
        case startedFrom
        case startedAt
        case finishedAt
        case elapsedSeconds
        case healthKitWorkoutUUID
        case activeEnergyKilocalories
        case averageHeartRate
        case maxHeartRate
        case healthKitStatusMessage
        case heartRateSourceHistory
        case heartRateSourceStatusMessage
        case trainedMuscleGroups
        case muscleLoadByGroup
        case muscleLoadByMatrixGroup
        case supersetGroups
        case exercises
    }

    enum LegacyCodingKeys: String, CodingKey {
        case muscleLoadByBodyMapRegion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        routineId = (try? container.decode(UUID.self, forKey: .routineId)) ?? UUID()
        routineName = (try? container.decode(String.self, forKey: .routineName)) ?? "Gym Workout"
        routineEmoji = PulsarRoutine.normalizedEmoji((try? container.decodeIfPresent(String.self, forKey: .routineEmoji)) ?? "🏋️")
        let decodedWorkoutKind = try? container.decodeIfPresent(PulsarGymWorkoutKind.self, forKey: .workoutKind)
        startedFrom = try? container.decodeIfPresent(PulsarWorkoutStartedFrom.self, forKey: .startedFrom)
        startedAt = (try? container.decode(Date.self, forKey: .startedAt)) ?? Date()
        finishedAt = try? container.decodeIfPresent(Date.self, forKey: .finishedAt)
        elapsedSeconds = (try? container.decode(Int.self, forKey: .elapsedSeconds)) ?? 0
        healthKitWorkoutUUID = try? container.decodeIfPresent(UUID.self, forKey: .healthKitWorkoutUUID)
        activeEnergyKilocalories = try? container.decodeIfPresent(Double.self, forKey: .activeEnergyKilocalories)
        averageHeartRate = try? container.decodeIfPresent(Double.self, forKey: .averageHeartRate)
        maxHeartRate = try? container.decodeIfPresent(Double.self, forKey: .maxHeartRate)
        healthKitStatusMessage = try? container.decodeIfPresent(String.self, forKey: .healthKitStatusMessage)
        heartRateSourceHistory = (try? container.decodeIfPresent([WorkoutHeartRateSourceSegment].self, forKey: .heartRateSourceHistory)) ?? []
        heartRateSourceStatusMessage = try? container.decodeIfPresent(String.self, forKey: .heartRateSourceStatusMessage)
        trainedMuscleGroups = (try? container.decodeIfPresent([PulsarMuscleGroup].self, forKey: .trainedMuscleGroups)) ?? []
        muscleLoadByGroup = (try? container.decodeIfPresent([String: Double].self, forKey: .muscleLoadByGroup)) ?? [:]
        muscleLoadByMatrixGroup = (try? container.decodeIfPresent([String: Double].self, forKey: .muscleLoadByMatrixGroup))
            ?? (try? legacyContainer.decodeIfPresent([String: Double].self, forKey: .muscleLoadByBodyMapRegion))
            ?? [:]
        supersetGroups = (try? container.decodeIfPresent([PulsarSupersetGroup].self, forKey: .supersetGroups)) ?? []
        exercises = (try? container.decode([PulsarGymWorkoutExerciseSession].self, forKey: .exercises)) ?? []
        workoutKind = decodedWorkoutKind ?? PulsarGymWorkoutKind.inferred(routineName: routineName, exerciseCount: exercises.count)
        supersetGroups = Self.normalizedSupersetGroups(supersetGroups, for: exercises)
    }

    var activityLogDisplayName: String {
        switch workoutKind {
        case .freeWorkout:
            return PulsarGymWorkoutKind.freeWorkout.displayName
        case .routine:
            let trimmedName = routineName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedName.isEmpty ? PulsarGymWorkoutKind.routine.displayName : trimmedName
        }
    }

    nonisolated static func normalizedSupersetGroups(
        _ groups: [PulsarSupersetGroup],
        for exercises: [PulsarGymWorkoutExerciseSession]
    ) -> [PulsarSupersetGroup] {
        let orderByExerciseId = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0.orderIndex) })
        return groups.compactMap { group in
            let memberIds = group.exerciseIds
                .filter { orderByExerciseId[$0] != nil }
                .sorted { (orderByExerciseId[$0] ?? 0) < (orderByExerciseId[$1] ?? 0) }
            guard memberIds.count >= 2 else { return nil }
            return PulsarSupersetGroup(
                id: group.id,
                type: group.type,
                exerciseIds: Array(memberIds.prefix(2)),
                sharedSetCount: group.sharedSetCount,
                restTimeSeconds: group.restTimeSeconds
            )
        }
    }

    nonisolated static func supersetGroups(from exercises: [PulsarGymWorkoutExerciseSession]) -> [PulsarSupersetGroup] {
        let grouped = Dictionary(grouping: exercises.compactMap { exercise -> (UUID, PulsarGymWorkoutExerciseSession)? in
            guard let groupId = exercise.supersetGroupId else { return nil }
            return (groupId, exercise)
        }, by: { $0.0 })

        return grouped.compactMap { entry in
            let groupId = entry.key
            let values = entry.value
            let members = values.map { $0.1 }.sorted { ($0.supersetOrder ?? $0.orderIndex) < ($1.supersetOrder ?? $1.orderIndex) }
            guard members.count >= 2 else { return nil }
            let sharedSetCount = members.map(\.plannedSets).max() ?? 1
            let restTimeSeconds = members.compactMap(\.supersetRestSeconds).first ?? members.map(\.plannedRestSeconds).max() ?? 90
            return PulsarSupersetGroup(
                id: groupId,
                type: .superset,
                exerciseIds: members.prefix(2).map(\.id),
                sharedSetCount: sharedSetCount,
                restTimeSeconds: restTimeSeconds
            )
        }
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
    var supersetGroupId: UUID?
    var supersetOrder: Int?
    var supersetRestSeconds: Int?
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
        supersetGroupId = routineExercise.supersetGroupId
        supersetOrder = routineExercise.supersetOrder
        supersetRestSeconds = nil
        sets = (1...routineExercise.plannedSets).map { setNumber in
            PulsarGymWorkoutSetSession(
                setNumber: setNumber,
                targetReps: routineExercise.plannedReps,
                targetWeight: routineExercise.plannedWeight
            )
        }
    }

    nonisolated init(activeGymExerciseState exercise: ActiveGymWorkoutExerciseState) {
        id = exercise.id
        routineExerciseId = exercise.id
        exerciseId = exercise.exerciseId
        exerciseName = exercise.exerciseName
        primaryMuscleGroup = PulsarMuscleGroup.gymDisplayName(exercise.muscleGroup)
        primaryMuscles = []
        secondaryMuscles = []
        equipment = exercise.equipment
        plannedSets = max(1, exercise.plannedSets)
        plannedReps = max(1, exercise.plannedReps)
        plannedWeight = max(0, exercise.plannedWeight)
        weightUnit = PulsarWeightUnit.gymDisplayName(exercise.weightUnit)
        plannedRestSeconds = max(0, exercise.plannedRestSeconds)
        notes = exercise.notes
        orderIndex = exercise.orderIndex
        supersetGroupId = exercise.supersetGroupId
        supersetOrder = exercise.supersetOrder
        supersetRestSeconds = exercise.supersetRestSeconds
        sets = exercise.sets.map(PulsarGymWorkoutSetSession.init(activeGymSetState:))
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
        case supersetGroupId
        case supersetOrder
        case supersetRestSeconds
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
        supersetGroupId = try? container.decodeIfPresent(UUID.self, forKey: .supersetGroupId)
        supersetOrder = try? container.decodeIfPresent(Int.self, forKey: .supersetOrder)
        supersetRestSeconds = try? container.decodeIfPresent(Int.self, forKey: .supersetRestSeconds)
        sets = (try? container.decode([PulsarGymWorkoutSetSession].self, forKey: .sets)) ?? []
    }

    nonisolated mutating func alignSetCount(to sharedSetCount: Int) {
        let nextCount = max(1, sharedSetCount)
        plannedSets = nextCount
        if sets.count < nextCount {
            let lastSet = sets.last
            for setNumber in (sets.count + 1)...nextCount {
                sets.append(
                    PulsarGymWorkoutSetSession(
                        setNumber: setNumber,
                        targetReps: lastSet?.targetReps ?? plannedReps,
                        targetWeight: lastSet?.targetWeight ?? plannedWeight
                    )
                )
            }
        } else if sets.count > nextCount {
            sets = Array(sets.prefix(nextCount))
        }
        for index in sets.indices {
            sets[index].setNumber = index + 1
        }
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

    nonisolated init(activeGymSetState set: ActiveGymWorkoutSetState) {
        self.init(
            id: set.id,
            setNumber: set.setNumber,
            targetReps: set.targetReps,
            targetWeight: set.targetWeight,
            completedReps: set.completedReps,
            completedWeight: set.completedWeight,
            isCompleted: set.isCompleted,
            completedAt: set.completedAt
        )
    }
}

struct PulsarGymCompletedExerciseSummary: Identifiable, Codable, Hashable {
    var id: UUID
    var exerciseName: String
    var weightUnit: PulsarWeightUnit
    var sets: [PulsarGymCompletedSetSummary]
}

struct PulsarGymCompletedSetSummary: Identifiable, Codable, Hashable {
    var id: UUID
    var setNumber: Int
    var reps: Int
    var weight: Double
}

struct PulsarGymWorkoutSummary: Identifiable, Codable, Hashable {
    var id: UUID
    var sessionId: UUID
    var routineName: String
    var routineEmoji: String
    var startedAt: Date?
    var endedAt: Date?
    var source: PulsarWorkoutStartedFrom?
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
    var heartRateSourceHistory: [WorkoutHeartRateSourceSegment]?
    var heartRateSourceStatusMessage: String?
    var completedExerciseSummaries: [PulsarGymCompletedExerciseSummary]

    init(session: PulsarGymWorkoutSession) {
        id = UUID()
        sessionId = session.id
        routineName = session.activityLogDisplayName
        routineEmoji = session.routineEmoji
        startedAt = session.startedAt
        endedAt = session.finishedAt
        source = session.startedFrom
        durationSeconds = session.elapsedSeconds
        exercisesCompleted = session.exercises.filter(\.isCompleted).count
        totalExercises = session.exercises.count
        setsCompleted = session.exercises.flatMap(\.sets).filter(\.isCompleted).count
        totalSets = session.exercises.flatMap(\.sets).count
        let summaryWeightUnit = session.exercises.first?.weightUnit ?? .kilograms
        weightUnit = summaryWeightUnit
        completedExerciseSummaries = Self.completedExerciseSummaries(from: session.exercises)
        healthKitWorkoutUUID = session.healthKitWorkoutUUID
        activeEnergyKilocalories = session.activeEnergyKilocalories
        averageHeartRate = session.averageHeartRate
        maxHeartRate = session.maxHeartRate
        healthKitStatusMessage = session.healthKitStatusMessage
        heartRateSourceHistory = session.heartRateSourceHistory
        heartRateSourceStatusMessage = session.heartRateSourceStatusMessage
        totalVolume = session.exercises.reduce(0) { partialResult, exercise in
            partialResult + exercise.sets.reduce(0) { setPartial, set in
                guard set.isCompleted else { return setPartial }
                let reps = Double(set.completedReps ?? set.targetReps)
                let weight = exercise.weightUnit.convert(set.completedWeight ?? set.targetWeight, to: summaryWeightUnit)
                return setPartial + reps * weight
            }
        }
    }

    init(activeGymState state: ActiveGymWorkoutState) {
        id = UUID()
        sessionId = state.sessionId
        routineName = state.routineName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Gym Workout" : state.routineName
        routineEmoji = PulsarRoutine.normalizedEmoji(state.routineEmoji ?? "🏋️")
        startedAt = state.startedAt
        endedAt = state.isFinished ? state.updatedAt : nil
        source = state.startedFrom
        durationSeconds = max(state.elapsedSeconds, Int(state.updatedAt.timeIntervalSince(state.startedAt)))
        exercisesCompleted = state.exercises.filter(\.isCompleted).count
        totalExercises = state.totalExercises
        setsCompleted = state.completedSets
        totalSets = state.totalSets
        let summaryWeightUnit = state.exercises.first.map { PulsarWeightUnit.gymDisplayName($0.weightUnit) } ?? .kilograms
        weightUnit = summaryWeightUnit
        completedExerciseSummaries = Self.completedExerciseSummaries(from: state.exercises)
        healthKitWorkoutUUID = state.healthKitWorkoutUUID
        activeEnergyKilocalories = state.activeEnergyKilocalories
        averageHeartRate = state.averageHeartRate
        maxHeartRate = state.maxHeartRate
        healthKitStatusMessage = state.healthKitStatusMessage
        heartRateSourceHistory = []
        heartRateSourceStatusMessage = nil
        totalVolume = state.exercises.reduce(0) { partialResult, exercise in
            let exerciseUnit = PulsarWeightUnit.gymDisplayName(exercise.weightUnit)
            return partialResult + exercise.sets.reduce(0) { setPartial, set in
                guard set.isCompleted else { return setPartial }
                let reps = Double(set.completedReps ?? set.targetReps)
                let weight = exerciseUnit.convert(set.completedWeight ?? set.targetWeight, to: summaryWeightUnit)
                return setPartial + reps * weight
            }
        }
    }

    var sourceDeviceName: String {
        (source ?? .iPhone).displayName
    }

    var heartRateSourceSummaryText: String? {
        WorkoutHeartRateSourceSummaryFormatter.summaryText(for: heartRateSourceHistory ?? [])
    }

    nonisolated static func completedExerciseSummaries(
        from exercises: [PulsarGymWorkoutExerciseSession]
    ) -> [PulsarGymCompletedExerciseSummary] {
        exercises.compactMap { exercise in
            let completedSets = exercise.sets.compactMap { set -> PulsarGymCompletedSetSummary? in
                guard set.isCompleted else { return nil }
                return PulsarGymCompletedSetSummary(
                    id: set.id,
                    setNumber: set.setNumber,
                    reps: max(1, set.completedReps ?? set.targetReps),
                    weight: max(0, set.completedWeight ?? set.targetWeight)
                )
            }
            guard !completedSets.isEmpty else { return nil }
            return PulsarGymCompletedExerciseSummary(
                id: exercise.id,
                exerciseName: exercise.exerciseName,
                weightUnit: exercise.weightUnit,
                sets: completedSets
            )
        }
    }

    nonisolated static func completedExerciseSummaries(
        from exercises: [ActiveGymWorkoutExerciseState]
    ) -> [PulsarGymCompletedExerciseSummary] {
        exercises.compactMap { exercise in
            let completedSets = exercise.sets.compactMap { set -> PulsarGymCompletedSetSummary? in
                guard set.isCompleted else { return nil }
                return PulsarGymCompletedSetSummary(
                    id: set.id,
                    setNumber: set.setNumber,
                    reps: max(1, set.completedReps ?? set.targetReps),
                    weight: max(0, set.completedWeight ?? set.targetWeight)
                )
            }
            guard !completedSets.isEmpty else { return nil }
            return PulsarGymCompletedExerciseSummary(
                id: exercise.id,
                exerciseName: exercise.exerciseName,
                weightUnit: PulsarWeightUnit.gymDisplayName(exercise.weightUnit),
                sets: completedSets
            )
        }
    }
}

extension String {
    nonisolated func normalizedPulsarIdentifier(prefix: String) -> String {
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

    var formattedRestLabel: String {
        let clamped = Swift.max(0, self)
        if clamped >= 60, clamped.isMultiple(of: 60) {
            return "\(clamped / 60) min"
        }
        return "\(clamped)s"
    }
}

private extension PulsarMuscleGroup {
    nonisolated static func gymDisplayName(_ value: String) -> PulsarMuscleGroup {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allCases.first { group in
            group.displayName.lowercased() == normalizedValue || group.rawValue.lowercased() == normalizedValue
        } ?? .other
    }
}

private extension PulsarWeightUnit {
    nonisolated static func gymDisplayName(_ value: String) -> PulsarWeightUnit {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedValue.contains("lb") { return .pounds }
        if normalizedValue.contains("kg") { return .kilograms }
        return PulsarWeightUnit(rawValue: normalizedValue) ?? .kilograms
    }
}
