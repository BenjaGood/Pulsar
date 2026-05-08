//
//  PulsarGymSharedModels.swift
//  Pulsar
//

import Foundation

struct ActiveGymWorkoutState: Codable, Hashable, Identifiable {
    var id: UUID { sessionId }

    var sessionId: UUID
    var routineId: UUID
    var routineName: String
    var startedAt: Date
    var elapsedSeconds: Int
    var currentExerciseIndex: Int
    var currentSetIndex: Int
    var totalExercises: Int
    var totalSets: Int
    var completedSets: Int
    var currentHeartRate: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var activeEnergyKilocalories: Double?
    var restRemainingSeconds: Int?
    var restTotalSeconds: Int?
    var isHealthKitEnabled: Bool
    var healthKitStatusMessage: String?
    var isFinished: Bool
    var updatedAt: Date
    var exercises: [ActiveGymWorkoutExerciseState]

    var currentExercise: ActiveGymWorkoutExerciseState? {
        if exercises.indices.contains(currentExerciseIndex) {
            return exercises[currentExerciseIndex]
        }
        return exercises.first { !$0.isCompleted } ?? exercises.last
    }

    var currentSet: ActiveGymWorkoutSetState? {
        guard let currentExercise else { return nil }
        if currentExercise.sets.indices.contains(currentSetIndex) {
            return currentExercise.sets[currentSetIndex]
        }
        return currentExercise.sets.first { !$0.isCompleted } ?? currentExercise.sets.last
    }

    var progressText: String {
        "\(completedSets)/\(totalSets) sets"
    }

    var exerciseProgressText: String {
        let displayIndex = min(max(currentExerciseIndex + 1, 1), max(totalExercises, 1))
        return "Exercise \(displayIndex) of \(max(totalExercises, 1))"
    }
}

struct ActiveGymWorkoutExerciseState: Codable, Hashable, Identifiable {
    var id: UUID
    var exerciseName: String
    var muscleGroup: String
    var equipment: String
    var plannedSets: Int
    var plannedReps: Int
    var plannedWeight: Double
    var weightUnit: String
    var plannedRestSeconds: Int
    var orderIndex: Int
    var notes: String?
    var sets: [ActiveGymWorkoutSetState]

    var completedSetIndexes: [Int] {
        sets.filter(\.isCompleted).map(\.setNumber)
    }

    var completedSetCount: Int {
        sets.filter(\.isCompleted).count
    }

    var isCompleted: Bool {
        !sets.isEmpty && completedSetCount == sets.count
    }
}

struct ActiveGymWorkoutSetState: Codable, Hashable, Identifiable {
    var id: UUID
    var setNumber: Int
    var targetReps: Int
    var targetWeight: Double
    var completedReps: Int?
    var completedWeight: Double?
    var isCompleted: Bool
    var completedAt: Date?
}

struct ActiveGymWorkoutAction: Codable, Hashable {
    enum Kind: String, Codable, Hashable {
        case completeSet
        case skipRestTimer
        case finishWorkout
        case requestState
        case metricsUpdated
    }

    var kind: Kind
    var sessionId: UUID?
    var exerciseId: UUID?
    var setId: UUID?
    var sentAt: Date
    var currentHeartRate: Double? = nil
    var averageHeartRate: Double? = nil
    var maxHeartRate: Double? = nil
    var activeEnergyKilocalories: Double? = nil
    var healthKitWorkoutUUID: UUID? = nil

    static func completeSet(sessionId: UUID, exerciseId: UUID, setId: UUID) -> ActiveGymWorkoutAction {
        ActiveGymWorkoutAction(kind: .completeSet, sessionId: sessionId, exerciseId: exerciseId, setId: setId, sentAt: Date())
    }

    static func skipRestTimer(sessionId: UUID) -> ActiveGymWorkoutAction {
        ActiveGymWorkoutAction(kind: .skipRestTimer, sessionId: sessionId, exerciseId: nil, setId: nil, sentAt: Date())
    }

    static func finishWorkout(sessionId: UUID) -> ActiveGymWorkoutAction {
        ActiveGymWorkoutAction(kind: .finishWorkout, sessionId: sessionId, exerciseId: nil, setId: nil, sentAt: Date())
    }

    static func requestState(sessionId: UUID? = nil) -> ActiveGymWorkoutAction {
        ActiveGymWorkoutAction(kind: .requestState, sessionId: sessionId, exerciseId: nil, setId: nil, sentAt: Date())
    }

    static func metricsUpdated(
        sessionId: UUID?,
        currentHeartRate: Double?,
        averageHeartRate: Double?,
        maxHeartRate: Double?,
        activeEnergyKilocalories: Double?,
        healthKitWorkoutUUID: UUID? = nil
    ) -> ActiveGymWorkoutAction {
        var action = ActiveGymWorkoutAction(kind: .metricsUpdated, sessionId: sessionId, exerciseId: nil, setId: nil, sentAt: Date())
        action.currentHeartRate = currentHeartRate
        action.averageHeartRate = averageHeartRate
        action.maxHeartRate = maxHeartRate
        action.activeEnergyKilocalories = activeEnergyKilocalories
        action.healthKitWorkoutUUID = healthKitWorkoutUUID
        return action
    }
}

enum ActiveGymWorkoutCodec {
    static func encodeState(_ state: ActiveGymWorkoutState) -> Data? {
        try? encoder.encode(state)
    }

    static func decodeState(_ data: Data) -> ActiveGymWorkoutState? {
        try? decoder.decode(ActiveGymWorkoutState.self, from: data)
    }

    static func encodeAction(_ action: ActiveGymWorkoutAction) -> Data? {
        try? encoder.encode(action)
    }

    static func decodeAction(_ data: Data) -> ActiveGymWorkoutAction? {
        try? decoder.decode(ActiveGymWorkoutAction.self, from: data)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum PulsarGymFormatters {
    static func duration(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3_600
        let minutes = (clamped % 3_600) / 60
        let seconds = clamped % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func heartRate(_ bpm: Double?) -> String {
        guard let bpm, bpm > 0 else { return "--" }
        return "\(Int(bpm.rounded()))"
    }

    static func weight(_ value: Double, unit: String) -> String {
        let formatted: String
        if value.rounded() == value {
            formatted = String(Int(value))
        } else {
            formatted = String(format: "%.1f", value)
        }
        return "\(formatted) \(unit)"
    }
}
