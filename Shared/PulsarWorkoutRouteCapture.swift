//
//  PulsarWorkoutRouteCapture.swift
//  Pulsar
//

import CoreLocation
import Foundation
import HealthKit

/// Owns an `HKWorkoutRouteBuilder` for one outdoor workout and ensures location
/// inserts complete before the workout/route are finalized.
@MainActor
final class PulsarWorkoutRouteCapture {
    private(set) var routeBuilder: HKWorkoutRouteBuilder?
    private(set) var usesLiveSeriesBuilder = false
    private var pendingInsertCount = 0
    private var insertWaiters: [CheckedContinuation<Void, Never>] = []

    var isEnabled: Bool { routeBuilder != nil }

    func attach(
        to workoutBuilder: HKLiveWorkoutBuilder,
        healthStore: HKHealthStore,
        enabled: Bool
    ) {
        reset()
        guard enabled else { return }

        if let seriesBuilder = workoutBuilder.seriesBuilder(for: HKSeriesType.workoutRoute()) as? HKWorkoutRouteBuilder {
            routeBuilder = seriesBuilder
            usesLiveSeriesBuilder = true
            PulsarSyncDebugLogger.log("HealthKit route builder attached via live series builder")
            return
        }

        routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)
        usesLiveSeriesBuilder = false
        PulsarSyncDebugLogger.log("HealthKit route builder attached via standalone builder fallback")
    }

    func insert(_ locations: [CLLocation], sessionID: String) {
        guard !locations.isEmpty, let routeBuilder else { return }
        pendingInsertCount += 1
        // Retain the per-workout capture until HealthKit acknowledges the
        // insert so every pending waiter is resumed exactly once.
        routeBuilder.insertRouteData(locations) { [self] success, error in
            Task { @MainActor in
                if let error {
                    PulsarSyncDebugLogger.log("HealthKit route insert failed session=\(sessionID) error=\(error.localizedDescription)")
                } else if !success {
                    PulsarSyncDebugLogger.log("HealthKit route insert returned false session=\(sessionID)")
                }
                self.completeInsert()
            }
        }
    }

    /// Waits until every in-flight `insertRouteData` completion has fired.
    func waitForPendingInserts() async {
        guard pendingInsertCount > 0 else { return }
        await withCheckedContinuation { continuation in
            insertWaiters.append(continuation)
        }
    }

    /// Finalizes a standalone route builder. Live series builders are persisted by `finishWorkout()`.
    @discardableResult
    func finishStandaloneRouteIfNeeded(
        workout: HKWorkout?,
        metadata: [String: Any]?,
        sessionID: String,
        pointCount: Int
    ) async -> Bool {
        await waitForPendingInserts()
        guard let workout else { return false }
        guard !usesLiveSeriesBuilder else {
            PulsarSyncDebugLogger.log(
                "HealthKit route deferred to live workout finish session=\(sessionID) points=\(pointCount)"
            )
            return pointCount > 1
        }
        guard let routeBuilder else { return false }
        guard pointCount > 0 else { return false }

        do {
            _ = try await routeBuilder.finishRoute(with: workout, metadata: metadata)
            PulsarSyncDebugLogger.log("HealthKit standalone route saved session=\(sessionID) points=\(pointCount)")
            return true
        } catch {
            PulsarSyncDebugLogger.log(
                "HealthKit standalone route save failed session=\(sessionID) error=\(error.localizedDescription)"
            )
            return false
        }
    }

    func reset() {
        routeBuilder = nil
        usesLiveSeriesBuilder = false
        pendingInsertCount = 0
        let waiters = insertWaiters
        insertWaiters = []
        waiters.forEach { $0.resume() }
    }

    private func completeInsert() {
        pendingInsertCount = max(0, pendingInsertCount - 1)
        guard pendingInsertCount == 0 else { return }
        let waiters = insertWaiters
        insertWaiters = []
        waiters.forEach { $0.resume() }
    }
}

enum PulsarWorkoutRouteMerge {
    /// Prefers the richer route when reconciling two representations of the same workout.
    nonisolated static func preferredRoute(
        _ first: [PulsarRunCoordinate],
        _ second: [PulsarRunCoordinate]
    ) -> [PulsarRunCoordinate] {
        if first.count > 1, second.count > 1 {
            return first.count >= second.count ? first : second
        }
        if first.count > 1 { return first }
        if second.count > 1 { return second }
        return first.isEmpty ? second : first
    }

    nonisolated static func preferredSplits(
        _ first: [PulsarRunSplit],
        _ second: [PulsarRunSplit]
    ) -> [PulsarRunSplit] {
        first.isEmpty ? second : first
    }

    nonisolated static func enrichSummary(
        _ summary: PulsarRunSummary,
        withFallbackRoute fallbackRoute: [PulsarRunCoordinate]
    ) -> PulsarRunSummary {
        var enriched = summary
        enriched.route = preferredRoute(summary.route, fallbackRoute)
        return enriched
    }
}
