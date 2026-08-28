//
//  FitnessRefreshCoordinator.swift
//  Pulsar
//

import Foundation

enum FitnessRefreshPriority: Int, Comparable {
    case maintenance
    case userInitiated
    case authoritative

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Keeps Fitness load and refresh work single-flight. Equal- or higher-priority
/// replacement work cancels its predecessor; lower-priority maintenance waits.
/// Every replacement waits for prior work to unwind, so HealthKit and
/// persistence operations cannot overlap even when cancellation is observed late.
@MainActor
final class FitnessRefreshCoordinator {
    private var activeTask: Task<Bool, Never>?
    private var activePriority: FitnessRefreshPriority?
    private var activeGeneration: Int?
    private var generation = 0
    private var cancellationGeneration = 0

    var isRunning: Bool {
        activeTask != nil
    }

    /// Returns `true` only when the submitted operation ran to completion.
    @discardableResult
    func run(
        priority: FitnessRefreshPriority = .userInitiated,
        skipIfBusy: Bool = false,
        _ operation: @escaping @MainActor @Sendable () async -> Void
    ) async -> Bool {
        guard !(skipIfBusy && activeTask != nil) else { return false }

        if let predecessor = activeTask,
           let currentPriority = activePriority,
           currentPriority > priority {
            let predecessorGeneration = activeGeneration
            let submissionCancellationGeneration = cancellationGeneration
            _ = await predecessor.value
            guard !Task.isCancelled,
                  cancellationGeneration == submissionCancellationGeneration else { return false }
            if activeGeneration == predecessorGeneration {
                activeTask = nil
                activePriority = nil
                activeGeneration = nil
            }
            return await run(priority: priority, skipIfBusy: skipIfBusy, operation)
        }

        generation += 1
        let requestGeneration = generation
        let predecessor = activeTask
        predecessor?.cancel()

        let task = Task { @MainActor () -> Bool in
            if let predecessor {
                _ = await predecessor.value
            }
            guard !Task.isCancelled else { return false }
            await operation()
            return !Task.isCancelled
        }
        activeTask = task
        activePriority = priority
        activeGeneration = requestGeneration

        let didComplete = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }

        if generation == requestGeneration {
            activeTask = nil
            activePriority = nil
            activeGeneration = nil
        }
        return didComplete
    }

    func cancel() {
        cancellationGeneration &+= 1
        activeTask?.cancel()
    }

    func waitUntilIdle() async {
        _ = await activeTask?.value
    }
}
