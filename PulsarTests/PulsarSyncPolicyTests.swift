//
//  PulsarSyncPolicyTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

struct PulsarSyncPolicyTests {
    @Test func foregroundSyncIntervalAllowsThreeMinuteRefresh() {
        let policy = PulsarSyncPolicy()
        let now = Date(timeIntervalSinceReferenceDate: 10_000)

        let recent = policy.decision(
            lastSuccessfulSyncAt: now.addingTimeInterval(-90),
            now: now,
            reason: "appBecameActive",
            lowPowerModeEnabled: false,
            hasStaleVisibleMetrics: false
        )
        let stale = policy.decision(
            lastSuccessfulSyncAt: now.addingTimeInterval(-181),
            now: now,
            reason: "appBecameActive",
            lowPowerModeEnabled: false,
            hasStaleVisibleMetrics: false
        )

        #expect(recent.shouldSync == false)
        #expect(recent.minimumInterval == 180)
        #expect(stale.shouldSync == true)
    }

    @Test func manualSyncBypassesAutomaticInterval() {
        let policy = PulsarSyncPolicy()
        let now = Date(timeIntervalSinceReferenceDate: 10_000)

        let decision = policy.decision(
            lastSuccessfulSyncAt: now,
            now: now,
            reason: "manualRefresh",
            lowPowerModeEnabled: false,
            hasStaleVisibleMetrics: false
        )

        #expect(decision.shouldSync == true)
        #expect(decision.minimumInterval == 0)
    }

    @Test func lowPowerModeReducesForegroundFrequency() {
        let policy = PulsarSyncPolicy()

        #expect(policy.minimumInterval(reason: "appBecameActive", lowPowerModeEnabled: true, hasStaleVisibleMetrics: false) == 360)
        #expect(policy.minimumInterval(reason: "healthKitAnchoredUpdate:heartRate", lowPowerModeEnabled: true, hasStaleVisibleMetrics: false) == 120)
    }

    @Test func healthKitMetricLabelsSupportAnchoredUpdates() {
        #expect(PulsarHealthKitIncrementalMetric.label(forIdentifier: "HKQuantityTypeIdentifierHeartRate") == "heartRate")
        #expect(PulsarHealthKitIncrementalMetric.label(forIdentifier: "HKQuantityTypeIdentifierStepCount") == "steps")
        #expect(PulsarHealthKitIncrementalMetric.label(forIdentifier: "HKCategoryTypeIdentifierSleepAnalysis") == "sleep")
    }

    @Test func timelineUpsertDoesNotDuplicateRepeatedSyncRecords() {
        let store = UnifiedHealthTimelineStore()
        let now = Date(timeIntervalSinceReferenceDate: 12_000)
        let record = HealthMetricRecord(
            id: "oura-steps-\(Int(now.timeIntervalSinceReferenceDate))",
            metricType: .activity,
            value: 1_200,
            unit: "steps",
            startDate: now,
            endDate: now.addingTimeInterval(60),
            sourceProvider: .ouraRing,
            sourceDeviceName: "Oura Ring",
            category: .activitySteps,
            ingestedAt: now,
            externalIdentifier: "oura-activity-day",
            originalPayloadIdentifier: "oura-payload",
            confidence: .high,
            freshnessPolicy: .daily
        )

        store.upsert([record])
        store.upsert([record])

        #expect(store.records(category: .activitySteps, source: .ouraRing).count == 1)
    }
}
