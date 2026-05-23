//
//  ContentView.swift
//  Pulsar Watch App Watch App
//

import SwiftUI

struct ContentView: View {
    @State private var isShowingLaunch = true

    var body: some View {
        ZStack {
            WatchHomeView()
                .opacity(isShowingLaunch ? 0 : 1)
                .animation(.easeOut(duration: 0.28), value: isShowingLaunch)

            if isShowingLaunch {
                WatchLaunchAnimationView {
                    withAnimation(.easeInOut(duration: 0.24)) {
                        isShowingLaunch = false
                    }
                }
                .transition(.opacity)
                .zIndex(1)
                .allowsHitTesting(false)
            }
        }
    }
}

struct WatchHomeView: View {
    @StateObject private var store = WatchHealthKitStore()
    @StateObject private var syncStore = PulsarWatchConnectivitySyncStore.shared
    @EnvironmentObject private var runManager: WatchRunSessionManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var isShowingWorkoutPicker = false

    var body: some View {
        Group {
            if runManager.snapshot.phase.isWatchActiveWorkoutPhase {
                WatchLiveRunView()
                    .environmentObject(runManager)
                    .onAppear {
                        PulsarSyncDebugLogger.log("Watch active workout UI route opened session=\(runManager.snapshot.pulsarWorkoutSessionId?.uuidString ?? "none") type=\(runManager.snapshot.workoutKind.rawValue)")
                    }
            } else if let activeWorkoutState = syncStore.activeWorkoutState,
                      activeWorkoutState.phase.isLive,
                      syncStore.isRoutableActiveWorkoutState(activeWorkoutState),
                      activeWorkoutState.kind.outdoorWorkoutKind != nil {
                WatchLiveRunView()
                    .environmentObject(runManager)
                    .onAppear {
                        runManager.reconcileActiveWorkoutSyncState(activeWorkoutState)
                        PulsarSyncDebugLogger.log("Watch active workout UI route opened from sync state session=\(activeWorkoutState.sessionId.uuidString) type=\(activeWorkoutState.kind.workoutTypeRawValue)")
                    }
            } else if let activeGymState = syncStore.activeGymState,
                      syncStore.isRoutableActiveGymState(activeGymState) {
                WatchActiveGymWorkoutView(syncStore: syncStore, state: activeGymState)
            } else {
                homeContent
            }
        }
        .task {
            syncStore.pruneStaleActiveWorkoutState(reason: "watchHomeAppeared")
            syncStore.sendWatchHeartbeat(reason: "watchHomeAppeared")
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            syncStore.pruneStaleActiveWorkoutState(reason: "watchAppBecameActive")
            syncStore.sendWatchHeartbeat(reason: "watchAppBecameActive")
        }
        .onChange(of: syncStore.activeWorkoutState) { _, state in
            guard let state,
                  state.kind.outdoorWorkoutKind != nil,
                  state.phase.isLive,
                  syncStore.isRoutableActiveWorkoutState(state) else { return }
            runManager.reconcileActiveWorkoutSyncState(state)
        }
    }

    private var homeContent: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    if store.snapshot.alarm.isEnabled, store.snapshot.alarm.syncedAt != nil {
                        WatchAlarmPill(alarm: store.snapshot.alarm)
                    }

                    if store.snapshot.healthKitState == .notRequested {
                        connectCard
                    } else if store.snapshot.healthKitState == .unavailable || store.snapshot.healthKitState == .needsPermission {
                        healthIssueCard
                    }

                    topMetricRow

