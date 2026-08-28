//
//  WorkoutCompletionPresentationStore.swift
//  Pulsar
//

import Combine
import Foundation

enum WorkoutCompletionPresentationSource: String, Codable, Hashable {
    case localFinish
    case watchSync
    case restored
    case rootSync
}

enum WorkoutCompletionPresentationKind {
    case gym(PulsarGymWorkoutSummary)
    case run(PulsarRunSummary)
}

struct WorkoutCompletionPresentation: Identifiable {
    var id: UUID { sessionID }

    let sessionID: UUID
    let kind: WorkoutCompletionPresentationKind
    let presentedAt: Date
    let source: WorkoutCompletionPresentationSource
}

enum WorkoutCompletionDismissalKind {
    case gym
    case watchGym
    case run
}

@MainActor
final class WorkoutCompletionPresentationStore: ObservableObject {
    @Published private(set) var pendingPresentation: WorkoutCompletionPresentation?

    private let defaults: UserDefaults
    private let consumedSessionIDsKey: String
    private let summaryEligibleSessionIDsKey: String
    private var consumedSessionIDs: Set<UUID>
    private var summaryEligibleSessionIDs: Set<UUID>

    init(
        defaults: UserDefaults = .standard,
        consumedSessionIDsKey: String = "pulsar.workoutCompletion.consumedSessionIDs.v1",
        summaryEligibleSessionIDsKey: String = "pulsar.workoutCompletion.summaryEligibleSessionIDs.v1"
    ) {
        self.defaults = defaults
        self.consumedSessionIDsKey = consumedSessionIDsKey
        self.summaryEligibleSessionIDsKey = summaryEligibleSessionIDsKey
        self.consumedSessionIDs = Self.restoreConsumedSessionIDs(
            from: defaults,
            key: consumedSessionIDsKey
        )
        self.summaryEligibleSessionIDs = Self.restoreConsumedSessionIDs(
            from: defaults,
            key: summaryEligibleSessionIDsKey
        )
    }

    func shouldAutoPresent(sessionID: UUID) -> Bool {
        !consumedSessionIDs.contains(sessionID)
    }

    func markEligibleForSummary(sessionID: UUID) {
        guard summaryEligibleSessionIDs.insert(sessionID).inserted else { return }
        persistSessionIDs(summaryEligibleSessionIDs, key: summaryEligibleSessionIDsKey)
    }

    func isEligibleForSummary(sessionID: UUID) -> Bool {
        summaryEligibleSessionIDs.contains(sessionID)
    }

    func markPending(_ presentation: WorkoutCompletionPresentation) {
        guard shouldAutoPresent(sessionID: presentation.sessionID) else {
            pendingPresentation = nil
            return
        }
        guard isEligibleForSummary(sessionID: presentation.sessionID) ||
                PulsarWorkoutStartCoordinator.shared.canPresentSummary(sessionID: presentation.sessionID) else {
            pendingPresentation = nil
            PulsarWorkoutLifecycleLogger.log(
                .summaryPresentationBlocked,
                sessionID: presentation.sessionID,
                source: "WorkoutCompletionPresentationStore.markPending",
                detail: "reason=notEligibleForSummary"
            )
            return
        }
        pendingPresentation = presentation
    }

    func canPresentSummary(sessionID: UUID) -> Bool {
        shouldAutoPresent(sessionID: sessionID) &&
            (isEligibleForSummary(sessionID: sessionID) ||
                PulsarWorkoutStartCoordinator.shared.canPresentSummary(sessionID: sessionID))
    }

    func consume(sessionID: UUID, reason: String) {
        consumedSessionIDs.insert(sessionID)
        summaryEligibleSessionIDs.remove(sessionID)
        persistSessionIDs(consumedSessionIDs, key: consumedSessionIDsKey)
        persistSessionIDs(summaryEligibleSessionIDs, key: summaryEligibleSessionIDsKey)
        if pendingPresentation?.sessionID == sessionID {
            pendingPresentation = nil
        }
        PulsarWorkoutStartCoordinator.shared.acknowledgeTerminal(sessionID: sessionID, reason: reason)
        PulsarStateDebugLogger.log("[PulsarSummary] Consumed workout completion session=\(sessionID.uuidString) reason=\(reason)")
    }

    private func persistSessionIDs(_ sessionIDs: Set<UUID>, key: String) {
        let encoded = sessionIDs.map(\.uuidString).sorted()
        defaults.set(encoded, forKey: key)
    }

    private static func restoreConsumedSessionIDs(
        from defaults: UserDefaults,
        key: String
    ) -> Set<UUID> {
        let strings = defaults.stringArray(forKey: key) ?? []
        return Set(strings.compactMap(UUID.init(uuidString:)))
    }
}
