//
//  WatchDetailViews.swift
//  Pulsar Watch App Watch App
//

import SwiftUI

struct RecoveryDetailWatchView: View {
    var snapshot: WatchDailyHealthSnapshot

    var body: some View {
        WatchDetailContainer(title: "Recovery") {
            WatchMetricCard(title: "Recovery", value: WatchFormatters.score(snapshot.recovery.score), subtitle: snapshot.recovery.label, symbol: "heart.text.square.fill", tint: PulsarMetricRingTheme.tint(for: .recovery))
            WatchGlassCard {
                VStack(spacing: 8) {
                    WatchStatPill(title: "HRV", value: WatchFormatters.milliseconds(snapshot.recovery.hrv), unit: "ms")
                    WatchStatPill(title: "Resting HR", value: WatchFormatters.bpm(snapshot.recovery.restingHeartRate), unit: "bpm")
                    WatchStatPill(title: "Resp Rate", value: WatchFormatters.bpm(snapshot.recovery.respiratoryRate), unit: "/m")
                    WatchStatPill(title: "Sleep Perf", value: WatchFormatters.percent(snapshot.recovery.sleepPerformance))
                }
            }
            WatchEmptyState(title: "Synced Recovery", message: "Pulsar shows the latest valid recovery score available from Apple Watch or iPhone sync, while newer Health data continues refreshing in the background.", symbol: "arrow.triangle.2.circlepath")
            WatchEmptyState(title: "Insight", message: recoveryInsight, symbol: "sparkles")
        }
    }

    private var recoveryInsight: String {
        if snapshot.recovery.score == nil { return "Build more baseline data to unlock recovery insights." }
        if let hrv = snapshot.recovery.hrv, hrv < 45 { return "HRV is lower than your recent baseline." }
        return snapshot.recovery.label
    }
}

struct StrainDetailWatchView: View {
    var snapshot: WatchDailyHealthSnapshot

    var body: some View {
        WatchDetailContainer(title: "Strain") {
            WatchMetricCard(title: "Current Strain", value: WatchFormatters.score(snapshot.strain.score), subtitle: recommendedSubtitle, symbol: "figure.run", tint: PulsarMetricRingTheme.tint(for: .strain), targetRange: recommendedStrainTargetRange)
            WatchGlassCard {
                VStack(spacing: 8) {
                    WatchStatPill(title: "Target", value: recommendedStrainTargetRange?.displayText ?? "--")
                    WatchStatPill(title: "Active", value: "\(Int(snapshot.strain.activeStrain.rounded()))")
                    WatchStatPill(title: "Passive", value: "\(Int(snapshot.strain.passiveStrain.rounded()))")
                    WatchStatPill(title: "Workout", value: WatchFormatters.minutes(snapshot.strain.workoutMinutes))
                    WatchStatPill(title: "Energy", value: WatchFormatters.calories(snapshot.strain.activeEnergy), unit: "cal")
                    WatchStatPill(title: "Steps", value: WatchFormatters.steps(snapshot.strain.steps))
                }
            }
            if snapshot.strain.zoneMinutes.isEmpty {
                WatchEmptyState(title: "Zones Pending", message: "Heart-rate zone summaries will appear when enough workout heart-rate data is available.", symbol: "waveform.path.ecg")
            } else {
            WatchGlassCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Heart Zones")
                            .font(.headline)
                        ForEach(snapshot.strain.zoneMinutes) { zone in
                            WatchStatPill(title: "Zone \(zone.zone)", value: WatchFormatters.minutes(zone.minutes))
                        }
                    }
                }
            }
            if let workout = snapshot.strain.lastWorkout {
                LastWorkoutCard(workout: workout)
            } else {
                WatchEmptyState(title: "No Workout Recorded", message: "Today’s strain still includes steps and active energy when available.", symbol: "figure.walk")
            }
            WatchEmptyState(title: "Insight", message: strainInsight, symbol: "sparkles")
        }
    }

    private var strainInsight: String {
        PulsarSharedMetricCalculator.strainGuidance(
            currentStrain: snapshot.strain.score,
            targetRange: recommendedStrainTargetRange,
            recoveryScore: snapshot.recovery.score,
            activeStrain: snapshot.strain.activeStrain,
            passiveStrain: snapshot.strain.passiveStrain,
            workoutMinutes: snapshot.strain.workoutMinutes,
            exerciseMinutes: snapshot.activity.workoutMinutes,
            steps: Int(snapshot.strain.steps.rounded()),
            isEarlyDay: Calendar.current.isDateInToday(snapshot.date) && Calendar.current.component(.hour, from: Date()) < 11
        )
    }

    private var recommendedStrainTargetRange: PulsarSharedStrainTargetRange? {
        PulsarSharedMetricCalculator.recommendedStrainTargetRange(forRecoveryScore: snapshot.recovery.score)
    }

    private var recommendedSubtitle: String {
        recommendedStrainTargetRange.map { "Target \($0.displayText)" } ?? "Today's load"
    }
}

