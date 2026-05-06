//
//  WatchDetailViews.swift
//  Pulsar Watch App Watch App
//

import SwiftUI

struct RecoveryDetailWatchView: View {
    var snapshot: WatchDailyHealthSnapshot

    var body: some View {
        WatchDetailContainer(title: "Recovery") {
            WatchMetricCard(title: "Recovery", value: WatchFormatters.score(snapshot.recovery.score), subtitle: snapshot.recovery.label, symbol: "heart.text.square.fill", tint: .green)
            WatchGlassCard {
                VStack(spacing: 8) {
                    WatchStatPill(title: "HRV", value: WatchFormatters.milliseconds(snapshot.recovery.hrv), unit: "ms")
                    WatchStatPill(title: "Resting HR", value: WatchFormatters.bpm(snapshot.recovery.restingHeartRate), unit: "bpm")
                    WatchStatPill(title: "Resp Rate", value: WatchFormatters.bpm(snapshot.recovery.respiratoryRate), unit: "/m")
                    WatchStatPill(title: "Sleep Perf", value: WatchFormatters.percent(snapshot.recovery.sleepPerformance))
                }
            }
            WatchEmptyState(title: "Synced Recovery", message: "Pulsar shows the latest valid recovery score available from Apple Watch or iPhone sync, while newer Health data continues refreshing in the background.", symbol: "arrow.triangle.2.circlepath")
        }
    }
}

struct StrainDetailWatchView: View {
    var snapshot: WatchDailyHealthSnapshot

    var body: some View {
        WatchDetailContainer(title: "Strain") {
            WatchMetricCard(title: "Strain", value: WatchFormatters.score(snapshot.strain.score), subtitle: "Today’s load", symbol: "figure.run", tint: .orange)
            WatchGlassCard {
                VStack(spacing: 8) {
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
            }
        }
    }
}

struct SleepDetailWatchView: View {
    var snapshot: WatchDailyHealthSnapshot

    var body: some View {
        WatchDetailContainer(title: "Sleep") {
            WatchMetricCard(title: "Sleep", value: WatchFormatters.score(snapshot.sleep.score), subtitle: WatchFormatters.minutes(snapshot.sleep.totalSleepMinutes), symbol: "moon.zzz.fill", tint: .indigo)
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
            WatchEmptyState(title: "Source", message: snapshot.sleep.sourceName ?? "Wear Apple Watch to sleep or connect a compatible sleep source to Apple Health.", symbol: "applewatch")
        }
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

struct RecoveryDetailWatchView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { RecoveryDetailWatchView(snapshot: WatchPreviewData.snapshot) }
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
