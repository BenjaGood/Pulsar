import Foundation
import HealthKit

@MainActor
final class HealthEventMonitor {
    private let healthKit: HealthKitGateway
    private let sleepDataService: SleepSummaryProviding
    private let notificationManager: IntelligentNotificationManager
    private let calendar: Calendar

    init(
        healthKit: HealthKitGateway,
        sleepDataService: SleepSummaryProviding,
        notificationManager: IntelligentNotificationManager? = nil,
        calendar: Calendar = .current
    ) {
        self.healthKit = healthKit
        self.sleepDataService = sleepDataService
        self.notificationManager = notificationManager ?? .shared
        self.calendar = calendar
    }

    func processForegroundSnapshot(profile: UserProfile, dashboard: HomeDashboard, now: Date = Date()) async {
        await notificationManager.evaluateDashboard(profile: profile, dashboard: dashboard, now: now)
        await processRecentWorkouts(dashboard: dashboard, now: now)
    }

    func processObservedChange(
        sampleType: HKSampleType,
        profile: UserProfile,
        dashboard: HomeDashboard,
        now: Date = Date()
    ) async {
        if isWorkoutType(sampleType) {
            await processRecentWorkouts(dashboard: dashboard, now: now)
        }

        if isSleepType(sampleType) {
            await processLatestSleepSummary(profile: profile, dashboard: dashboard, now: now)
        }

        if isStressRelevantType(sampleType) {
            await notificationManager.evaluateHighStress(profile: profile, stress: dashboard.stress, now: now)
        }
    }

    private func processRecentWorkouts(dashboard: HomeDashboard, now: Date) async {
        let start = calendar.date(byAdding: .hour, value: -12, to: now) ?? now.addingTimeInterval(-12 * 60 * 60)
        let events = await healthKit.fetchWorkoutNotificationEvents(start: start, end: now.addingTimeInterval(60))
        for event in events.sorted(by: { $0.endDate < $1.endDate }) {
            await notificationManager.handleCompletedWorkout(event, dashboard: dashboard, now: now)
        }
    }

    private func processLatestSleepSummary(profile: UserProfile, dashboard: HomeDashboard, now: Date) async {
        guard let summary = try? await sleepDataService.sleepSummary(
            profile: profile,
            wakeUpDate: now,
            calendar: calendar,
            refreshedAt: now
        ) else {
            return
        }
        await notificationManager.evaluateSleepSummary(sleep: summary, recovery: dashboard.recovery, now: now)
    }

    private func isWorkoutType(_ type: HKSampleType) -> Bool {
        type.identifier == HKObjectType.workoutType().identifier
    }

    private func isSleepType(_ type: HKSampleType) -> Bool {
        type.identifier == HKObjectType.categoryType(forIdentifier: .sleepAnalysis)?.identifier
    }

    private func isStressRelevantType(_ type: HKSampleType) -> Bool {
        let identifiers: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .heartRateVariabilitySDNN,
            .restingHeartRate,
            .respiratoryRate,
            .appleSleepingWristTemperature,
            .activeEnergyBurned
        ]
        return identifiers
            .compactMap { HKObjectType.quantityType(forIdentifier: $0)?.identifier }
            .contains(type.identifier)
    }
}