struct SleepDetailWatchView: View {
    var snapshot: WatchDailyHealthSnapshot

    var body: some View {
        WatchDetailContainer(title: "Sleep") {
            WatchMetricCard(title: "Sleep", value: WatchFormatters.score(snapshot.sleep.score), subtitle: WatchFormatters.minutes(snapshot.sleep.totalSleepMinutes), symbol: "moon.zzz.fill", tint: PulsarMetricRingTheme.tint(for: .sleep))
            WatchGlassCard {
                VStack(spacing: 8) {
                    WatchStatPill(title: "Total", value: WatchFormatters.minutes(snapshot.sleep.totalSleepMinutes))
                    WatchStatPill(title: "Efficiency", value: WatchFormatters.percent(snapshot.sleep.efficiency))
                    WatchStatPill(title: "Consistency", value: WatchFormatters.percent(snapshot.sleep.consistency))
                }
            }
            WatchGlassCard {
                VStack(spacing: 8) {
                    WatchStatPill(title: "Awake", value: WatchFormatters.minutes(snapshot.sleep.awakeMinutes))
                    WatchStatPill(title: "REM", value: WatchFormatters.minutes(snapshot.sleep.remMinutes))
                    WatchStatPill(title: "Core", value: WatchFormatters.minutes(snapshot.sleep.coreMinutes))
                    WatchStatPill(title: "Deep", value: WatchFormatters.minutes(snapshot.sleep.deepMinutes))
                    WatchStatPill(title: "Asleep", value: WatchFormatters.minutes(snapshot.sleep.asleepUnspecifiedMinutes))
                }
            }
            if snapshot.alarm.syncedAt != nil {
                WatchGlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(snapshot.alarm.isEnabled ? "Alarm On" : "Alarm Off", systemImage: "alarm.fill")
                                .font(.headline)
                            Spacer()
                            if snapshot.alarm.isEnabled {
                                Text(WatchFormatters.clockTime(snapshot.alarm.timeMinutesFromMidnight))
                                    .font(.caption.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(.orange)
                            }
                        }
                        WatchStatPill(title: "Time", value: snapshot.alarm.isEnabled ? WatchFormatters.clockTime(snapshot.alarm.timeMinutesFromMidnight) : "--")
                        WatchStatPill(title: "Haptics", value: snapshot.alarm.hapticsEnabled ? "On" : "Off")
                        if let days = snapshot.alarm.sleepGoalDaysLabel {
                            WatchStatPill(title: "Days", value: days)
                        }
                    }
                }
            } else {
                WatchEmptyState(title: "Alarm", message: "Open Sleep Preferences on iPhone to sync your Pulsar sleep alarm to Apple Watch.", symbol: "alarm.fill")
            }
            WatchEmptyState(title: "Source", message: snapshot.sleep.sourceName ?? "Wear Apple Watch to sleep or connect a compatible sleep source to Apple Health.", symbol: "applewatch")
            WatchEmptyState(title: "Insight", message: sleepInsight, symbol: "sparkles")
        }
    }

    private var sleepInsight: String {
        if snapshot.sleep.score == nil { return "No sleep data yet." }
        if let efficiency = snapshot.sleep.efficiency, efficiency < 0.82 { return "Sleep efficiency was lower than usual." }
        return "Sleep duration and continuity are supporting today’s score."
    }
}

struct StressDetailWatchView: View {
    var snapshot: WatchDailyHealthSnapshot

    private var stress: WatchStressSummary { snapshot.stress }
    private var tint: Color { WatchStressPalette.tint(for: stress.score) }

    var body: some View {
        WatchDetailContainer(title: "Stress") {
            WatchGlassCard {
                VStack(alignment: .center, spacing: 10) {
                    WatchStressHaloGaugeView(stress: stress, size: 112)
                    Text(stress.level)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(tint)
                    Text(WatchFormatters.confidence(stress.confidence))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.08), in: Capsule())
                }
                .frame(maxWidth: .infinity)
            }

            WatchGlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Today")
                        .font(.headline)
                    WatchMiniStressTimelineView(samples: stress.timelineSamples, tint: tint)
                        .frame(height: 58)
                    Text("Estimated from available wearable signals. Not a medical diagnosis.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            WatchGlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Key Drivers")
                        .font(.headline)
                    ForEach(driverRows, id: \.self) { driver in
                        Label(driver, systemImage: "waveform.path.ecg")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            WatchGlassCard {
                VStack(spacing: 8) {
                    WatchStatPill(title: "HRV", value: WatchFormatters.milliseconds(stress.hrv), unit: "ms")
                    WatchStatPill(title: "Heart Rate", value: WatchFormatters.bpm(stress.recentHeartRate ?? snapshot.heart.latestHeartRate), unit: "bpm")
                    WatchStatPill(title: "Non-Activity", value: watchStressScore(stress.nonActivityStress))
                    WatchStatPill(title: "Adjusted", value: watchStressScore(stress.activityAdjustedStress))
                    WatchStatPill(title: "State", value: stress.movementState ?? stress.calculationState.displayText)
                    WatchStatPill(title: "Resting HR", value: WatchFormatters.bpm(stress.restingHeartRate ?? snapshot.heart.restingHeartRate), unit: "bpm")
                    WatchStatPill(title: "Respiration", value: WatchFormatters.bpm(stress.respiratoryRate ?? snapshot.heart.respiratoryRate), unit: "/m")
                    WatchStatPill(title: "Confidence", value: WatchFormatters.confidence(stress.confidence))
                }
            }

            WatchEmptyState(
                title: "About Stress",
                message: "Stress is a wellness estimate of physiological load. Exercise, sleep, caffeine, illness, heat, and emotional stress can all influence it.",
                symbol: "info.circle.fill"
            )
        }
    }

    private var driverRows: [String] {
        let rows = stress.driverInsights.filter { !$0.isEmpty }
        if !rows.isEmpty { return Array(rows.prefix(3)) }
        if stress.score == nil { return ["Stress confidence improves with more signals"] }
        return ["Your physiology looks close to baseline"]
    }

    private func watchStressScore(_ value: Double?) -> String {
        guard let value else { return stress.isPaused ? "Paused" : "--" }
        return "\(PulsarStressScale.roundedScore(value))"
    }
}

struct WorkoutSummaryWatchView: View {
    var snapshot: WatchDailyHealthSnapshot

    var body: some View {
        WatchDetailContainer(title: "Workouts") {
            if snapshot.workouts.isEmpty {
                WatchEmptyState(title: "No Workouts Yet", message: "Today’s workouts will appear here when Apple Health has compatible workout data.", symbol: "figure.run.circle")
            } else {
                ForEach(snapshot.workouts) { workout in
                    LastWorkoutCard(workout: workout)
                }
            }
        }
    }
}

struct HealthStatusWatchView: View {
    var snapshot: WatchDailyHealthSnapshot
    @ObservedObject var store: WatchHealthKitStore

    var body: some View {
        WatchDetailContainer(title: "Health") {
            WatchGlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("HealthKit")
                            .font(.headline)
                        Spacer()
                        Text(snapshot.healthKitState.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(snapshot.healthKitState.tint)
                    }
                    Text("Data source: \(sourceLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if snapshot.healthKitState == .notRequested {
                        Button("Connect") { Task { await store.requestAuthorization() } }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            WatchEmptyState(title: "Manage Permissions", message: "Manage permissions from the iPhone app or Apple Health. Pulsar reads compatible data and does not write Health data from this watch app yet.", symbol: "lock.shield.fill")
            WatchEmptyState(title: "Sync Status", message: "Today’s scores are shared between Apple Watch and iPhone. Pulsar keeps the newest valid synced values and ignores older or empty updates.", symbol: "sparkles")
        }
    }

    private var sourceLabel: String {
        if snapshot.detectedSources.isEmpty { return "HealthKit Auto" }
        return snapshot.detectedSources.prefix(2).joined(separator: ", ")
    }
}

private struct LastWorkoutCard: View {
    var workout: WatchWorkoutSummary

    var body: some View {
        WatchGlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(workout.type)
                        .font(.headline)
                    Spacer()
                    Text(workout.start.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                WatchStatPill(title: "Duration", value: WatchFormatters.minutes(workout.durationMinutes))
                WatchStatPill(title: "Active Cal", value: WatchFormatters.calories(workout.activeEnergy ?? 0), unit: "cal")
                WatchStatPill(title: "Avg HR", value: WatchFormatters.bpm(workout.averageHeartRate), unit: "bpm")
                if let source = workout.sourceName {
                    Text(source)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct WatchDetailContainer<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .navigationTitle(title)
    }
}

#if DEBUG
struct RecoveryDetailWatchView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { RecoveryDetailWatchView(snapshot: WatchPreviewData.snapshot) }
    }
}

struct StressDetailWatchView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { StressDetailWatchView(snapshot: WatchPreviewData.snapshot) }
    }
}

struct StrainDetailWatchView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { StrainDetailWatchView(snapshot: WatchPreviewData.snapshot) }
    }
}

struct SleepDetailWatchView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { SleepDetailWatchView(snapshot: WatchPreviewData.snapshot) }
    }
}

struct WorkoutSummaryWatchView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { WorkoutSummaryWatchView(snapshot: WatchPreviewData.snapshot) }
    }
}

struct HealthStatusWatchView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { HealthStatusWatchView(snapshot: WatchPreviewData.snapshot, store: WatchHealthKitStore()) }
    }
}
#endif
