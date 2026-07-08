//
//  CompletedWorkoutEditor.swift
//  Pulsar
//

import Foundation

enum CompletedWorkoutEditorError: LocalizedError, Equatable {
    case sessionUnavailable
    case exerciseNotFound
    case setNotFound

    var errorDescription: String? {
        switch self {
        case .sessionUnavailable:
            return "The original workout session is not available for editing."
        case .exerciseNotFound:
            return "That exercise could not be found in this workout."
        case .setNotFound:
            return "That set could not be found in this workout."
        }
    }
}

@MainActor
struct CompletedWorkoutEditor {
    var historyStore: PulsarGymWorkoutHistoryStore

    @discardableResult
    func updateSet(
        sessionId: UUID,
        exerciseId: UUID,
        setId: UUID,
        reps: Int,
        weight: Double
    ) throws -> PulsarGymWorkoutSession {
        guard var session = historyStore.session(id: sessionId) else {
            throw CompletedWorkoutEditorError.sessionUnavailable
        }
        guard let exerciseIndex = session.exercises.firstIndex(where: { $0.id == exerciseId }) else {
            throw CompletedWorkoutEditorError.exerciseNotFound
        }
        guard let setIndex = session.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setId }) else {
            throw CompletedWorkoutEditorError.setNotFound
        }

        let nextReps = min(max(1, reps), 200)
        let nextWeight = max(0, weight)
        session.exercises[exerciseIndex].sets[setIndex].targetReps = nextReps
        session.exercises[exerciseIndex].sets[setIndex].targetWeight = nextWeight
        session.exercises[exerciseIndex].sets[setIndex].completedReps = nextReps
        session.exercises[exerciseIndex].sets[setIndex].completedWeight = nextWeight
        session.exercises[exerciseIndex].sets[setIndex].isCompleted = true
        if session.exercises[exerciseIndex].sets[setIndex].completedAt == nil {
            session.exercises[exerciseIndex].sets[setIndex].completedAt = session.finishedAt ?? session.startedAt
        }

        return historyStore.updateSession(session)
    }
}
