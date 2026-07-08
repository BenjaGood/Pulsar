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
    private var consumedSessionIDs: Set<UUID>

    init(
        defaults: UserDefaults = .standard,
        consumedSessionIDsKey: String = "pulsar.workoutCompletion.consumedSessionIDs.v1"
    ) {
        self.defaults = defaults
        self.consumedSessionIDsKey = consumedSessionIDsKey
        self.consumedSessionIDs = Self.restoreConsumedSessionIDs(
            from: defaults,
            key: consumedSessionIDsKey
        )
    }

    func shouldAutoPresent(sessionID: UUID) -> Bool {
        !consumedSessionIDs.contains(sessionID)
    }

    func markPending(_ presentation: WorkoutCompletionPresentation) {
        guard shouldAutoPresent(sessionID: presentation.sessionID) else {
            pendingPresentation = nil
            return
        }
        pendingPresentation = presentation
    }

    func consume(sessionID: UUID, reason: String) {
        consumedSessionIDs.insert(sessionID)
        persistConsumedSessionIDs()
        if pendingPresentation?.sessionID == sessionID {
            pendingPresentation = nil
        }
        PulsarStateDebugLogger.log("[PulsarSummary] Consumed workout completion session=\(sessionID.uuidString) reason=\(reason)")
    }

    private func persistConsumedSessionIDs() {
        let encoded = consumedSessionIDs.map(\.uuidString).sorted()
        defaults.set(encoded, forKey: consumedSessionIDsKey)
    }

    private static func restoreConsumedSessionIDs(
        from defaults: UserDefaults,
        key: String
    ) -> Set<UUID> {
        let strings = defaults.stringArray(forKey: key) ?? []
        return Set(strings.compactMap(UUID.init(uuidString:)))
    }
}
