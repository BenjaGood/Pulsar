//
//  HealthSourceSelectorTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

struct HealthSourceSelectorTests {
    @Test func automaticModeKeepsAppleWatchWhenFresh() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let selector = ActiveSourceSelector()
        let source = selector.activeSource(
            for: .heartRate,
            mode: .automatic,
            snapshots: [
                snapshot(.appleWatch, metrics: [.heartRate], lastSyncAt: now.addingTimeInterval(-60)),
                snapshot(.ouraRing, metrics: [.heartRate], lastSyncAt: now)
            ],
            now: now
        )

        #expect(source == .appleWatch)
    }

    @Test func automaticModeFallsBackToOuraWhenAppleWatchIsStale() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let selector = ActiveSourceSelector()
        let source = selector.activeSource(
            for: .heartRate,
            mode: .automatic,
            snapshots: [
                snapshot(.appleWatch, metrics: [.heartRate], lastSyncAt: now.addingTimeInterval(-4 * 60 * 60)),
                snapshot(.ouraRing, metrics: [.heartRate], lastSyncAt: now.addingTimeInterval(-10 * 60))
            ],
            now: now
        )

        #expect(source == .ouraRing)
    }

    @Test func setupRequiredOuraFallsBackToFreshAppleWatch() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let selector = ActiveSourceSelector()
        let source = selector.activeSource(
            for: .sleep,
            mode: .automatic,
            snapshots: [
                snapshot(.appleWatch, metrics: [.sleep], lastSyncAt: now.addingTimeInterval(-10 * 60)),
                snapshot(.ouraRing, connectionState: .setupRequired, metrics: [.sleep], lastSyncAt: now)
            ],
            now: now
        )

        #expect(source == .appleWatch)
    }

    @Test func sourceRouterPrefersAppleActivityForLiveStrainAndKeepsOuraIndependentMetrics() {
        let now = Date(timeIntervalSinceReferenceDate: 100_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let defaults = ephemeralDefaults()
        let priorityStore = HealthSourcePriorityStore(defaults: defaults)
        priorityStore.setCurrentSource(.ouraRing, for: .activitySteps)
        priorityStore.setCurrentSource(.appleWatch, for: .workoutsActivity)
        priorityStore.setFallbackEnabled(false, for: .activitySteps)

        let apple = dashboard(
            payload: strainPayload(source: .iPhone, date: now, steps: 4_200, movementLoad: 11, workoutLoad: 44, workoutMinutes: 42, sourceName: "Apple Watch", calendar: calendar),
            date: now,
            calendar: calendar
        )
        let oura = dashboard(
            payload: strainPayload(source: .ouraRing, date: now, steps: 880, movementLoad: 8, workoutLoad: 0, workoutMinutes: 0, sourceName: "Oura Ring", calendar: calendar),
            date: now,
            calendar: calendar
        )

        let routed = HealthDataSourceRouter(priorityStore: priorityStore, calendar: calendar).routedDashboard(
            profile: .empty,
            date: now,
            generatedAt: now,
            sourceDashboards: [.appleWatch: apple, .ouraRing: oura],
            snapshots: [
                snapshot(.appleWatch, metrics: [.activity, .strain, .workouts], lastSyncAt: now),
                snapshot(.ouraRing, metrics: [.activity, .strain], lastSyncAt: now)
            ],
            now: now
        )

        #expect(routed.dashboard.strain.steps == 4_200)
        #expect(routed.dashboard.strain.movementLoad == 11)
        #expect(routed.dashboard.strain.workoutMinutes == 42)
        #expect(routed.dashboard.strain.workoutLoad == 44)
        #expect(routed.decisions[.activitySteps]?.displayedSource == .appleWatch)
        #expect(routed.decisions[.workoutsActivity]?.displayedSource == .appleWatch)
    }

    @Test func sourceRouterPrefersAppleLiveStressAndMergesOuraSupplementalHRV() {
        let now = Date(timeIntervalSinceReferenceDate: 105_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let defaults = ephemeralDefaults()
        let priorityStore = HealthSourcePriorityStore(defaults: defaults)
        priorityStore.setCurrentSource(.ouraRing, for: .stressResilience)
        priorityStore.setFallbackEnabled(true, for: .stressResilience)

        let apple = dashboard(
            payload: stressPayload(source: .iPhone, date: now, sourceName: "Apple Watch", calendar: calendar, score: 28, heartRate: 78),
            date: now,
            calendar: calendar
        )
        let oura = dashboard(
            payload: stressPayload(source: .ouraRing, date: now, sourceName: "Oura Ring", calendar: calendar, score: 35, hrv: 62),
            date: now,
            calendar: calendar
        )

        let routed = HealthDataSourceRouter(priorityStore: priorityStore, calendar: calendar).routedDashboard(
            profile: .empty,
            date: now,
            generatedAt: now,
            sourceDashboards: [.appleWatch: apple, .ouraRing: oura],
            snapshots: [
                snapshot(.appleWatch, metrics: [.heartRate, .stress], lastSyncAt: now),
                snapshot(.ouraRing, metrics: [.heartRate, .stress], lastSyncAt: now)
            ],
            now: now
        )

        #expect(routed.dashboard.stress.score == 28)
        #expect(routed.dashboard.stress.lastHeartRate == 78)
        #expect(routed.dashboard.stress.lastHRV == 62)
        #expect(routed.dashboard.stress.sourceBadges.map(\.displayName).contains("Apple Watch"))
        #expect(routed.dashboard.stress.sourceBadges.map(\.displayName).contains("Oura Ring"))
        #expect(routed.decisions[.stressResilience]?.currentSource == .ouraRing)
        #expect(routed.decisions[.stressResilience]?.displayedSource == .appleWatch)
    }

    @Test func sourceRouterDoesNotLetMissingHealthKitStressDisplaceOuraStress() {
        let now = Date(timeIntervalSinceReferenceDate: 106_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let defaults = ephemeralDefaults()
        let priorityStore = HealthSourcePriorityStore(defaults: defaults)
        priorityStore.setCurrentSource(.ouraRing, for: .stressResilience)
        priorityStore.setFallbackEnabled(true, for: .stressResilience)

        var appleMissingStress = StressSummary.missing
        appleMissingStress.date = now
        appleMissingStress.analyzedSampleCount = 28
        appleMissingStress.lastUpdated = now
        appleMissingStress.sourceBadges = [
            SourceProvenance(
                sourceName: "Apple Watch",
                sourceBundleIdentifier: "com.apple.health",
                sourceVersion: nil,
                operatingSystemVersion: nil,
                productType: nil,
                deviceName: "Apple Watch",
                deviceManufacturer: "Apple Inc.",
                deviceModel: "Apple Watch"
            )
        ]
        let apple = HomeDashboard(
            profile: .empty,
            sleep: .missing,
            recovery: .missing,
            strain: .missing,
            stress: appleMissingStress,
            healthMonitor: .missing(date: now),
            generatedAt: now,
            usingSampleData: false
        )
        let oura = dashboard(
            payload: stressPayload(source: .ouraRing, date: now, sourceName: "Oura Ring", calendar: calendar, score: 37, hrv: 89, heartRate: 94, restingHeartRate: 48),
            date: now,
            calendar: calendar
        )

        let routed = HealthDataSourceRouter(priorityStore: priorityStore, calendar: calendar).routedDashboard(
            profile: .empty,
            date: now,
            generatedAt: now,
            sourceDashboards: [.appleWatch: apple, .ouraRing: oura],
            snapshots: [
                snapshot(.appleWatch, metrics: [.heartRate, .stress], lastSyncAt: now),
                snapshot(.ouraRing, metrics: [.heartRate, .stress], lastSyncAt: now)
            ],
            now: now
        )

        #expect(routed.dashboard.stress.score == 37)
        #expect(routed.dashboard.stress.lastHeartRate == 94)
        #expect(routed.dashboard.stress.lastHRV == 89)
        #expect(routed.decisions[.stressResilience]?.displayedSource == .ouraRing)
        #expect(routed.decisions[.stressResilience]?.isFallback == false)
    }

    @Test func sourceRouterDoesNotSilentlyFallbackWhenFallbackIsDisabled() {
        let now = Date(timeIntervalSinceReferenceDate: 110_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let defaults = ephemeralDefaults()
        let priorityStore = HealthSourcePriorityStore(defaults: defaults)
        priorityStore.setCurrentSource(.ouraRing, for: .sleepRecovery)
        priorityStore.setFallbackEnabled(false, for: .sleepRecovery)
        let apple = dashboard(
            payload: sleepPayload(source: .iPhone, date: now, score: 82, sourceName: "Apple Watch", calendar: calendar),
            date: now,
            calendar: calendar
        )

        let routed = HealthDataSourceRouter(priorityStore: priorityStore, calendar: calendar).routedDashboard(
            profile: .empty,
            date: now,
            generatedAt: now,
            sourceDashboards: [.appleWatch: apple],
            snapshots: [
                snapshot(.appleWatch, metrics: [.sleep, .recovery], lastSyncAt: now),
                snapshot(.ouraRing, metrics: [.sleep, .recovery], lastSyncAt: nil)
            ],
            now: now
        )

        #expect(routed.dashboard.sleep.score == 0)
        #expect(routed.dashboard.sleep.sourceBadges.isEmpty)
        #expect(routed.decisions[.sleepRecovery]?.displayedSource == nil)
    }

    @Test func sourceRouterUsesFallbackOnlyWhenEnabled() {
        let now = Date(timeIntervalSinceReferenceDate: 120_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let defaults = ephemeralDefaults()
        let priorityStore = HealthSourcePriorityStore(defaults: defaults)
        priorityStore.setCurrentSource(.ouraRing, for: .sleepRecovery)
        priorityStore.setFallbackEnabled(true, for: .sleepRecovery)
        let apple = dashboard(
            payload: sleepPayload(source: .iPhone, date: now, score: 79, sourceName: "Apple Watch", calendar: calendar),
            date: now,
            calendar: calendar
        )

        let routed = HealthDataSourceRouter(priorityStore: priorityStore, calendar: calendar).routedDashboard(
            profile: .empty,
            date: now,
            generatedAt: now,
            sourceDashboards: [.appleWatch: apple],
            snapshots: [
                snapshot(.appleWatch, metrics: [.sleep, .recovery], lastSyncAt: now),
                snapshot(.ouraRing, metrics: [.sleep, .recovery], lastSyncAt: nil)
            ],
            now: now
        )

        #expect(routed.dashboard.sleep.score == 79)
        #expect(routed.decisions[.sleepRecovery]?.isFallback == true)
        #expect(routed.decisions[.sleepRecovery]?.displayedSource == .appleWatch)
    }

    @Test func sourceRouterFallsBackSleepIndependentlyWhenCurrentOuraHasOnlyRecovery() {
        let now = Date(timeIntervalSinceReferenceDate: 125_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let defaults = ephemeralDefaults()
        let priorityStore = HealthSourcePriorityStore(defaults: defaults)
        priorityStore.setCurrentSource(.ouraRing, for: .sleepRecovery)
        priorityStore.setFallbackEnabled(true, for: .sleepRecovery)

        let apple = dashboard(
            payload: sleepPayload(source: .iPhone, date: now, score: 82, sourceName: "Apple Watch", calendar: calendar),
            date: now,
            calendar: calendar
        )
        let ouraRecoveryOnly = dashboard(
            payload: strainPayload(source: .ouraRing, date: now, steps: 1_000, movementLoad: 5, workoutLoad: 0, workoutMinutes: 0, sourceName: "Oura Ring", calendar: calendar),
            date: now,
            calendar: calendar
        )

        let routed = HealthDataSourceRouter(priorityStore: priorityStore, calendar: calendar).routedDashboard(
            profile: .empty,
            date: now,
            generatedAt: now,
            sourceDashboards: [.appleWatch: apple, .ouraRing: ouraRecoveryOnly],
            snapshots: [
                snapshot(.appleWatch, metrics: [.sleep, .recovery], lastSyncAt: now),
                snapshot(.ouraRing, metrics: [.sleep, .recovery], lastSyncAt: now)
            ],
            now: now
        )

        #expect(routed.dashboard.sleep.score == 82)
        #expect(routed.dashboard.sleep.totalSleepMinutes == 450)
        #expect(routed.dashboard.sleep.sourceBadges.map(\.displayName).contains("Apple Watch"))
        #expect(routed.dashboard.recovery.score == 68)
        #expect(routed.dashboard.recovery.sourceBadges.map(\.displayName).contains("Oura Ring"))
    }

    @Test func metricResolverFallsBackWhenCurrentOuraHasNoRestingHeartRate() {
        let now = Date(timeIntervalSinceReferenceDate: 130_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let defaults = ephemeralDefaults()
        let priorityStore = HealthSourcePriorityStore(defaults: defaults)
        priorityStore.setCurrentSource(.ouraRing, for: .heartMetrics)
        priorityStore.setFallbackEnabled(true, for: .heartMetrics)

        let apple = dashboard(
            payload: healthMonitorPayload(source: .appleWatch, date: now, kind: .restingHeartRate, value: 54, sourceName: "Apple Watch", calendar: calendar),
            date: now,
            calendar: calendar
        )
        let oura = dashboard(
            payload: healthMonitorPayload(source: .ouraRing, date: now, kind: .hrv, value: 61, sourceName: "Oura Ring", calendar: calendar),
            date: now,
            calendar: calendar
        )

        let routed = HealthDataSourceRouter(priorityStore: priorityStore, calendar: calendar).routedDashboard(
            profile: .empty,
            date: now,
            generatedAt: now,
            sourceDashboards: [.appleWatch: apple, .ouraRing: oura],
            snapshots: [
                snapshot(.appleWatch, metrics: [.restingHeartRate, .hrv], lastSyncAt: now),
                snapshot(.ouraRing, metrics: [.restingHeartRate, .hrv], lastSyncAt: now)
            ],
            now: now
        )

        let restingHeartRate = routed.dashboard.healthMonitor.metric(.restingHeartRate)
        #expect(restingHeartRate.value == 54)
        #expect(restingHeartRate.sourceBadges.map(\.displayName).contains("Apple Watch"))
        #expect(restingHeartRate.sourceResolution?.currentSource == .ouraRing)
        #expect(restingHeartRate.sourceResolution?.displayedRecordSource == .appleWatch)
        #expect(restingHeartRate.sourceResolution?.fallbackUsed == true)
        #expect(restingHeartRate.sourceResolution?.sourceAvailabilityByProvider.first(where: { $0.source == .ouraRing })?.sampleCount == 0)
        #expect(routed.decisions[.heartMetrics]?.displayedSource == .appleWatch)
    }

    @Test func metricResolverDoesNotMarkConnectedOuraActiveWhenMetricUnavailable() {
        let now = Date(timeIntervalSinceReferenceDate: 140_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let defaults = ephemeralDefaults()
        let priorityStore = HealthSourcePriorityStore(defaults: defaults)
        priorityStore.setCurrentSource(.ouraRing, for: .heartMetrics)
        priorityStore.setFallbackEnabled(false, for: .heartMetrics)

        let oura = dashboard(
            payload: healthMonitorPayload(source: .ouraRing, date: now, kind: .hrv, value: 61, sourceName: "Oura Ring", calendar: calendar),
            date: now,
            calendar: calendar
        )

        let routed = HealthDataSourceRouter(priorityStore: priorityStore, calendar: calendar).routedDashboard(
            profile: .empty,
            date: now,
            generatedAt: now,
            sourceDashboards: [.ouraRing: oura],
            snapshots: [
                snapshot(.ouraRing, metrics: [.restingHeartRate, .hrv], lastSyncAt: now)
            ],
            now: now
        )

        let restingHeartRate = routed.dashboard.healthMonitor.metric(.restingHeartRate)
        #expect(restingHeartRate.value == nil)
        #expect(restingHeartRate.sourceResolution?.currentSource == .ouraRing)
        #expect(restingHeartRate.sourceResolution?.displayedRecordSource == nil)
        #expect(restingHeartRate.sourceResolution?.fallbackUsed == false)
        #expect(routed.decisions[.heartMetrics]?.displayedSource == nil)
    }

    @Test func metricResolverUsesCurrentOuraWhenExactMetricExists() {
        let now = Date(timeIntervalSinceReferenceDate: 150_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let defaults = ephemeralDefaults()
        let priorityStore = HealthSourcePriorityStore(defaults: defaults)
        priorityStore.setCurrentSource(.ouraRing, for: .heartMetrics)
        priorityStore.setFallbackEnabled(true, for: .heartMetrics)

        let apple = dashboard(
            payload: healthMonitorPayload(source: .appleWatch, date: now, kind: .restingHeartRate, value: 54, sourceName: "Apple Watch", calendar: calendar),
            date: now,
            calendar: calendar
        )
        let oura = dashboard(
            payload: healthMonitorPayload(source: .ouraRing, date: now, kind: .restingHeartRate, value: 58, sourceName: "Oura Ring", calendar: calendar),
            date: now,
            calendar: calendar
        )

        let routed = HealthDataSourceRouter(priorityStore: priorityStore, calendar: calendar).routedDashboard(
            profile: .empty,
            date: now,
            generatedAt: now,
            sourceDashboards: [.appleWatch: apple, .ouraRing: oura],
            snapshots: [
                snapshot(.appleWatch, metrics: [.restingHeartRate], lastSyncAt: now),
                snapshot(.ouraRing, metrics: [.restingHeartRate], lastSyncAt: now)
            ],
            now: now
        )

        let restingHeartRate = routed.dashboard.healthMonitor.metric(.restingHeartRate)
        #expect(restingHeartRate.value == 58)
        #expect(restingHeartRate.sourceBadges.map(\.displayName).contains("Oura Ring"))
        #expect(restingHeartRate.sourceResolution?.currentSource == .ouraRing)
        #expect(restingHeartRate.sourceResolution?.displayedRecordSource == .ouraRing)
        #expect(restingHeartRate.sourceResolution?.fallbackUsed == false)
    }

    @Test func currentOuraWithFallbackOffDoesNotDisplayAppleWatchRestingHeartRate() {
        let now = Date(timeIntervalSinceReferenceDate: 160_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let defaults = ephemeralDefaults()
        let priorityStore = HealthSourcePriorityStore(defaults: defaults)
        priorityStore.setCurrentSource(.ouraRing, for: .heartMetrics)
        priorityStore.setFallbackEnabled(false, for: .heartMetrics)

        let apple = dashboard(
            payload: healthMonitorPayload(source: .appleWatch, date: now, kind: .restingHeartRate, value: 54, sourceName: "Apple Watch", calendar: calendar),
            date: now,
            calendar: calendar
        )

        let routed = HealthDataSourceRouter(priorityStore: priorityStore, calendar: calendar).routedDashboard(
            profile: .empty,
            date: now,
            generatedAt: now,
            sourceDashboards: [.appleWatch: apple],
            snapshots: [
                snapshot(.appleWatch, metrics: [.restingHeartRate], lastSyncAt: now),
                snapshot(.ouraRing, metrics: [.restingHeartRate], lastSyncAt: now)
            ],
            now: now
        )

        let restingHeartRate = routed.dashboard.healthMonitor.metric(.restingHeartRate)
        #expect(restingHeartRate.value == nil)
        #expect(restingHeartRate.sourceBadges.isEmpty)
        #expect(restingHeartRate.sourceResolution?.currentSource == .ouraRing)
        #expect(restingHeartRate.sourceResolution?.displayedRecordSource == nil)
        #expect(restingHeartRate.sourceResolution?.fallbackUsed == false)
    }

    @Test func currentAppleWatchWithFallbackOffDisplaysAppleWatchRestingHeartRate() {
        let now = Date(timeIntervalSinceReferenceDate: 170_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let defaults = ephemeralDefaults()
        let priorityStore = HealthSourcePriorityStore(defaults: defaults)
        priorityStore.setCurrentSource(.appleWatch, for: .heartMetrics)
        priorityStore.setFallbackEnabled(false, for: .heartMetrics)

        let apple = dashboard(
            payload: healthMonitorPayload(source: .appleWatch, date: now, kind: .restingHeartRate, value: 54, sourceName: "Apple Watch", calendar: calendar),
            date: now,
            calendar: calendar
        )

        let routed = HealthDataSourceRouter(priorityStore: priorityStore, calendar: calendar).routedDashboard(
            profile: .empty,
            date: now,
            generatedAt: now,
            sourceDashboards: [.appleWatch: apple],
            snapshots: [
                snapshot(.appleWatch, metrics: [.restingHeartRate], lastSyncAt: now)
            ],
            now: now
        )

        let restingHeartRate = routed.dashboard.healthMonitor.metric(.restingHeartRate)
        #expect(restingHeartRate.value == 54)
        #expect(restingHeartRate.sourceBadges.map(\.displayName).contains("Apple Watch"))
        #expect(restingHeartRate.sourceResolution?.currentSource == .appleWatch)
        #expect(restingHeartRate.sourceResolution?.displayedRecordSource == .appleWatch)
        #expect(restingHeartRate.sourceResolution?.fallbackUsed == false)
    }

    @Test func currentOuraTemperatureWithFallbackOffShowsOvernightRingMessage() {
        let now = Date(timeIntervalSinceReferenceDate: 175_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let defaults = ephemeralDefaults()
        let priorityStore = HealthSourcePriorityStore(defaults: defaults)
        priorityStore.setCurrentSource(.ouraRing, for: .temperatureCycle)
        priorityStore.setFallbackEnabled(false, for: .temperatureCycle)

        let apple = dashboard(
            payload: healthMonitorPayload(source: .appleWatch, date: now, kind: .wristTemperature, value: 0.2, sourceName: "Apple Watch", calendar: calendar),
            date: now,
            calendar: calendar
        )

        let routed = HealthDataSourceRouter(priorityStore: priorityStore, calendar: calendar).routedDashboard(
            profile: .empty,
            date: now,
            generatedAt: now,
            sourceDashboards: [.appleWatch: apple],
            snapshots: [
                snapshot(.appleWatch, metrics: [.temperature], lastSyncAt: now),
                snapshot(.ouraRing, metrics: [.temperature], lastSyncAt: now)
            ],
            now: now
        )

        let temperature = routed.dashboard.healthMonitor.metric(.wristTemperature)
        #expect(temperature.value == nil)
        #expect(temperature.title == "Temperature Trend")
        #expect(temperature.comparisonText == "No Oura temperature trend available yet. Wear your ring overnight.")
        #expect(temperature.sourceResolution?.currentSource == .ouraRing)
        #expect(temperature.sourceResolution?.displayedRecordSource == nil)
        #expect(temperature.sourceResolution?.fallbackUsed == false)
    }

    @Test func currentOuraTemperatureUsesAppleWatchOnlyWhenFallbackIsEnabled() {
        let now = Date(timeIntervalSinceReferenceDate: 176_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let defaults = ephemeralDefaults()
        let priorityStore = HealthSourcePriorityStore(defaults: defaults)
        priorityStore.setCurrentSource(.ouraRing, for: .temperatureCycle)
        priorityStore.setFallbackEnabled(true, for: .temperatureCycle)

        let apple = dashboard(
            payload: healthMonitorPayload(source: .appleWatch, date: now, kind: .wristTemperature, value: 0.2, sourceName: "Apple Watch", calendar: calendar),
            date: now,
            calendar: calendar
        )

        let routed = HealthDataSourceRouter(priorityStore: priorityStore, calendar: calendar).routedDashboard(
            profile: .empty,
            date: now,
            generatedAt: now,
            sourceDashboards: [.appleWatch: apple],
            snapshots: [
                snapshot(.appleWatch, metrics: [.temperature], lastSyncAt: now),
                snapshot(.ouraRing, metrics: [.temperature], lastSyncAt: now)
            ],
            now: now
        )

        let temperature = routed.dashboard.healthMonitor.metric(.wristTemperature)
        #expect(temperature.value == 0.2)
        #expect(temperature.detailValueText == "+0.2 °C vs baseline")
        #expect(temperature.sourceResolution?.currentSource == .ouraRing)
        #expect(temperature.sourceResolution?.displayedRecordSource == .appleWatch)
        #expect(temperature.sourceResolution?.fallbackUsed == true)
        #expect(temperature.sourceResolution?.fallbackReason == "No Oura temperature trend available yet. Wear your ring overnight.")
    }

    @Test func routerRejectsAppleWatchMetricStoredUnderOuraWithoutFallback() {
        let now = Date(timeIntervalSinceReferenceDate: 180_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let defaults = ephemeralDefaults()
        let priorityStore = HealthSourcePriorityStore(defaults: defaults)
        priorityStore.setCurrentSource(.ouraRing, for: .heartMetrics)
        priorityStore.setFallbackEnabled(false, for: .heartMetrics)

        let appleBadgedDashboard = dashboard(
            payload: healthMonitorPayload(source: .appleWatch, date: now, kind: .restingHeartRate, value: 54, sourceName: "Apple Watch", calendar: calendar),
            date: now,
            calendar: calendar
        )

        let routed = HealthDataSourceRouter(priorityStore: priorityStore, calendar: calendar).routedDashboard(
            profile: .empty,
            date: now,
            generatedAt: now,
            sourceDashboards: [.ouraRing: appleBadgedDashboard],
            snapshots: [
                snapshot(.ouraRing, metrics: [.restingHeartRate], lastSyncAt: now)
            ],
            now: now
        )

        let restingHeartRate = routed.dashboard.healthMonitor.metric(.restingHeartRate)
        #expect(restingHeartRate.value == nil)
        #expect(restingHeartRate.sourceResolution?.currentSource == .ouraRing)
        #expect(restingHeartRate.sourceResolution?.displayedRecordSource == nil)
        #expect(restingHeartRate.sourceResolution?.fallbackUsed == false)
    }

    @Test func sourcePayloadSanitizerDropsAppleWatchHealthMonitorFromOuraPayload() {
        let now = Date(timeIntervalSinceReferenceDate: 181_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let mixedPayload = mixedHealthMonitorPayload(
            source: .ouraRing,
            date: now,
            metrics: [
                (.hrv, 63, "Oura Ring"),
                (.restingHeartRate, 57, "Benjamín’s Apple Watch")
            ],
            calendar: calendar
        )

        let sanitized = mixedPayload.sanitizedForDeclaredSource()
        let metricKinds = sanitized.healthMonitor?.metrics.map(\.kind) ?? []

        #expect(sanitized.sourceDevice == .ouraRing)
        #expect(metricKinds == [.hrv])
        #expect(sanitized.healthMonitor?.metrics.first?.sourceNames == ["Oura Ring"])
        #expect(sanitized.resolvedDataFingerprint.contains("source=ouraRing"))
        #expect(sanitized.resolvedDataFingerprint.contains("fallback=false"))
        #expect(!sanitized.resolvedDataFingerprint.contains("Apple Watch"))
        #expect(!sanitized.resolvedDataFingerprint.contains("restingHeartRate"))
    }

    @Test func sourcePayloadSanitizerDropsSourceNeutralNoDataHealthMetricWithoutInvalidMix() {
        let now = Date(timeIntervalSinceReferenceDate: 181_500)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let healthMonitor = PulsarHealthMonitorSyncMetric(
            metrics: [
                PulsarHealthMetricSyncValue(
                    kind: .hrv,
                    value: 63,
                    status: .normal,
                    baselineValue: 61,
                    comparisonText: "From Oura overnight HRV.",
                    sourceNames: ["Oura Ring"]
                ),
                PulsarHealthMetricSyncValue(
                    kind: .wristTemperature,
                    value: nil,
                    status: .noData,
                    baselineValue: nil,
                    comparisonText: "No temperature trend available yet.",
                    sourceNames: []
                )
            ],
            baselineWindowDays: 14,
            sourceNames: ["Oura Ring"],
            computedAt: now
        )
        let payload = PulsarDailyMetricsSyncPayload(
            date: calendar.startOfDay(for: now),
            dateKey: PulsarDailyMetricsDateKey.dateKey(for: now, calendar: calendar),
            syncedAt: now,
            sourceDevice: .ouraRing,
            healthMonitor: healthMonitor,
            syncSessionID: UUID(),
            validityFlag: true
        )

        let sanitized = payload.sanitizedForDeclaredSource()
        let metricKinds = sanitized.healthMonitor?.metrics.map(\.kind) ?? []

        #expect(metricKinds == [.hrv])
        #expect(sanitized.healthMonitor?.metrics.first?.sourceNames == ["Oura Ring"])
        #expect(sanitized.resolvedDataFingerprint.contains("source=ouraRing"))
        #expect(!sanitized.resolvedDataFingerprint.contains("source=unknown"))
        #expect(!sanitized.resolvedDataFingerprint.contains("wristTemperature"))
    }

    @Test func mergingNewOuraPayloadDoesNotCarryForwardAppleWatchHealthMonitor() {
        let now = Date(timeIntervalSinceReferenceDate: 182_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let appleHealthMonitor = healthMonitorPayload(
            source: .appleWatch,
            date: now,
            kind: .restingHeartRate,
            value: 57,
            sourceName: "Benjamín’s Apple Watch",
            calendar: calendar
        )
        let newerOuraActivity = strainPayload(
            source: .ouraRing,
            date: now.addingTimeInterval(60),
            steps: 1_400,
            movementLoad: 12,
            workoutLoad: 0,
            workoutMinutes: 0,
            sourceName: "Oura Ring",
            calendar: calendar
        )

        let merged = appleHealthMonitor.merged(with: newerOuraActivity, calendar: calendar)

        #expect(merged.sourceDevice == .ouraRing)
        #expect(merged.strain?.sourceNames == ["Oura Ring"])
        #expect(merged.healthMonitor == nil)
        #expect(!merged.resolvedDataFingerprint.contains("Apple Watch"))
        #expect(!merged.resolvedDataFingerprint.contains("health-monitor"))
    }

    @Test func pureOuraHealthMonitorFingerprintCarriesPerMetricSourceMetadata() {
        let now = Date(timeIntervalSinceReferenceDate: 183_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let payload = healthMonitorPayload(
            source: .ouraRing,
            date: now,
            kind: .restingHeartRate,
            value: 58,
            sourceName: "Oura Ring",
            calendar: calendar
        )

        let fingerprint = payload.sanitizedForDeclaredSource().resolvedDataFingerprint

        #expect(fingerprint.contains("health-monitor"))
        #expect(fingerprint.contains("source=ouraRing"))
        #expect(fingerprint.contains("fallback=false"))
        #expect(!fingerprint.contains("source=appleWatchHealthKit:fallback=false"))
    }

    @Test func sameDayOuraPartialPayloadStaysSourceSpecificWhenAppleDailyCacheExists() {
        let now = Date(timeIntervalSinceReferenceDate: 183_500)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let appleDaily = strainPayload(
            source: .iPhone,
            date: now,
            steps: 4_200,
            movementLoad: 11,
            workoutLoad: 44,
            workoutMinutes: 42,
            sourceName: "Apple Watch",
            calendar: calendar
        )
        let ouraStressOnly = stressPayload(
            source: .ouraRing,
            date: now.addingTimeInterval(120),
            sourceName: "Oura Ring",
            calendar: calendar
        )
        let nextDayOuraStress = stressPayload(
            source: .ouraRing,
            date: now.addingTimeInterval(24 * 60 * 60),
            sourceName: "Oura Ring",
            calendar: calendar
        )

        #expect(!PulsarWatchConnectivitySyncStore.shouldPromotePayloadToGlobalCache(currentPayload: appleDaily, incomingPayload: ouraStressOnly))
        #expect(PulsarWatchConnectivitySyncStore.shouldPromotePayloadToGlobalCache(currentPayload: nil, incomingPayload: ouraStressOnly))
        #expect(PulsarWatchConnectivitySyncStore.shouldPromotePayloadToGlobalCache(currentPayload: appleDaily, incomingPayload: nextDayOuraStress))
    }

    @Test func syncPayloadKeepsValidStrainWhenRecoveryIsMissing() throws {
        let now = Date(timeIntervalSinceReferenceDate: 183_750)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let sourceDashboard = dashboard(
            payload: strainOnlyPayload(
                source: .iPhone,
                date: now,
                steps: 2_400,
                movementLoad: 9,
                workoutLoad: 0,
                workoutMinutes: 0,
                sourceName: "Apple Watch",
                calendar: calendar
            ),
            date: now,
            calendar: calendar
        )

        let payload = try #require(sourceDashboard.syncPayload(sourceDevice: .iPhone, calendar: calendar))

        #expect(payload.hasValidStrain)
        #expect(payload.recovery == nil)
        #expect(payload.strain?.steps == 2_400)
    }

    @Test func sourceCacheSanitizerDropsStaleAppleWatchSleepFromOuraBucket() {
        let now = Date(timeIntervalSinceReferenceDate: 184_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let staleMixedSleep = sleepPayload(
            source: .ouraRing,
            date: now,
            score: 87,
            sourceName: "Benjamín’s Apple Watch",
            calendar: calendar
        )
        let dateKey = staleMixedSleep.sleep?.sleepDateKey ?? staleMixedSleep.resolvedDateKey

        let sanitized = PulsarWatchConnectivitySyncStore.sanitizedSourcePayloadCache(
            [dateKey: [.ouraRing: staleMixedSleep]],
            isUsable: { $0.sleep?.isValid == true }
        )

        #expect(sanitized[dateKey]?[.ouraRing] == nil)
    }

    @Test func sourceUIStringsDistinguishPreferredAndActiveSources() throws {
        #expect(HealthSourceDisplayCopy.preferredSource == "Preferred source")
        #expect(HealthSourceDisplayCopy.activeSource == "Active source")
        #expect(HealthSourceDisplayCopy.preferredSourceTitle == "Preferred Source")
        #expect(HealthSourceDisplayCopy.activeSourceTitle == "Active Source")
    }

    private func snapshot(
        _ sourceID: HealthSourceID,
        connectionState: SourceConnectionState = .connected,
        metrics: Set<MeasurementHealthMetricType>,
        lastSyncAt: Date?
    ) -> HealthSourceSnapshot {
        HealthSourceSnapshot(
            sourceID: sourceID,
            connectionState: connectionState,
            syncState: .idle,
            supportedMetrics: metrics,
            lastSyncAt: lastSyncAt,
            batteryPercentage: nil
        )
    }

    private func dashboard(payload: PulsarDailyMetricsSyncPayload, date: Date, calendar: Calendar) -> HomeDashboard {
        HomeDashboard(
            profile: .empty,
            sleep: .missing,
            recovery: .missing,
            strain: .missing,
            stress: .missing,
            healthMonitor: .missing(date: date),
            generatedAt: date,
            usingSampleData: false
        )
        .applying(payload: payload, calendar: calendar)
    }

    private func strainPayload(
        source: PulsarSyncSourceDevice,
        date: Date,
        steps: Int,
        movementLoad: Double,
        workoutLoad: Double,
        workoutMinutes: Double,
        sourceName: String,
        calendar: Calendar
    ) -> PulsarDailyMetricsSyncPayload {
        let strain = PulsarStrainSyncMetric(
            score: ScoreMath.roundedScore((movementLoad + workoutLoad) / 120),
            confidence: .high,
            rawLoad: movementLoad + workoutLoad,
            workoutLoad: workoutLoad,
            movementLoad: movementLoad,
            steps: steps,
            activeEnergyKilocalories: movementLoad * 20,
            exerciseMinutes: max(workoutMinutes, movementLoad),
            workoutMinutes: workoutMinutes,
            averageActiveHeartRate: workoutMinutes > 0 ? 136 : nil,
            peakHeartRate: workoutMinutes > 0 ? 168 : nil,
            sourceNames: [sourceName],
            computedAt: date
        )
        let recovery = PulsarRecoverySyncMetric(
            score: 68,
            confidence: .moderate,
            statusText: "Moderate recovery",
            hrvSDNN: 58,
            hrvBaseline: 60,
            restingHeartRate: 55,
            restingHeartRateBaseline: 56,
            sleepDuration: 7 * 60 * 60,
            sleepEfficiency: 0.9,
            strainScore: Double(strain.score),
            respiratoryRate: 14,
            oxygenSaturation: 0.96,
            wristTemperatureDeviation: nil,
            hrvReadiness: 0.7,
            restingHeartRateReadiness: 0.7,
            respiratoryStability: 0.8,
            sleepContribution: 0.8,
            strainPenalty: 0.2,
            sourceNames: [sourceName],
            computedAt: date
        )
        return PulsarDailyMetricsSyncPayload(
            date: calendar.startOfDay(for: date),
            dateKey: PulsarDailyMetricsDateKey.dateKey(for: date, calendar: calendar),
            syncedAt: date,
            sourceDevice: source,
            strain: strain,
            recovery: recovery,
            syncSessionID: UUID(),
            validityFlag: true
        )
    }

    private func strainOnlyPayload(
        source: PulsarSyncSourceDevice,
        date: Date,
        steps: Int,
        movementLoad: Double,
        workoutLoad: Double,
        workoutMinutes: Double,
        sourceName: String,
        calendar: Calendar
    ) -> PulsarDailyMetricsSyncPayload {
        let strain = PulsarStrainSyncMetric(
            score: ScoreMath.roundedScore((movementLoad + workoutLoad) / 120),
            confidence: .moderate,
            rawLoad: movementLoad + workoutLoad,
            workoutLoad: workoutLoad,
            movementLoad: movementLoad,
            steps: steps,
            activeEnergyKilocalories: movementLoad * 20,
            exerciseMinutes: max(workoutMinutes, movementLoad),
            workoutMinutes: workoutMinutes,
            averageActiveHeartRate: nil,
            peakHeartRate: nil,
            sourceNames: [sourceName],
            computedAt: date
        )
        return PulsarDailyMetricsSyncPayload(
            date: calendar.startOfDay(for: date),
            dateKey: PulsarDailyMetricsDateKey.dateKey(for: date, calendar: calendar),
            syncedAt: date,
            sourceDevice: source,
            strain: strain,
            syncSessionID: UUID(),
            validityFlag: true
        )
    }

    private func sleepPayload(
        source: PulsarSyncSourceDevice,
        date: Date,
        score: Int,
        sourceName: String,
        calendar: Calendar
    ) -> PulsarDailyMetricsSyncPayload {
        let start = date.addingTimeInterval(-8 * 60 * 60)
        let end = date
        let sleep = PulsarSleepSyncMetric(
            score: score,
            confidence: .high,
            sleepDateKey: PulsarDailyMetricsDateKey.dateKey(for: date, calendar: calendar),
            wakeUpDate: calendar.startOfDay(for: date),
            sleepStart: start,
            sleepEnd: end,
            queryStart: start.addingTimeInterval(-60),
            queryEnd: end.addingTimeInterval(60),
            totalSleepMinutes: 450,
            timeInBedMinutes: 480,
            sleepEfficiency: 0.94,
            awakeMinutes: 30,
            wasoMinutes: 20,
            remMinutes: 110,
            coreMinutes: 260,
            deepMinutes: 80,
            asleepUnspecifiedMinutes: 0,
            awakenings: 2,
            analyzedSampleCount: 8,
            sleepConsistency: 0.8,
            sleepPerformance: 0.85,
            durationAdequacy: 0.9,
            regularity: 0.8,
            continuity: 0.8,
            targetSleepHours: 8,
            sourceNames: [sourceName],
            computedAt: date
        )
        return PulsarDailyMetricsSyncPayload(
            date: calendar.startOfDay(for: date),
            dateKey: PulsarDailyMetricsDateKey.dateKey(for: date, calendar: calendar),
            syncedAt: date,
            sourceDevice: source,
            sleep: sleep,
            syncSessionID: UUID(),
            validityFlag: true
        )
    }

    private func healthMonitorPayload(
        source: PulsarSyncSourceDevice,
        date: Date,
        kind: PulsarHealthMetricSyncKind,
        value: Double,
        sourceName: String,
        calendar: Calendar
    ) -> PulsarDailyMetricsSyncPayload {
        let healthMonitor = PulsarHealthMonitorSyncMetric(
            metrics: [
                PulsarHealthMetricSyncValue(
                    kind: kind,
                    value: value,
                    status: .normal,
                    baselineValue: value,
                    comparisonText: "Close to your recent baseline.",
                    sourceNames: [sourceName]
                )
            ],
            baselineWindowDays: 14,
            sourceNames: [sourceName],
            computedAt: date
        )
        return PulsarDailyMetricsSyncPayload(
            date: calendar.startOfDay(for: date),
            dateKey: PulsarDailyMetricsDateKey.dateKey(for: date, calendar: calendar),
            syncedAt: date,
            sourceDevice: source,
            healthMonitor: healthMonitor,
            syncSessionID: UUID(),
            validityFlag: true
        )
    }

    private func stressPayload(
        source: PulsarSyncSourceDevice,
        date: Date,
        sourceName: String,
        calendar: Calendar,
        score: Int = 35,
        hrv: Double? = nil,
        heartRate: Double? = nil,
        restingHeartRate: Double? = nil
    ) -> PulsarDailyMetricsSyncPayload {
        let stress = PulsarStressSyncMetric(
            score: score,
            confidence: .high,
            levelText: PulsarSharedMetricCalculator.stressLevelText(score: score),
            driverInsights: [],
            hrvSDNN: hrv,
            hrvTimestamp: hrv == nil ? nil : date,
            restingHeartRate: restingHeartRate,
            respiratoryRate: nil,
            recentHeartRate: heartRate,
            heartRateTimestamp: heartRate == nil ? nil : date,
            nonActivityStress: heartRate == nil ? nil : Double(score),
            activityAdjustedStress: heartRate == nil ? nil : Double(score),
            sleepDurationMinutes: nil,
            strainScore: nil,
            availableSignalCount: 1,
            baselineWindowDays: 0,
            timelineSamples: [PulsarStressSyncSample(timestamp: date, score: Double(score), context: "\(sourceName) daily stress")],
            sourceNames: [sourceName],
            computedAt: date
        )
        return PulsarDailyMetricsSyncPayload(
            date: calendar.startOfDay(for: date),
            dateKey: PulsarDailyMetricsDateKey.dateKey(for: date, calendar: calendar),
            syncedAt: date,
            sourceDevice: source,
            stress: stress,
            syncSessionID: UUID(),
            validityFlag: true
        )
    }

    private func mixedHealthMonitorPayload(
        source: PulsarSyncSourceDevice,
        date: Date,
        metrics: [(kind: PulsarHealthMetricSyncKind, value: Double, sourceName: String)],
        calendar: Calendar
    ) -> PulsarDailyMetricsSyncPayload {
        let healthMetrics = metrics.map { metric in
            PulsarHealthMetricSyncValue(
                kind: metric.kind,
                value: metric.value,
                status: .normal,
                baselineValue: metric.value,
                comparisonText: "Close to your recent baseline.",
                sourceNames: [metric.sourceName]
            )
        }
        let healthMonitor = PulsarHealthMonitorSyncMetric(
            metrics: healthMetrics,
            baselineWindowDays: 14,
            sourceNames: Array(Set(metrics.map { $0.sourceName })).sorted(),
            computedAt: date
        )
        return PulsarDailyMetricsSyncPayload(
            date: calendar.startOfDay(for: date),
            dateKey: PulsarDailyMetricsDateKey.dateKey(for: date, calendar: calendar),
            syncedAt: date,
            sourceDevice: source,
            healthMonitor: healthMonitor,
            syncSessionID: UUID(),
            validityFlag: true
        )
    }

    private func ephemeralDefaults() -> UserDefaults {
        let suiteName = "PulsarSourceRouterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
