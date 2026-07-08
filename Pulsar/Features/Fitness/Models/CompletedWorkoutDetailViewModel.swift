//
//  CompletedWorkoutDetailViewModel.swift
//  Pulsar
//

import Combine
import Foundation

@MainActor
final class CompletedWorkoutDetailViewModel: ObservableObject {
    @Published private(set) var presentations: [CompletedWorkoutExercisePresentation] = []
    @Published var expandedExerciseIds: Set<UUID> = []
    @Published private(set) var editErrorMessage: String?

    let activity: WeeklyActivity
    let historyStore: PulsarGymWorkoutHistoryStore
    let catalogStore: ExerciseCatalogStore
    private var sourceSession: PulsarGymWorkoutSession?

    init(
        activity: WeeklyActivity,
        historyStore: PulsarGymWorkoutHistoryStore? = nil,
        catalogStore: ExerciseCatalogStore? = nil
    ) {
        self.activity = activity
        self.historyStore = historyStore ?? PulsarGymWorkoutHistoryStore()
        self.catalogStore = catalogStore ?? ExerciseCatalogStore()
        reloadSourceSession()
        rebuildPresentations(shouldDefaultExpandFirst: true)
    }

    var isEditable: Bool {
        activity.source == .localGym && sourceSession != nil
    }

    var routineEmoji: String? {
        guard let emoji = sourceSession?.routineEmoji.trimmingCharacters(in: .whitespacesAndNewlines),
              !emoji.isEmpty else { return nil }
        return emoji
    }

    var allExercisesExpanded: Bool {
        !presentations.isEmpty && presentations.allSatisfy { expandedExerciseIds.contains($0.id) }
    }

    func loadCatalogIfNeeded() async {
        await catalogStore.loadCatalogIfNeeded()
        rebuildPresentations(shouldDefaultExpandFirst: false)
    }

    func toggleExpanded(_ exerciseId: UUID) {
        if expandedExerciseIds.contains(exerciseId) {
            expandedExerciseIds.remove(exerciseId)
        } else {
            expandedExerciseIds.insert(exerciseId)
        }
    }

    func expandAll() {
        expandedExerciseIds = Set(presentations.map(\.id))
    }

    func collapseAll() {
        expandedExerciseIds = []
    }

    func updateSet(
        exerciseId: UUID,
        setId: UUID,
        reps: Int,
        weight: Double
    ) -> Bool {
        guard let sourceSession else { return false }
        do {
            let savedSession = try CompletedWorkoutEditor(historyStore: historyStore).updateSet(
                sessionId: sourceSession.id,
                exerciseId: exerciseId,
                setId: setId,
                reps: reps,
                weight: weight
            )
            self.sourceSession = savedSession
            editErrorMessage = nil
            rebuildPresentations(shouldDefaultExpandFirst: false)
            return true
        } catch {
            editErrorMessage = error.localizedDescription
            return false
        }
    }

    func clearEditError() {
        editErrorMessage = nil
    }

    private func reloadSourceSession() {
        guard let sessionId = activity.pulsarWorkoutSessionId else {
            sourceSession = nil
            return
        }
        sourceSession = historyStore.session(id: sessionId)
    }

    private func rebuildPresentations(shouldDefaultExpandFirst: Bool) {
        let summaries = sourceSession.map {
            PulsarGymWorkoutSummary.completedExerciseSummaries(from: $0.exercises)
        } ?? activity.gymSetSummaries

        let nextPresentations = CompletedWorkoutExerciseResolver.presentations(
            summaries: summaries,
            sourceSession: sourceSession,
            catalogExercises: catalogStore.exercises
        )
        presentations = nextPresentations

        let validIds = Set(nextPresentations.map(\.id))
        expandedExerciseIds = expandedExerciseIds.intersection(validIds)
        if shouldDefaultExpandFirst, expandedExerciseIds.isEmpty, let first = nextPresentations.first {
            expandedExerciseIds = [first.id]
        }
    }
}