                    NavigationLink { StressDetailWatchView(snapshot: store.snapshot) } label: {
                        WatchStressCardView(stress: store.snapshot.stress)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 64)
            }
            .navigationTitle("")
            .overlay(alignment: .top) {
                if let syncBannerState = store.syncBannerState {
                    WatchSyncBanner(state: syncBannerState)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                        .allowsHitTesting(false)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                WatchWorkoutFloatingAddButton {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.76)) {
                        isShowingWorkoutPicker = true
                    }
                }
                .padding(.trailing, 9)
                .padding(.bottom, 8)
            }
            .animation(.smooth(duration: 0.24), value: store.syncBannerState)
            .sheet(isPresented: $isShowingWorkoutPicker) {
                WatchWorkoutPickerView()
                    .environmentObject(runManager)
            }
            .task {
                store.viewAppeared()
                await store.refreshForAppActivation()
            }
            .refreshable { await store.load(reason: "manualRefresh", showsBanner: true) }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                Task { await store.refreshForAppActivation() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Today")
                .font(.title2.weight(.bold))
            Text(store.snapshot.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 2)
    }

    private var topMetricRow: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = proxy.size.width < 170 ? 4 : 6
            let cardWidth = (proxy.size.width - spacing * 2) / 3
            let ringSize: CGFloat = min(46, max(36, cardWidth * 0.78))

            HStack(spacing: spacing) {
                NavigationLink { SleepDetailWatchView(snapshot: store.snapshot) } label: {
                    WatchMetricCardView(
                        title: "Sleep",
                        score: store.snapshot.sleep.score,
                        subtitle: "",
                        symbol: "moon.zzz.fill",
                        tint: PulsarMetricRingTheme.tint(for: .sleep),
                        ringSize: ringSize,
                        showsSubtitle: false
                    )
                    .frame(width: cardWidth)
                }
                .buttonStyle(.plain)

                NavigationLink { RecoveryDetailWatchView(snapshot: store.snapshot) } label: {
                    WatchMetricCardView(
                        title: "Recovery",
                        score: store.snapshot.recovery.score,
                        subtitle: "",
                        symbol: "heart.text.square.fill",
                        tint: PulsarMetricRingTheme.tint(for: .recovery),
                        ringSize: ringSize,
                        showsSubtitle: false
                    )
                    .frame(width: cardWidth)
                }
                .buttonStyle(.plain)

                NavigationLink { StrainDetailWatchView(snapshot: store.snapshot) } label: {
                    WatchMetricCardView(
                        title: "Strain",
                        score: store.snapshot.strain.score,
                        subtitle: "",
                        symbol: "figure.run",
                        tint: PulsarMetricRingTheme.tint(for: .strain),
                        ringSize: ringSize,
                        showsSubtitle: false,
                        targetRange: recommendedStrainTargetRange
                    )
                    .frame(width: cardWidth)
                }
                .buttonStyle(.plain)
            }
            .frame(width: proxy.size.width, alignment: .center)
        }
        .frame(height: 78)
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

    private var recommendedStrainTargetRange: PulsarSharedStrainTargetRange? {
        PulsarSharedMetricCalculator.recommendedStrainTargetRange(forRecoveryScore: store.snapshot.recovery.score)
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

private extension PulsarRunPhase {
    var isWatchActiveWorkoutPhase: Bool {
        switch self {
        case .running, .paused, .finishing, .connectingToWatch:
            true
        case .idle, .requestingPermissions, .countingDown, .finished, .failed:
            false
        }
    }
}

private struct WatchSyncBanner: View {
    var state: WatchSyncBannerState
    @State private var shimmerOffset = -90.0
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(state.tint.opacity(0.16))
                    .frame(width: 20, height: 20)
                    .scaleEffect(pulse && state.isSyncing ? 1.08 : 1)
                if state.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(state.tint)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: state.symbol)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(state.tint)
                        .scaleEffect(pulse ? 1.08 : 1)
                }
            }
            .frame(width: 22, height: 22)

            Text(compactMessage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
        }
        .frame(width: 116, height: 30)
        .fixedSize(horizontal: true, vertical: true)
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

    private var compactMessage: String {
        switch state {
        case .syncing(_):
            return "Syncing"
        case .success(_):
            return "Synced"
        case .failure(_):
            return "Latest"
        }
    }
}

#if DEBUG
private struct WatchHomePreview: View {
    var snapshot: WatchDailyHealthSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Today")
                        .font(.title2.weight(.bold))
                    Text(snapshot.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                if snapshot.alarm.isEnabled, snapshot.alarm.syncedAt != nil {
                    WatchAlarmPill(alarm: snapshot.alarm)
                }
                GeometryReader { proxy in
                    let spacing: CGFloat = proxy.size.width < 170 ? 4 : 6
                    let cardWidth = (proxy.size.width - spacing * 2) / 3
                    let ringSize: CGFloat = min(46, max(36, cardWidth * 0.78))
                    HStack(spacing: spacing) {
                        WatchMetricCardView(title: "Sleep", score: snapshot.sleep.score, subtitle: "", symbol: "moon.zzz.fill", tint: PulsarMetricRingTheme.tint(for: .sleep), ringSize: ringSize, showsSubtitle: false)
                            .frame(width: cardWidth)
                        WatchMetricCardView(title: "Recovery", score: snapshot.recovery.score, subtitle: "", symbol: "heart.text.square.fill", tint: PulsarMetricRingTheme.tint(for: .recovery), ringSize: ringSize, showsSubtitle: false)
                            .frame(width: cardWidth)
                        WatchMetricCardView(title: "Strain", score: snapshot.strain.score, subtitle: "", symbol: "figure.run", tint: PulsarMetricRingTheme.tint(for: .strain), ringSize: ringSize, showsSubtitle: false, targetRange: PulsarSharedMetricCalculator.recommendedStrainTargetRange(forRecoveryScore: snapshot.recovery.score))
                            .frame(width: cardWidth)
                    }
                    .frame(width: proxy.size.width, alignment: .center)
                }
                .frame(height: 78)
                WatchStressCardView(stress: snapshot.stress)
            }
            .padding(8)
        }
    }
}

struct WatchHomeView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            WatchHomePreview(snapshot: WatchPreviewData.snapshot)
                .previewDevice("Apple Watch Series 9 (41mm)")
                .previewDisplayName("Small")
            WatchHomePreview(snapshot: WatchPreviewData.snapshot)
                .previewDevice("Apple Watch Series 9 (45mm)")
                .previewDisplayName("Medium")
            WatchHomePreview(snapshot: WatchPreviewData.snapshot)
                .previewDevice("Apple Watch Ultra 2 (49mm)")
                .previewDisplayName("Ultra")
            WatchHomePreview(snapshot: WatchPreviewData.missingSnapshot)
                .previewDevice("Apple Watch Series 9 (41mm)")
                .previewDisplayName("Watch Home Missing")
        }
    }
}
#endif
