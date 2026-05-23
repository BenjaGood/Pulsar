//
//  PulsarSyncPolicy.swift
//  Pulsar
//

import Foundation

struct PulsarSyncPolicyDecision: Equatable {
    var shouldSync: Bool
    var minimumInterval: TimeInterval
    var reason: String

    nonisolated init(shouldSync: Bool, minimumInterval: TimeInterval, reason: String) {
        self.shouldSync = shouldSync
        self.minimumInterval = minimumInterval
        self.reason = reason
    }
}

struct PulsarSyncPolicy: Equatable {
    var foregroundMinimumInterval: TimeInterval = 3 * 60
    var staleVisibleMetricMinimumInterval: TimeInterval = 2 * 60
    var healthKitAnchoredMinimumInterval: TimeInterval = 60
    var backgroundMinimumInterval: TimeInterval = 15 * 60
    var lowPowerModeMultiplier: Double = 2

    nonisolated init(
        foregroundMinimumInterval: TimeInterval = 3 * 60,
        staleVisibleMetricMinimumInterval: TimeInterval = 2 * 60,
        healthKitAnchoredMinimumInterval: TimeInterval = 60,
        backgroundMinimumInterval: TimeInterval = 15 * 60,
        lowPowerModeMultiplier: Double = 2
    ) {
        self.foregroundMinimumInterval = foregroundMinimumInterval
        self.staleVisibleMetricMinimumInterval = staleVisibleMetricMinimumInterval
        self.healthKitAnchoredMinimumInterval = healthKitAnchoredMinimumInterval
        self.backgroundMinimumInterval = backgroundMinimumInterval
        self.lowPowerModeMultiplier = lowPowerModeMultiplier
    }

    func decision(
        lastSuccessfulSyncAt: Date?,
        now: Date,
        reason: String,
        lowPowerModeEnabled: Bool,
        hasStaleVisibleMetrics: Bool
    ) -> PulsarSyncPolicyDecision {
        let interval = minimumInterval(
            reason: reason,
            lowPowerModeEnabled: lowPowerModeEnabled,
            hasStaleVisibleMetrics: hasStaleVisibleMetrics
        )
        guard interval > 0 else {
            return PulsarSyncPolicyDecision(shouldSync: true, minimumInterval: interval, reason: "manual")
        }
        guard let lastSuccessfulSyncAt else {
            return PulsarSyncPolicyDecision(shouldSync: true, minimumInterval: interval, reason: "noPreviousSync")
        }
        let elapsed = now.timeIntervalSince(lastSuccessfulSyncAt)
        return PulsarSyncPolicyDecision(
            shouldSync: elapsed >= interval,
            minimumInterval: interval,
            reason: elapsed >= interval ? "stale" : "recent"
        )
    }

    func minimumInterval(
        reason: String,
        lowPowerModeEnabled: Bool,
        hasStaleVisibleMetrics: Bool
    ) -> TimeInterval {
        let base: TimeInterval
        if reason == "manualRefresh" {
            base = 0
        } else if reason.hasPrefix("healthKitAnchoredUpdate") {
            base = healthKitAnchoredMinimumInterval
        } else if reason == "backgroundRefresh" {
            base = backgroundMinimumInterval
        } else if hasStaleVisibleMetrics {
            base = staleVisibleMetricMinimumInterval
        } else {
            base = foregroundMinimumInterval
        }
        guard lowPowerModeEnabled, base > 0 else { return base }
        return base * lowPowerModeMultiplier
    }
}
