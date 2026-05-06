//
//  ContentView.swift
//  Pulsar Watch App Watch App
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        WatchHomeView()
    }
}

struct WatchHomeView: View {
    @StateObject private var store = WatchHealthKitStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    if let syncBannerState = store.syncBannerState {
                        WatchSyncBanner(state: syncBannerState)
                    }

                    if store.snapshot.healthKitState == .notRequested {
                        connectCard
                    } else if store.snapshot.healthKitState == .unavailable || store.snapshot.healthKitState == .needsPermission {
                        healthIssueCard
                    }

                    if !store.isLoading,
                       let message = store.message,
                       store.snapshot.healthKitState == .connected {
                        WatchSyncBanner(state: .failure(message))
                    }

                    NavigationLink { RecoveryDetailWatchView(snapshot: store.snapshot) } label: {
                        WatchMetricCard(title: "Recovery", value: WatchFormatters.score(store.snapshot.recovery.score), subtitle: store.snapshot.recovery.label, symbol: "heart.text.square.fill", tint: .green)
                    }
                    .buttonStyle(.plain)

                    NavigationLink { StrainDetailWatchView(snapshot: store.snapshot) } label: {
                        WatchMetricCard(title: "Strain", value: WatchFormatters.score(store.snapshot.strain.score), subtitle: "\(WatchFormatters.minutes(store.snapshot.strain.workoutMinutes)) workout", symbol: "figure.run", tint: .orange)
                    }
                    .buttonStyle(.plain)

                    NavigationLink { SleepDetailWatchView(snapshot: store.snapshot) } label: {
                        WatchMetricCard(title: "Sleep", value: WatchFormatters.score(store.snapshot.sleep.score), subtitle: WatchFormatters.minutes(store.snapshot.sleep.totalSleepMinutes), symbol: "moon.zzz.fill", tint: .indigo)
                    }
                    .buttonStyle(.plain)

                    activitySection
                    heartSection

                    NavigationLink { HealthStatusWatchView(snapshot: store.snapshot, store: store) } label: {
                        WatchGlassCard {
                            HStack {
                                Label("Health Status", systemImage: "heart.circle.fill")
                                    .font(.caption.weight(.semibold))
                                Spacer()
                                Text(store.snapshot.healthKitState.label)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(store.snapshot.healthKitState.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
            .navigationTitle("Pulsar")
            .task {
                store.viewAppeared()
                await store.load()
            }
            .refreshable { await store.load() }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                Task { await store.load() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Today")
                .font(.title2.weight(.bold))
            Text(store.snapshot.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 2)
    }

    private var connectCard: some View {
        WatchGlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Apple Health", systemImage: "heart.text.square.fill")
                    .font(.headline)
                Text(store.message ?? "Connect Apple Health to view watch metrics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Connect") {
                    Task { await store.requestAuthorization() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var healthIssueCard: some View {
        WatchEmptyState(title: store.snapshot.healthKitState.label, message: store.message ?? "Manage permissions from the iPhone app or Apple Health.", symbol: "exclamationmark.triangle.fill")
    }

    private var activitySection: some View {
        NavigationLink { WorkoutSummaryWatchView(snapshot: store.snapshot) } label: {
            VStack(alignment: .leading, spacing: 6) {
                WatchSectionTitle(title: "Activity")
                HStack(spacing: 6) {
                    WatchStatPill(title: "Steps", value: WatchFormatters.steps(store.snapshot.activity.steps))
                    WatchStatPill(title: "Energy", value: WatchFormatters.calories(store.snapshot.activity.activeEnergy), unit: "cal")
                }
                WatchStatPill(title: "Workout", value: WatchFormatters.minutes(store.snapshot.strain.workoutMinutes))
            }
        }
        .buttonStyle(.plain)
    }

    private var heartSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            WatchSectionTitle(title: "Heart")
            HStack(spacing: 6) {
                WatchStatPill(title: "HR", value: WatchFormatters.bpm(store.snapshot.heart.latestHeartRate), unit: "bpm")
                WatchStatPill(title: "RHR", value: WatchFormatters.bpm(store.snapshot.heart.restingHeartRate), unit: "bpm")
            }
            HStack(spacing: 6) {
                WatchStatPill(title: "HRV", value: WatchFormatters.milliseconds(store.snapshot.heart.hrvSDNN), unit: "ms")
                WatchStatPill(title: "Resp", value: WatchFormatters.bpm(store.snapshot.heart.respiratoryRate), unit: "/m")
            }
        }
    }
}

private struct WatchSyncBanner: View {
    var state: WatchSyncBannerState
    @State private var shimmerOffset = -90.0
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(state.tint.opacity(0.16))
                    .frame(width: 22, height: 22)
                    .scaleEffect(pulse && state.isSyncing ? 1.08 : 1)
                if state.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(state.tint)
                } else {
                    Image(systemName: state.symbol)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(state.tint)
                        .scaleEffect(pulse ? 1.08 : 1)
                }
            }

            Text(state.message)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(.thinMaterial)
        )
        .background(
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [state.tint.opacity(0.18), Color.white.opacity(0.05), state.tint.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.24), lineWidth: 0.8)
        }
        .overlay {
            if state.isSyncing {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.28), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 70)
                    .offset(x: shimmerOffset)
                    .blendMode(.screen)
            }
        }
        .clipShape(Capsule(style: .continuous))
        .shadow(color: state.tint.opacity(0.14), radius: 10, y: 5)
        .transition(.scale(scale: 0.96).combined(with: .opacity))
        .onAppear {
            shimmerOffset = -90
            pulse = false
            if state.isSyncing {
                withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: false)) {
                    shimmerOffset = 90
                }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            } else if case .success = state {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.58)) {
                    pulse = true
                }
            }
        }
    }
}

private struct WatchHomePreview: View {
    var snapshot: WatchDailyHealthSnapshot

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                WatchMetricCard(title: "Recovery", value: WatchFormatters.score(snapshot.recovery.score), subtitle: snapshot.recovery.label, symbol: "heart.text.square.fill", tint: .green)
                WatchMetricCard(title: "Strain", value: WatchFormatters.score(snapshot.strain.score), subtitle: "\(WatchFormatters.minutes(snapshot.strain.workoutMinutes)) workout", symbol: "figure.run", tint: .orange)
                WatchMetricCard(title: "Sleep", value: WatchFormatters.score(snapshot.sleep.score), subtitle: WatchFormatters.minutes(snapshot.sleep.totalSleepMinutes), symbol: "moon.zzz.fill", tint: .indigo)
            }
            .padding(8)
        }
    }
}

struct WatchHomeView_Previews: PreviewProvider {
    static var previews: some View {
        WatchHomePreview(snapshot: WatchPreviewData.snapshot)
    }
}
