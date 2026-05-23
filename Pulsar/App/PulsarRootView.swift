//
//  PulsarRootView.swift
//  Pulsar
//

import SwiftUI
import Combine
import UIKit

struct PulsarRootView: View {
    @State private var selectedTab: PulsarRootTab = .home
    @State private var lastPresentedWorkout: PulsarPresentedWorkout?
    @State private var tabBarMetrics = PulsarTabBarMetrics()
    @State private var lastVisibleTabBarHeight: CGFloat = 0
    @State private var workoutFailureNotice: PulsarWorkoutFailureNotice?
    @State private var lastFailedWorkoutSessionID: UUID?
    @State private var ignoredFailedSessionIDs = Set<UUID>()
    @State private var lastKnownActiveWorkoutDisplayStates: [UUID: PulsarWorkoutMiniPlayerState] = [:]
    @State private var presentedPlusDestination: PulsarPlusDestination?
    @StateObject private var homeViewModel = HomeViewModel()
    @StateObject private var runCoordinator = PulsarRunCoordinator()
    @StateObject private var watchSyncStore = PulsarWatchConnectivitySyncStore.shared
    @StateObject private var activeWorkoutManager = PulsarActiveWorkoutManager()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        rootShellWithLifecycle
    }

    private var workoutFailureNoticeBinding: Binding<PulsarWorkoutFailureNotice?> {
        Binding(
            get: {
                guard let notice = workoutFailureNotice else { return nil }
                if notice.wasCurrentSessionAtFailure ||
                    activeWorkoutManager.activeWorkout?.sessionID == notice.sessionID {
                    return notice
                }
                PulsarStateDebugLogger.log("Alert gate blocked failedSession=\(notice.sessionID.uuidString) currentSession=\(activeWorkoutManager.activeWorkout?.sessionID.uuidString ?? "none")")
                return nil
            },
            set: { newValue in
                workoutFailureNotice = newValue
            }
        )
    }

    private var rootShellWithPresentation: some View {
        rootShell
            .tint(.accentColor)
            .environmentObject(activeWorkoutManager)
            .environmentObject(runCoordinator)
            .alert(item: workoutFailureNoticeBinding) { notice in
                Alert(
                    title: Text("Workout connection lost"),
                    message: Text(notice.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .sheet(
                item: $activeWorkoutManager.presentedWorkout,
                onDismiss: handleWorkoutPresentationDismissed
            ) { workout in
                presentedWorkoutView(workout)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.regularMaterial)
            }
            .fullScreenCover(item: $presentedPlusDestination) { destination in
                plusDestinationView(destination)
            }
    }

    private var rootShellWithLifecycle: some View {
        rootShellWithPresentation
            .task {
                syncCurrentActiveWorkoutSessionContext(reason: "rootTask")
                await homeViewModel.requestInitialAppEntrySync()
                watchSyncStore.pruneStaleActiveWorkoutState(reason: "rootTask")
                await GymLiveActivityManager.endStaleActivitiesIfNeeded(activeState: watchSyncStore.activeGymState)
                await reconcileRestoredActiveWorkoutOnAppEntry(source: "rootTask")
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else {
                    homeViewModel.appDidResignActive()
                    return
                }
                Task {
                    await homeViewModel.appDidBecomeActive()
                    watchSyncStore.pruneStaleActiveWorkoutState(reason: "sceneBecameActive")
                    await GymLiveActivityManager.endStaleActivitiesIfNeeded(activeState: watchSyncStore.activeGymState)
                    await reconcileRestoredActiveWorkoutOnAppEntry(source: "sceneBecameActive")
                }
            }
            .onChange(of: activeWorkoutManager.presentedWorkout) { _, newValue in
                if let newValue {
                    lastPresentedWorkout = newValue
                }
            }
            .onChange(of: runCoordinator.snapshot.phase) { _, newPhase in
                handleRunPhaseChanged(newPhase)
            }
            .onChange(of: runCoordinator.snapshot) { _, _ in
                cacheActiveWorkoutDisplayStateIfAvailable(reason: "runSnapshotChanged")
            }
            .onChange(of: watchSyncStore.activeWorkoutState) { _, state in
                guard state?.phase != .failed else { return }
                let source = activeWorkoutSyncSource(for: state, fallback: "activeWorkoutSyncChanged")
                guard shouldApplyLiveActiveWorkoutSyncUpdate(state, source: source) else {
                    if let state, case .gym = state.kind {
                        Task {
                            await discardStaleRestoredActiveWorkout(
                                state,
                                source: source,
                                reason: restoredActiveWorkoutRejectionReason(state, source: source)
                            )
                        }
                    }
                    return
                }
                applyActiveWorkoutSyncUpdate(state, source: source)
                cacheActiveWorkoutDisplayStateIfAvailable(reason: "activeWorkoutSyncChanged")
            }
            .onChange(of: watchSyncStore.activeGymState?.isFinished) { _, isFinished in
                if isFinished == true {
                    activeWorkoutManager.clearWatchGymWorkout(
                        sessionID: watchSyncStore.activeGymState?.sessionId,
                        phase: "ended",
                        source: "activeGymStateChanged",
                        reason: "watchGymFinished"
                    )
                }
            }
            .onReceive(watchSyncStore.$lastActiveWorkoutUpdateEvent.compactMap { $0 }) { event in
                guard event.state.phase == .failed || event.state.isEnded else { return }
                handleActiveWorkoutUpdateDecision(event.decision, state: event.state, source: event.source)
            }
            .onAppear {
                syncCurrentActiveWorkoutSessionContext(reason: "rootAppear")
                PulsarArchitectureDebugLogger.log("Using MiniWorkoutHost placement=\(miniWorkoutPlacementDescription)")
                PulsarUIDebugLogger.log("MiniWorkoutHost mounted at root")
                activeWorkoutManager.reconcilePresentationIntegrity(reason: "rootAppear")
                cacheActiveWorkoutDisplayStateIfAvailable(reason: "rootAppear")
                logMiniWorkoutVisibility()
            }
            .onChange(of: shouldShowMiniWorkoutBar) { _, shouldShow in
                cacheActiveWorkoutDisplayStateIfAvailable(reason: "miniBarVisibilityChanged")
                logMiniWorkoutVisibility()
                if shouldShow, let sessionID = activeWorkoutManager.activeWorkout?.sessionID {
                    PulsarUIDebugLogger.log("MiniWorkout visible session=\(sessionID.uuidString) placement=\(miniWorkoutPlacementDescription)")
                }
            }
            .onChange(of: activeWorkoutManager.presentation) { _, _ in
                activeWorkoutManager.reconcilePresentationIntegrity(reason: "presentationChanged")
                cacheActiveWorkoutDisplayStateIfAvailable(reason: "presentationChanged")
                logMiniWorkoutVisibility()
            }
            .onChange(of: activeWorkoutManager.activeWorkout?.sessionID) { _, _ in
                syncCurrentActiveWorkoutSessionContext(reason: "activeWorkoutChanged")
                activeWorkoutManager.reconcilePresentationIntegrity(reason: "activeWorkoutChanged")
                pruneLastKnownWorkoutDisplayStates()
                cacheActiveWorkoutDisplayStateIfAvailable(reason: "activeWorkoutChanged")
                logMiniWorkoutVisibility()
            }
            .onChange(of: selectedTab) { _, _ in
                logMiniWorkoutVisibility()
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.88), value: activeWorkoutMiniPlayerState?.sessionID)
    }

    private var rootShell: some View {
        ZStack(alignment: .bottom) {
            PulsarRootTabBackground(tab: selectedTab)
                .ignoresSafeArea()

            nativeTabs
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .background(
                    PulsarTabBarMetricsReader { metrics in
                        updateTabBarMetrics(metrics)
                    }
                )

            rootMiniWorkoutHost
        }
        .background(PulsarRootTabBackground(tab: selectedTab).ignoresSafeArea())
    }

    @ViewBuilder
    private var nativeTabs: some View {
        PulsarNativeTabController(
            selectedTab: $selectedTab,
            homeViewModel: homeViewModel,
            activeWorkoutManager: activeWorkoutManager,
            runCoordinator: runCoordinator,
            onOpenDestination: openPlusDestination,
            onMetricsChange: updateTabBarMetrics
        )
    }

    @ViewBuilder
    private var rootMiniWorkoutHost: some View {
        if shouldShowMiniWorkoutBar, let state = activeWorkoutMiniPlayerState {
            GeometryReader { proxy in
                ZStack(alignment: .top) {
                    Color.clear
                        .allowsHitTesting(false)

                    PulsarMiniWorkoutBarHost(
                        state: state,
                        isInlinePlacement: false,
                        placement: "rootStable",
                        onOpen: openActiveWorkoutMiniPlayer,
                        onPrimaryAction: handleActiveWorkoutMiniPlayerAction
                    )
                    .frame(maxWidth: rootMiniWorkoutMaxWidth)
                    .padding(.horizontal, rootMiniWorkoutHorizontalPadding)
                    .frame(width: proxy.size.width, height: rootMiniWorkoutHeight)
                    .position(
                        x: proxy.size.width / 2,
                        y: rootMiniWorkoutCenterY(in: proxy)
                    )
                    .onAppear {
                        PulsarUIDebugLogger.log("Rendering MiniActiveWorkoutBar from root stable host")
                        PulsarUIDebugLogger.log("MiniWorkout visible session=\(state.sessionID.uuidString) placement=rootStable")
                    }
                }
            }
            .zIndex(999)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var shouldShowMiniWorkoutBar: Bool {
        guard let activeWorkout = activeWorkoutManager.activeWorkout,
              activeWorkoutManager.presentation == .minimized(activeWorkout.sessionID) else {
            return false
        }
        guard let state = activeWorkoutMiniPlayerState else {
            PulsarStateDebugLogger.log("Mini workout display state unavailable; preserving active workout session=\(activeWorkout.sessionID.uuidString) presentation=\(activeWorkoutManager.presentation)")
            return false
        }
        guard activeWorkout.sessionID == state.sessionID else {
            PulsarStateDebugLogger.log("Refused mini workout render because state session mismatched activeSession=\(activeWorkout.sessionID.uuidString) stateSession=\(state.sessionID.uuidString)")
            return false
        }
        return true
    }

    private var rootMiniWorkoutMaxWidth: CGFloat {
        horizontalSizeClass == .regular ? 720 : .infinity
    }

    private var miniWorkoutPlacementDescription: String {
        if usesNativeMiniWorkoutTabAccessory {
            return "tabAccessory"
        }
        return "rootStable"
    }

    private var usesNativeMiniWorkoutTabAccessory: Bool {
        return false
    }


    private var rootMiniWorkoutHorizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 56 : 16
    }

    private var rootMiniWorkoutHeight: CGFloat {
        60
    }

    private var rootMiniWorkoutGap: CGFloat {
        8
    }

    private func rootMiniWorkoutCenterY(in proxy: GeometryProxy) -> CGFloat {
        guard proxy.size.height > rootMiniWorkoutHeight else {
            return rootMiniWorkoutHeight / 2
        }
        let rootFrame = proxy.frame(in: .global)
        let tabTopY = tabBarMetrics.minY - rootFrame.minY

        if tabTopY > rootMiniWorkoutHeight,
           tabTopY < proxy.size.height {
            let proposed = max(
                rootMiniWorkoutHeight / 2 + rootMiniWorkoutGap,
                tabTopY - rootMiniWorkoutGap - rootMiniWorkoutHeight / 2
            )
            return min(proposed, proxy.size.height - rootMiniWorkoutHeight / 2)
        }

        let fallbackTabChromeHeight = max(tabBarMetrics.visibleHeight, lastVisibleTabBarHeight, tabBarMetrics.bottomSafeAreaInset + 58, 72)
        let proposed = max(
            rootMiniWorkoutHeight / 2 + rootMiniWorkoutGap,
            proxy.size.height - fallbackTabChromeHeight - rootMiniWorkoutGap - rootMiniWorkoutHeight / 2
        )
        return min(proposed, proxy.size.height - rootMiniWorkoutHeight / 2)
    }

    private var activeWorkoutMiniPlayerState: PulsarWorkoutMiniPlayerState? {
        currentActiveWorkoutMiniPlayerState ?? cachedActiveWorkoutMiniPlayerState
    }

    private var currentActiveWorkoutMiniPlayerState: PulsarWorkoutMiniPlayerState? {
        guard let activeWorkout = activeWorkoutManager.activeWorkout,
              activeWorkoutManager.presentation == .minimized(activeWorkout.sessionID) else { return nil }

        switch activeWorkout.kind {
        case .run:
            if let state = watchSyncStore.activeWorkoutState,
               state.sessionId == activeWorkout.sessionID,
               state.lastUpdatedFrom.isAppleWatchRecorder,
               state.phase.isMiniBarDisplayable {
                return syncMiniPlayerState(for: activeWorkout) ?? runMiniPlayerState(for: activeWorkout)
            }
            return runMiniPlayerState(for: activeWorkout) ?? syncMiniPlayerState(for: activeWorkout)
        case .gym:
            return gymMiniPlayerState(for: activeWorkout)
        case .watchGym:
            return watchGymMiniPlayerState(for: activeWorkout) ?? syncMiniPlayerState(for: activeWorkout)
        }
    }

    private var cachedActiveWorkoutMiniPlayerState: PulsarWorkoutMiniPlayerState? {
        guard let activeWorkout = activeWorkoutManager.activeWorkout,
              activeWorkoutManager.presentation == .minimized(activeWorkout.sessionID) else { return nil }
        guard let cached = lastKnownActiveWorkoutDisplayStates[activeWorkout.sessionID] else { return nil }
        PulsarStateDebugLogger.log("Using last known mini workout display state session=\(activeWorkout.sessionID.uuidString)")
        return cached
    }

    private func runMiniPlayerState(for activeWorkout: PulsarActiveWorkout) -> PulsarWorkoutMiniPlayerState? {
        let snapshot = runCoordinator.snapshot
        guard case .run(let workoutKind) = activeWorkout.kind else { return nil }
        guard snapshot.phase.isActiveWorkoutPhase else { return nil }
        guard snapshot.pulsarWorkoutSessionId == activeWorkout.sessionID ||
                watchSyncStore.activeWorkoutState?.sessionId == activeWorkout.sessionID else { return nil }

        if snapshot.pulsarWorkoutSessionId == nil {
            PulsarStateDebugLogger.log("Refused to render mini workout because sessionID was nil")
            return nil
        }

        let heartRateText = snapshot.currentHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "HR unavailable"
        let detail = snapshot.distanceMeters > 10
            ? "\(PulsarRunFormatters.distance(snapshot.distanceMeters)) · \(PulsarRunFormatters.paceOrSpeed(workoutKind: workoutKind, paceSecondsPerKilometer: snapshot.currentPaceSecondsPerKilometer, speedMetersPerSecond: snapshot.distanceMeters / max(snapshot.movingTime, 1)))"
            : snapshot.source.label
        let sessionIdentifier = activeWorkout.sessionID.uuidString

        return PulsarWorkoutMiniPlayerState(
            id: "run-\(workoutKind.rawValue)-\(sessionIdentifier)",
            sessionID: activeWorkout.sessionID,
            kind: .run(workoutKind),
            title: workoutKind.displayName,
            subtitle: snapshot.phase == .paused ? "Paused" : "Live workout",
            metrics: "\(PulsarRunFormatters.duration(snapshot.elapsedTime)) · \(heartRateText)",
            detail: detail,
            symbol: workoutKind.systemImageName,
            isPaused: snapshot.phase == .paused
        )
    }

    private func gymMiniPlayerState(for activeWorkout: PulsarActiveWorkout) -> PulsarWorkoutMiniPlayerState? {
        guard activeWorkout.kind == .gym else { return nil }
        guard let viewModel = activeWorkoutManager.gymSessionViewModel,
              viewModel.summary == nil,
              viewModel.session.id == activeWorkout.sessionID,
              activeWorkoutManager.isGymWorkoutMinimized else { return nil }

        let heartRateText = viewModel.currentHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "HR unavailable"
        return PulsarWorkoutMiniPlayerState(
            id: "gym-\(viewModel.session.id.uuidString)",
            sessionID: viewModel.session.id,
            kind: .gym,
            title: viewModel.session.routineName,
            subtitle: "Gym workout",
            metrics: "\(PulsarGymFormatters.duration(viewModel.elapsedSeconds)) · \(heartRateText)",
            detail: "\(viewModel.completedSetsCount)/\(viewModel.totalSetsCount) sets",
            symbol: "dumbbell.fill",
            isPaused: false
        )
    }

    private func watchGymMiniPlayerState(for activeWorkout: PulsarActiveWorkout) -> PulsarWorkoutMiniPlayerState? {
        guard activeWorkout.kind == .watchGym else { return nil }
        guard let state = watchSyncStore.activeGymState,
              state.sessionId == activeWorkout.sessionID,
              !state.isFinished,
              watchSyncStore.isRoutableActiveGymState(state),
              activeWorkoutManager.gymSessionViewModel == nil else { return nil }

        let heartRateText = state.currentHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "HR unavailable"
        return PulsarWorkoutMiniPlayerState(
            id: "watch-gym-\(state.sessionId.uuidString)",
            sessionID: state.sessionId,
            kind: .watchGym,
            title: state.routineName,
            subtitle: "Apple Watch Gym",
            metrics: "\(PulsarGymFormatters.duration(state.elapsedSeconds)) · \(heartRateText)",
            detail: state.progressText,
            symbol: "applewatch",
            isPaused: false
        )
    }

    private func syncMiniPlayerState(for activeWorkout: PulsarActiveWorkout) -> PulsarWorkoutMiniPlayerState? {
        guard let state = watchSyncStore.activeWorkoutState,
              state.sessionId == activeWorkout.sessionID,
              state.phase.isMiniBarDisplayable else { return nil }

        let heartRateText = state.currentHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "HR unavailable"
        let detail = state.startedFrom.displayName

        switch state.kind {
        case .outdoor(let workoutKind):
            let distanceDetail = (state.distanceMeters ?? 0) > 10
                ? "\(PulsarRunFormatters.distance(state.distanceMeters ?? 0)) · \(PulsarRunFormatters.paceOrSpeed(workoutKind: workoutKind, paceSecondsPerKilometer: state.currentPaceSecondsPerKilometer, speedMetersPerSecond: state.averageSpeedMetersPerSecond))"
                : detail
            return PulsarWorkoutMiniPlayerState(
                id: "sync-run-\(workoutKind.rawValue)-\(state.sessionId.uuidString)",
                sessionID: state.sessionId,
                kind: .run(workoutKind),
                title: workoutKind.displayName,
                subtitle: state.phase.miniBarSubtitle,
                metrics: "\(PulsarRunFormatters.duration(TimeInterval(state.elapsedSeconds))) · \(heartRateText)",
                detail: distanceDetail,
                symbol: workoutKind.systemImageName,
                isPaused: state.phase == .paused
            )
        case .gym:
            let metrics = "\(PulsarRunFormatters.duration(TimeInterval(state.elapsedSeconds))) · \(heartRateText)"
            return PulsarWorkoutMiniPlayerState(
                id: "sync-gym-\(state.kind.workoutTypeRawValue)-\(state.sessionId.uuidString)",
                sessionID: state.sessionId,
                kind: .watchGym,
                title: state.displayName,
                subtitle: state.phase.miniBarSubtitle,
                metrics: metrics,
                detail: detail,
                symbol: "applewatch",
                isPaused: false
            )
        }
    }

    private func openPlusDestination(_ destination: PulsarPlusDestination) {
        playPlusMenuHaptic(.light)
        DispatchQueue.main.async {
            presentedPlusDestination = destination
        }
    }

    private func dismissPlusDestination() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        presentedPlusDestination = nil
    }

    private func playPlusMenuHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    private func openActiveWorkoutMiniPlayer() {
        guard let state = activeWorkoutMiniPlayerState else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        switch state.kind {
        case .run(let workoutKind):
            activeWorkoutManager.presentRunWorkout(
                workoutKind,
                sessionID: state.sessionID
            )
        case .gym:
            activeWorkoutManager.presentGymWorkout(sessionID: state.sessionID)
        case .watchGym:
            activeWorkoutManager.presentWatchGymWorkout(sessionID: state.sessionID)
        }
    }

    private func handleActiveWorkoutMiniPlayerAction() {
        guard let state = activeWorkoutMiniPlayerState else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        switch state.kind {
        case .run:
            if runCoordinator.snapshot.phase == .paused {
                runCoordinator.resume()
            } else if runCoordinator.snapshot.phase == .running {
                runCoordinator.pause()
            } else {
                openActiveWorkoutMiniPlayer()
            }
        case .gym, .watchGym:
            openActiveWorkoutMiniPlayer()
        }
    }

    private func resolvedRunSessionIDForMiniWorkout(reason: String) -> UUID? {
        runCoordinator.snapshot.pulsarWorkoutSessionId
            ?? activeWorkoutManager.activeWorkout?.sessionID
            ?? runCoordinator.ensureActiveWorkoutSessionID(reason: reason)
    }

    private func handleWorkoutPresentationDismissed() {
        guard let workout = lastPresentedWorkout else { return }
        lastPresentedWorkout = nil

        switch workout {
        case .run(let workoutKind):
            guard runCoordinator.snapshot.phase.isActiveWorkoutPhase else { return }
            activeWorkoutManager.minimizeRunWorkout(
                workoutKind,
                sessionID: resolvedRunSessionIDForMiniWorkout(reason: "sheetDismissed")
            )
        case .gym:
            guard activeWorkoutManager.gymSessionViewModel?.summary == nil else { return }
            activeWorkoutManager.minimizeGymWorkout(sessionID: activeWorkoutManager.gymSessionViewModel?.session.id)
        case .watchGym:
            guard let state = watchSyncStore.activeGymState,
                  !state.isFinished,
                  watchSyncStore.isRoutableActiveGymState(state) else { return }
            activeWorkoutManager.minimizeWatchGymWorkout(sessionID: state.sessionId)
        }
    }

    private func handleRunPhaseChanged(_ newPhase: PulsarRunPhase) {
        guard let activeWorkout = activeWorkoutManager.activeWorkout,
              case .run = activeWorkout.kind else { return }

        guard newPhase.isTerminalActiveWorkoutClearPhase else {
            PulsarStateDebugLogger.log("Blocked active run clear from non-terminal local phase session=\(activeWorkout.sessionID.uuidString) phase=\(newPhase.rawValue)")
            return
        }

        let sessionID = runCoordinator.snapshot.pulsarWorkoutSessionId ?? activeWorkout.sessionID
        if newPhase == .failed,
           let state = watchSyncStore.activeWorkoutState,
           state.sessionId == sessionID,
           state.phase.isLive {
            PulsarStateDebugLogger.log("Blocked active run clear from local failed phase because Watch still reports live session=\(sessionID.uuidString) watchPhase=\(state.phase.rawValue)")
            return
        }

        activeWorkoutManager.clearRunWorkout(
            sessionID: sessionID,
            phase: newPhase.rawValue,
            source: "runCoordinatorPhaseChanged",
            reason: "localRunPhaseChanged"
        )
    }

    private func cacheActiveWorkoutDisplayStateIfAvailable(reason: String) {
        guard let activeWorkout = activeWorkoutManager.activeWorkout,
              activeWorkoutManager.presentation == .minimized(activeWorkout.sessionID),
              let state = currentActiveWorkoutMiniPlayerState,
              state.sessionID == activeWorkout.sessionID else { return }

        guard lastKnownActiveWorkoutDisplayStates[state.sessionID] != state else { return }
        lastKnownActiveWorkoutDisplayStates[state.sessionID] = state
        pruneLastKnownWorkoutDisplayStates()
        PulsarStateDebugLogger.log("Cached mini workout display state session=\(state.sessionID.uuidString) reason=\(reason)")
    }

    private func pruneLastKnownWorkoutDisplayStates() {
        guard let activeSessionID = activeWorkoutManager.activeWorkout?.sessionID else {
            lastKnownActiveWorkoutDisplayStates.removeAll()
            return
        }
        lastKnownActiveWorkoutDisplayStates = lastKnownActiveWorkoutDisplayStates.filter { $0.key == activeSessionID }
    }

    private func syncCurrentActiveWorkoutSessionContext(reason: String) {
        watchSyncStore.setCurrentActiveWorkoutSessionContext(
            sessionID: activeWorkoutManager.activeWorkout?.sessionID,
            canShowConnectionLostAlert: currentActiveWorkoutCanShowConnectionLostAlert(),
            reason: reason
        )
    }

    private func currentActiveWorkoutCanShowConnectionLostAlert() -> Bool {
        guard let activeWorkout = activeWorkoutManager.activeWorkout else { return false }
        return activeWorkoutCanShowConnectionLostAlert(activeWorkout)
    }

    private func activeWorkoutCanShowConnectionLostAlert(_ activeWorkout: PulsarActiveWorkout) -> Bool {
        switch activeWorkout.kind {
        case .run:
            if let state = watchSyncStore.activeWorkoutState,
               state.sessionId == activeWorkout.sessionID,
               state.startedFrom == .appleWatch {
                return false
            }
            return runCoordinator.snapshot.phase.isActiveWorkoutPhase &&
                runCoordinator.snapshot.pulsarWorkoutSessionId == activeWorkout.sessionID
        case .gym:
            return activeWorkoutManager.gymSessionViewModel?.summary == nil &&
                activeWorkoutManager.gymSessionViewModel?.session.id == activeWorkout.sessionID
        case .watchGym:
            guard let state = watchSyncStore.activeGymState,
                  state.sessionId == activeWorkout.sessionID,
                  !state.isFinished else { return false }
            return watchSyncStore.isRoutableActiveGymState(state)
        }
    }

    private func reconcileRestoredActiveWorkoutOnAppEntry(source: String) async {
        guard let state = watchSyncStore.activeWorkoutState else {
            if !runCoordinator.hasAnyValidatedLiveWorkoutSession {
                await runCoordinator.endStaleLiveActivities(reason: "no validated active workout on launch")
            }
            syncCurrentActiveWorkoutSessionContext(reason: "\(source).noRestoredActiveWorkout")
            return
        }

        guard shouldApplyLiveActiveWorkoutSyncUpdate(state, source: source) else {
            await discardStaleRestoredActiveWorkout(
                state,
                source: source,
                reason: restoredActiveWorkoutRejectionReason(state, source: source)
            )
            return
        }

        applyValidatedRestoredActiveWorkoutSyncUpdate(state, source: source)
    }

    private func activeWorkoutSyncSource(
        for state: PulsarActiveWorkoutSyncState?,
        fallback: String
    ) -> String {
        guard let state,
              let event = watchSyncStore.lastActiveWorkoutUpdateEvent,
              event.state.sessionId == state.sessionId,
              event.state.updatedAt == state.updatedAt else { return fallback }
        return event.source
    }

    private func shouldApplyLiveActiveWorkoutSyncUpdate(
        _ state: PulsarActiveWorkoutSyncState?,
        source: String
    ) -> Bool {
        guard let state else { return true }
        guard !state.isEnded else { return true }

        if state.phase == .ending,
           activeWorkoutManager.activeWorkout?.sessionID != state.sessionId {
            PulsarSyncDebugLogger.log("Rejected unowned ending workout restore source=\(source) session=\(state.sessionId.uuidString) action=noop")
            return false
        }

        if let presentationRejectionReason = state.activeWorkoutPresentationRejectionReason() {
            PulsarSyncDebugLogger.log("active workout restore rejected: \(presentationRejectionReason) source=\(source) session=\(state.sessionId.uuidString) phase=\(state.phase.rawValue)")
            return false
        }

        if case .gym = state.kind {
            guard let activeGymState = watchSyncStore.activeGymState,
                  activeGymState.sessionId == state.sessionId else {
                PulsarSyncDebugLogger.log("active workout restore rejected: missing active gym state source=\(source) session=\(state.sessionId.uuidString)")
                return false
            }
            if let gymRejectionReason = activeGymState.activeWorkoutPresentationRejectionReason() {
                PulsarSyncDebugLogger.log("active workout restore rejected: \(gymRejectionReason) source=\(source) session=\(state.sessionId.uuidString)")
                return false
            }
            guard activeGymState.startedFrom?.isAppleWatchRecorder == true else {
                PulsarSyncDebugLogger.log("active workout restore rejected: untrusted gym source source=\(source) session=\(state.sessionId.uuidString) startedFrom=\(activeGymState.startedFrom?.rawValue ?? "unknown")")
                return false
            }
            return true
        }

        if activeWorkoutManager.activeWorkout?.sessionID == state.sessionId {
            return true
        }

        if runCoordinator.hasValidatedLiveWorkoutSession(sessionID: state.sessionId) {
            return true
        }

        if state.startedFrom == .iPhone,
           state.lastUpdatedFrom == .iPhone,
           source.hasPrefix("iPhoneRun") {
            return true
        }

        if source.hasPrefix("received"),
           state.lastUpdatedFrom == .appleWatch,
           state.isFreshRestoreConfirmation() {
            return true
        }

        PulsarSyncDebugLogger.log(
            "Rejected unverified active workout restore source=\(source) session=\(state.sessionId.uuidString) phase=\(state.phase.rawValue) updatedAt=\(state.updatedAt) reason=\(restoredActiveWorkoutRejectionReason(state, source: source)) action=noop"
        )
        return false
    }

    private func restoredActiveWorkoutRejectionReason(
        _ state: PulsarActiveWorkoutSyncState,
        source: String
    ) -> String {
        if let presentationRejectionReason = state.activeWorkoutPresentationRejectionReason() {
            return presentationRejectionReason
        }
        if case .gym = state.kind {
            guard let activeGymState = watchSyncStore.activeGymState,
                  activeGymState.sessionId == state.sessionId else {
                return "missing active gym state"
            }
            if let gymRejectionReason = activeGymState.activeWorkoutPresentationRejectionReason() {
                return gymRejectionReason
            }
            if activeGymState.startedFrom != .appleWatch {
                return "untrusted gym source"
            }
        }
        if !state.phase.isRestoreEligible {
            return "phase=\(state.phase.rawValue)"
        }
        if runCoordinator.hasValidatedLiveWorkoutSession(sessionID: state.sessionId) {
            return "validatedLocalHealthKitSession"
        }
        if source.hasPrefix("received"),
           state.lastUpdatedFrom == .appleWatch,
           !state.isFreshRestoreConfirmation() {
            let age = Int(Date().timeIntervalSince(state.updatedAt).rounded())
            return "watchConfirmationStale age=\(age)s"
        }
        return "noVerifiedLiveWorkoutSource"
    }

    private func applyValidatedRestoredActiveWorkoutSyncUpdate(
        _ state: PulsarActiveWorkoutSyncState,
        source: String
    ) {
        switch state.kind {
        case .outdoor(let workoutKind):
            runCoordinator.reconcileActiveWorkoutSyncState(state)
            if activeWorkoutManager.activeWorkout?.sessionID == state.sessionId {
                activeWorkoutManager.reconcilePresentationIntegrity(reason: "\(source).validatedRestore")
            } else {
                activeWorkoutManager.minimizeRunWorkout(workoutKind, sessionID: state.sessionId)
                PulsarSyncDebugLogger.log("iPhone active workout UI restore minimized reason=\(source) session=\(state.sessionId.uuidString) type=\(workoutKind.rawValue)")
            }
            syncCurrentActiveWorkoutSessionContext(reason: "\(source).validatedRestore")
        case .gym:
            applyActiveWorkoutSyncUpdate(state, source: source)
        }
    }

    private func discardStaleRestoredActiveWorkout(
        _ state: PulsarActiveWorkoutSyncState,
        source: String,
        reason: String
    ) async {
        PulsarSyncDebugLogger.log("active workout restore rejected: \(reason) source=\(source) session=\(state.sessionId.uuidString) phase=\(state.phase.rawValue)")
        watchSyncStore.tombstoneActiveWorkoutSession(state.sessionId, reason: "discardedStaleRestoredActiveWorkout.\(source)")
        watchSyncStore.clearActiveWorkoutState(reason: "discardedStaleRestoredActiveWorkout.\(source)", broadcastEndedState: false)
        switch state.kind {
        case .outdoor:
            activeWorkoutManager.clearRunWorkout(
                sessionID: state.sessionId,
                phase: "ended",
                source: source,
                reason: "discardedStaleRestoredActiveWorkout"
            )
            await runCoordinator.discardRestoredActiveWorkout(
                sessionID: state.sessionId,
                reason: "restored workout was stale"
            )
        case .gym:
            if watchSyncStore.activeGymState?.sessionId == state.sessionId {
                watchSyncStore.clearActiveGymState(reason: "discardedStaleRestoredActiveWorkout.\(source)", broadcastEndedState: false)
            }
            activeWorkoutManager.clearWatchGymWorkout(
                sessionID: state.sessionId,
                phase: "ended",
                source: source,
                reason: "discardedStaleRestoredActiveWorkout"
            )
        }
        PulsarSyncDebugLogger.log("active workout state cleared on launch source=\(source) session=\(state.sessionId.uuidString)")
        syncCurrentActiveWorkoutSessionContext(reason: "discardedStaleRestoredActiveWorkout")
    }

    @discardableResult
    private func applyActiveWorkoutSyncUpdate(_ state: PulsarActiveWorkoutSyncState?, source: String) -> ActiveWorkoutUpdateDecision {
        let decision = ActiveWorkoutUpdateDecision.userInterfaceDecision(
            for: state,
            currentSessionID: activeWorkoutManager.activeWorkout?.sessionID,
            currentSessionUpdatedAt: activeWorkoutManager.activeWorkout?.updatedAt,
            currentSessionCanShowConnectionLostAlert: currentActiveWorkoutCanShowConnectionLostAlert(),
            ignoredFailedSessionIDs: ignoredFailedSessionIDs
        )
        return handleActiveWorkoutUpdateDecision(decision, state: state, source: source)
    }

    @discardableResult
    private func handleActiveWorkoutUpdateDecision(
        _ decision: ActiveWorkoutUpdateDecision,
        state: PulsarActiveWorkoutSyncState?,
        source: String
    ) -> ActiveWorkoutUpdateDecision {
        switch decision {
        case .appliedActive, .appliedPaused:
            guard let state else { return decision }
            applyLiveActiveWorkoutSyncUpdate(state, source: source)
        case .endedCurrent:
            guard let state else { return decision }
            applyEndedActiveWorkoutSyncUpdate(state, source: source)
        case .failedCurrentAndShouldAlert:
            guard let state else {
                suppressConnectionLostAlert(reason: "invalidNoSession", sessionID: decision.sessionID)
                return decision
            }
            handleCurrentFailedActiveWorkoutSyncUpdate(state, source: source)
        case .ignoredStaleFailed(let sessionID):
            ignoredFailedSessionIDs.insert(sessionID)
            logAlertGateBlocked(failedSessionID: sessionID)
            PulsarStateDebugLogger.log("activeWorkout unchanged after stale failed update currentSession=\(activeWorkoutManager.activeWorkout?.sessionID.uuidString ?? "none")")
            let currentSessionID = activeWorkoutManager.activeWorkout?.sessionID
            let reason = currentSessionID == nil
                ? "currentSessionNil"
                : currentSessionID == sessionID ? "failedUpdateWasNeverCurrent" : "sessionMismatch"
            suppressConnectionLostAlert(reason: reason, sessionID: sessionID)
            if reason != "failedUpdateWasNeverCurrent" {
                suppressConnectionLostAlert(reason: "failedUpdateWasNeverCurrent", sessionID: sessionID)
            }
        case .ignoredDuplicateStaleFailed(let sessionID):
            logAlertGateBlocked(failedSessionID: sessionID)
            PulsarStateDebugLogger.log("activeWorkout unchanged after stale failed update currentSession=\(activeWorkoutManager.activeWorkout?.sessionID.uuidString ?? "none")")
            suppressConnectionLostAlert(reason: "duplicateStaleFailed", sessionID: sessionID)
        case .ignoredInvalidNoSession:
            break
        case .ignoredHistoricalOnly:
            if state?.phase == .failed, let sessionID = state?.sessionId {
                logAlertGateBlocked(failedSessionID: sessionID)
                suppressConnectionLostAlert(reason: "historicalFailed", sessionID: sessionID)
            } else if state?.isEnded == true {
                PulsarSyncDebugLogger.log("Ignored stale ended workout update session=\(state?.sessionId.uuidString ?? "none") currentSession=\(activeWorkoutManager.activeWorkout?.sessionID.uuidString ?? "none") action=noop")
            }
        }
        return decision
    }

    private func applyLiveActiveWorkoutSyncUpdate(_ state: PulsarActiveWorkoutSyncState, source: String) {
        ignoredFailedSessionIDs.remove(state.sessionId)
        PulsarSyncDebugLogger.log("Active workout UI update received from \(source) session=\(state.sessionId.uuidString) type=\(state.kind.workoutTypeRawValue) phase=\(state.phase.rawValue) startedFrom=\(state.startedFrom.rawValue) updatedFrom=\(state.lastUpdatedFrom.rawValue)")

        switch state.kind {
        case .outdoor(let workoutKind):
            let localRunIsActive = runCoordinator.snapshot.phase.isActiveWorkoutPhase &&
                runCoordinator.snapshot.pulsarWorkoutSessionId == state.sessionId
            guard localRunIsActive || watchSyncStore.isRoutableActiveWorkoutState(state) else {
                PulsarSyncDebugLogger.log("iPhone active workout UI route skipped without clearing reason=\(source) session=\(state.sessionId.uuidString) type=\(workoutKind.rawValue) staleReason=\(state.staleRouteReason() ?? "unknown") action=noop")
                return
            }
            runCoordinator.reconcileActiveWorkoutSyncState(state)
            PulsarSyncDebugLogger.log("active workout UI presentation allowed: valid active session source=\(source) session=\(state.sessionId.uuidString) type=\(workoutKind.rawValue)")
            if activeWorkoutManager.reconcileActiveWorkoutPresentation(
                route: .run(workoutKind),
                sessionID: state.sessionId,
                phase: state.phase.rawValue,
                reason: source
            ) {
                PulsarSyncDebugLogger.log("iPhone active workout UI route opened reason=\(source) session=\(state.sessionId.uuidString) type=\(workoutKind.rawValue)")
            }
            syncCurrentActiveWorkoutSessionContext(reason: "liveRunSyncApplied")
        case .gym:
            let activeGymState = watchSyncStore.activeGymState
            let gymStateIsRoutable = activeGymState?.sessionId == state.sessionId &&
                activeGymState?.startedFrom?.isAppleWatchRecorder == true &&
                activeGymState.map { watchSyncStore.isRoutableActiveGymState($0) } == true
            guard gymStateIsRoutable else {
                syncCurrentActiveWorkoutSessionContext(reason: "rejectedPassiveWatchGymSync")
                PulsarSyncDebugLogger.log("iPhone active gym mirror UI route skipped reason=\(source) session=\(state.sessionId.uuidString) type=\(state.kind.workoutTypeRawValue) startedFrom=\(state.startedFrom.rawValue) updatedFrom=\(state.lastUpdatedFrom.rawValue) staleReason=\(state.staleRouteReason() ?? activeGymState?.staleRouteReason() ?? "unknown") action=noop")
                return
            }
            guard activeWorkoutManager.gymSessionViewModel == nil else { return }
            PulsarSyncDebugLogger.log("active workout UI presentation allowed: valid active session source=\(source) session=\(state.sessionId.uuidString) type=\(state.kind.workoutTypeRawValue)")
            if activeWorkoutManager.reconcileActiveWorkoutPresentation(
                route: .watchGym,
                sessionID: state.sessionId,
                phase: state.phase.rawValue,
                reason: source
            ) {
                PulsarSyncDebugLogger.log("iPhone active gym mirror UI route opened reason=\(source) session=\(state.sessionId.uuidString) type=\(state.kind.workoutTypeRawValue)")
            }
            syncCurrentActiveWorkoutSessionContext(reason: "liveGymSyncApplied")
        }
    }

    private func applyEndedActiveWorkoutSyncUpdate(_ state: PulsarActiveWorkoutSyncState, source: String) {
        PulsarSyncDebugLogger.log("Active workout data updated from \(source) session=\(state.sessionId.uuidString) type=\(state.kind.workoutTypeRawValue) phase=\(state.phase.rawValue)")

        switch state.kind {
        case .outdoor:
            runCoordinator.reconcileActiveWorkoutSyncState(state)
            activeWorkoutManager.clearRunWorkout(
                sessionID: state.sessionId,
                phase: state.phase.rawValue,
                source: source,
                reason: "endedActiveWorkoutSync"
            )
        case .gym:
            activeWorkoutManager.clearWatchGymWorkout(
                sessionID: state.sessionId,
                phase: state.phase.rawValue,
                source: source,
                reason: "endedActiveWorkoutSync"
            )
        }
        syncCurrentActiveWorkoutSessionContext(reason: "endedActiveWorkoutSync")
    }

    private func handleCurrentFailedActiveWorkoutSyncUpdate(_ state: PulsarActiveWorkoutSyncState, source: String) {
        let currentSessionID = activeWorkoutManager.activeWorkout?.sessionID
        PulsarSyncDebugLogger.log("Failed update received source=\(source) session=\(state.sessionId.uuidString) currentSession=\(currentSessionID?.uuidString ?? "none")")

        guard alertGateAllowsConnectionLostAlert(failedSessionID: state.sessionId) else {
            let reason = currentSessionID == nil
                ? "currentSessionNil"
                : currentSessionID == state.sessionId ? "failedUpdateWasNeverCurrent" : "sessionMismatch"
            suppressConnectionLostAlert(reason: reason, sessionID: state.sessionId)
            if reason != "failedUpdateWasNeverCurrent" {
                suppressConnectionLostAlert(reason: "failedUpdateWasNeverCurrent", sessionID: state.sessionId)
            }
            return
        }

        PulsarSyncDebugLogger.log("Current active workout failed session=\(state.sessionId.uuidString) action=clearAndAlert")

        switch state.kind {
        case .outdoor:
            activeWorkoutManager.clearRunWorkout(
                sessionID: state.sessionId,
                phase: state.phase.rawValue,
                source: source,
                reason: "failedActiveWorkout"
            )
        case .gym:
            activeWorkoutManager.clearWatchGymWorkout(
                sessionID: state.sessionId,
                phase: state.phase.rawValue,
                source: source,
                reason: "failedActiveWorkout"
            )
            if watchSyncStore.activeGymState?.sessionId == state.sessionId {
                watchSyncStore.clearActiveGymState(reason: "failedActiveWorkout", broadcastEndedState: false)
            }
        }

        if watchSyncStore.activeWorkoutState?.sessionId == state.sessionId {
            watchSyncStore.clearActiveWorkoutState(reason: "failedActiveWorkout", broadcastEndedState: false)
        }
        syncCurrentActiveWorkoutSessionContext(reason: "failedActiveWorkout")

        PulsarUIDebugLogger.log("Cleared failed workout presentation session=\(state.sessionId.uuidString) presentation=\(activeWorkoutManager.presentation)")
        ignoredFailedSessionIDs.insert(state.sessionId)

        guard lastFailedWorkoutSessionID != state.sessionId else { return }
        lastFailedWorkoutSessionID = state.sessionId
        PulsarUIDebugLogger.log("Showing connection lost alert session=\(state.sessionId.uuidString) reason=currentActiveWorkoutFailed")
        workoutFailureNotice = PulsarWorkoutFailureNotice(
            sessionID: state.sessionId,
            message: "The active workout stopped syncing and was cleared. Start a new workout when you’re ready.",
            wasCurrentSessionAtFailure: true
        )
    }

    private func alertGateAllowsConnectionLostAlert(failedSessionID: UUID) -> Bool {
        guard let currentSessionID = activeWorkoutManager.activeWorkout?.sessionID else {
            PulsarStateDebugLogger.log("Alert gate blocked failedSession=\(failedSessionID.uuidString) currentSession=none")
            return false
        }

        guard currentSessionID == failedSessionID else {
            PulsarStateDebugLogger.log("Alert gate blocked failedSession=\(failedSessionID.uuidString) currentSession=\(currentSessionID.uuidString)")
            return false
        }

        guard currentActiveWorkoutCanShowConnectionLostAlert() else {
            PulsarStateDebugLogger.log("Alert gate blocked failedSession=\(failedSessionID.uuidString) currentSession=\(currentSessionID.uuidString) reason=notAlertEligible")
            return false
        }

        PulsarStateDebugLogger.log("Alert gate passed session=\(failedSessionID.uuidString)")
        return true
    }

    private func logAlertGateBlocked(failedSessionID: UUID) {
        PulsarStateDebugLogger.log("Alert gate blocked failedSession=\(failedSessionID.uuidString) currentSession=\(activeWorkoutManager.activeWorkout?.sessionID.uuidString ?? "none")")
    }

    private func suppressConnectionLostAlert(reason: String, sessionID: UUID?) {
        if let sessionID {
            clearConnectionLostAlertState(for: sessionID)
        }

        let currentSession = activeWorkoutManager.activeWorkout?.sessionID.uuidString ?? "none"
        switch (reason, sessionID) {
        case ("currentSessionNil", let sessionID?):
            PulsarUIDebugLogger.log("Suppressed connection lost alert reason=currentSessionNil failedSession=\(sessionID.uuidString)")
        case ("duplicateStaleFailed", let sessionID?):
            PulsarUIDebugLogger.log("Suppressed connection lost alert reason=duplicateStaleFailed session=\(sessionID.uuidString) currentSession=\(currentSession)")
        case ("sessionMismatch", let sessionID?):
            PulsarUIDebugLogger.log("Suppressed connection lost alert reason=sessionMismatch failedSession=\(sessionID.uuidString) currentSession=\(currentSession)")
        case ("historicalFailed", let sessionID?):
            PulsarUIDebugLogger.log("Suppressed connection lost alert reason=historicalFailed failedSession=\(sessionID.uuidString) currentSession=\(currentSession)")
        case ("invalidNoSession", let sessionID?):
            PulsarUIDebugLogger.log("Suppressed connection lost alert reason=invalidNoSession failedSession=\(sessionID.uuidString) currentSession=\(currentSession)")
        case ("failedUpdateWasNeverCurrent", let sessionID?):
            PulsarUIDebugLogger.log("Suppressed connection lost alert reason=failedUpdateWasNeverCurrent session=\(sessionID.uuidString)")
        default:
            PulsarUIDebugLogger.log("Suppressed connection lost alert reason=\(reason) currentSession=\(currentSession)")
        }
    }

    private func clearConnectionLostAlertState(for sessionID: UUID) {
        if workoutFailureNotice?.sessionID == sessionID {
            workoutFailureNotice = nil
        }
        if lastFailedWorkoutSessionID == sessionID {
            lastFailedWorkoutSessionID = nil
        }
    }

    private func logMiniWorkoutVisibility() {
        let shouldShow = shouldShowMiniWorkoutBar
        let state = activeWorkoutMiniPlayerState
        PulsarUIDebugLogger.log(
            "shouldShowMiniWorkoutBar=\(shouldShow) session=\(state?.sessionID.uuidString ?? "none") phase=\(activeWorkoutPhaseDescription) presentation=\(activeWorkoutManager.presentation) selectedTab=\(selectedTab.rawValue) miniState=\(state?.id ?? "none") placement=\(miniWorkoutPlacementDescription)"
        )
        if shouldShow, let sessionID = state?.sessionID {
            PulsarUIDebugLogger.log("MiniWorkoutHost shouldShow=true session=\(sessionID.uuidString)")
        }
    }

    private func updateTabBarMetrics(_ metrics: PulsarTabBarMetrics) {
        guard tabBarMetrics != metrics else { return }
        tabBarMetrics = metrics
        if metrics.visibleHeight > 1 {
            lastVisibleTabBarHeight = metrics.visibleHeight
        }
        PulsarUIDebugLogger.log("Native tab bar metrics visibleHeight=\(Int(metrics.visibleHeight)) height=\(Int(metrics.height)) width=\(Int(metrics.width)) minY=\(Int(metrics.minY)) minimized=\(metrics.isMinimized) hidden=\(metrics.isHidden)")
        if shouldShowMiniWorkoutBar, let sessionID = activeWorkoutMiniPlayerState?.sessionID {
            PulsarUIDebugLogger.log("MiniWorkout preserved during scroll session=\(sessionID.uuidString)")
        }
    }

    private var activeWorkoutPhaseDescription: String {
        guard let activeSessionID = activeWorkoutManager.activeWorkout?.sessionID else {
            return "unknown"
        }

        if let activeWorkoutState = watchSyncStore.activeWorkoutState,
           activeWorkoutState.sessionId == activeSessionID {
            return activeWorkoutState.phase.rawValue
        }

        if let runSessionID = runCoordinator.snapshot.pulsarWorkoutSessionId,
           runSessionID == activeSessionID {
            return runCoordinator.snapshot.phase.rawValue
        }

        if let gymSessionViewModel = activeWorkoutManager.gymSessionViewModel,
           gymSessionViewModel.session.id == activeSessionID {
            return gymSessionViewModel.summary == nil ? "active" : "ended"
        }

        return "unknown"
    }

    @ViewBuilder
    private func plusDestinationView(_ destination: PulsarPlusDestination) -> some View {
        switch destination {
        case .lab:
            LabView(profileStore: homeViewModel.profileStore, onClose: dismissPlusDestination)
        case .cycle:
            CycleView(onClose: dismissPlusDestination)
        }
    }

    @ViewBuilder
    private func presentedWorkoutView(_ workout: PulsarPresentedWorkout) -> some View {
        switch workout {
        case .run(let workoutKind):
            PulsarRunExperienceView(
                coordinator: runCoordinator,
                workoutKind: workoutKind,
                onMinimize: {
                    activeWorkoutManager.minimizeRunWorkout(
                        workoutKind,
                        sessionID: resolvedRunSessionIDForMiniWorkout(reason: "toolbarMinimize")
                    )
                }
            )
        case .gym:
            if let viewModel = activeWorkoutManager.gymSessionViewModel {
                GymWorkoutSessionView(
                    viewModel: viewModel,
                    onMinimize: {
                        activeWorkoutManager.minimizeGymWorkout(sessionID: viewModel.session.id)
                    },
                    onFinish: {
                        activeWorkoutManager.completeGymWorkout()
                    }
                )
            } else {
                Color.clear
                    .onAppear {
                        activeWorkoutManager.completeGymWorkout()
                    }
            }
        case .watchGym:
            GymWatchMirroredWorkoutView(syncStore: watchSyncStore) {
                activeWorkoutManager.minimizeWatchGymWorkout(sessionID: watchSyncStore.activeGymState?.sessionId)
            }
        }
    }
}

private extension PulsarRunPhase {
    var isActiveWorkoutPhase: Bool {
        switch self {
        case .running, .paused, .finishing, .connectingToWatch:
            true
        case .idle, .requestingPermissions, .countingDown, .finished, .failed:
            false
        }
    }

    var isTerminalActiveWorkoutClearPhase: Bool {
        switch self {
        case .finished, .failed:
            true
        case .idle, .requestingPermissions, .countingDown, .connectingToWatch, .running, .paused, .finishing:
            false
        }
    }
}

private extension PulsarActiveWorkoutSyncPhase {
    var isMiniBarDisplayable: Bool {
        switch self {
        case .starting, .active, .paused, .resumed, .ending:
            true
        case .ended, .failed, .cancelled:
            false
        }
    }

    var miniBarSubtitle: String {
        switch self {
        case .starting:
            "Connecting"
        case .active, .resumed:
            "Live workout"
        case .paused:
            "Paused"
        case .ending:
            "Finishing"
        case .ended:
            "Ended"
        case .failed:
            "Connection lost"
        case .cancelled:
            "Cancelled"
        }
    }
}

enum PulsarUIDebugLogger {
    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[PulsarUI] \(message())")
        #endif
    }
}

enum PulsarArchitectureDebugLogger {
    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[PulsarArchitecture] \(message())")
        #endif
    }
}

private struct PulsarWorkoutFailureNotice: Identifiable {
    let sessionID: UUID
    let message: String
    let wasCurrentSessionAtFailure: Bool

    var id: UUID { sessionID }
}

private struct PulsarTabBarMetrics: Equatable {
    var height: CGFloat = 0
    var width: CGFloat = 0
    var minX: CGFloat = 0
    var maxX: CGFloat = 0
    var minY: CGFloat = 0
    var maxY: CGFloat = 0
    var visibleHeight: CGFloat = 0
    var bottomSafeAreaInset: CGFloat = 0
    var isMinimized = false
    var isHidden = false
}

private struct PulsarTabBarMetricsReader: UIViewRepresentable {
    let onChange: (PulsarTabBarMetrics) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        DispatchQueue.main.async {
            context.coordinator.update(from: view)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.update(from: uiView)
        }
    }

    final class Coordinator {
        private let onChange: (PulsarTabBarMetrics) -> Void
        private var lastMetrics = PulsarTabBarMetrics()

        init(onChange: @escaping (PulsarTabBarMetrics) -> Void) {
            self.onChange = onChange
        }

        func update(from view: UIView) {
            guard let tabBar = view.enclosingViewController?.tabBarController?.tabBar
                    ?? view.window?.rootViewController?.pulsarVisibleTabBar else {
                publish(PulsarTabBarMetrics())
                return
            }

            let windowBounds = tabBar.window?.bounds ?? .zero
            let windowWidth = windowBounds.width
            let windowHeight = windowBounds.height
            let bottomSafeAreaInset = tabBar.window?.safeAreaInsets.bottom ?? 0
            let tabFrameInWindow = tabBar.superview?.convert(tabBar.frame, to: tabBar.window) ?? tabBar.frame
            let tabBarHeight = max(tabBar.bounds.height, tabFrameInWindow.height)
            let rawVisibleHeight = tabBar.isHidden || windowHeight <= 0 ? 0 : max(0, windowHeight - tabFrameInWindow.minY)
            let maximumChromeHeight = max(tabBarHeight + bottomSafeAreaInset + 20, 72)
            let visibleHeight = min(rawVisibleHeight, maximumChromeHeight)
            let isMinimized = !tabBar.isHidden
                && windowWidth > 0
                && tabFrameInWindow.width > 0
                && tabFrameInWindow.width < windowWidth * 0.72
            publish(
                PulsarTabBarMetrics(
                    height: tabBarHeight,
                    width: tabFrameInWindow.width,
                    minX: tabFrameInWindow.minX,
                    maxX: tabFrameInWindow.maxX,
                    minY: tabFrameInWindow.minY,
                    maxY: tabFrameInWindow.maxY,
                    visibleHeight: visibleHeight,
                    bottomSafeAreaInset: bottomSafeAreaInset,
                    isMinimized: isMinimized,
                    isHidden: tabBar.isHidden
                )
            )
        }

        private func publish(_ metrics: PulsarTabBarMetrics) {
            guard metrics != lastMetrics else { return }
            lastMetrics = metrics
            onChange(metrics)
        }
    }
}

private struct PulsarRootTabBackground: View {
    let tab: PulsarRootTab

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        switch tab {
        case .home:
            LinearGradient(
                colors: homeColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .fitness:
            FitnessWeeklyBackground()
        case .food, .mindfulness:
            PulsarSectionBackground()
        }
    }

    private var homeColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.06, green: 0.08, blue: 0.14),
                Color(red: 0.03, green: 0.05, blue: 0.10),
                Color(red: 0.01, green: 0.02, blue: 0.05)
            ]
        }

        return [
            Color(.systemBackground),
            Color(red: 0.95, green: 0.97, blue: 1.00),
            Color(.secondarySystemBackground)
        ]
    }
}

private extension UIViewController {
    var pulsarVisibleTabBar: UITabBar? {
        if let tabBarController = self as? UITabBarController {
            return tabBarController.tabBar
        }

        for child in children {
            if let tabBar = child.pulsarVisibleTabBar {
                return tabBar
            }
        }

        return presentedViewController?.pulsarVisibleTabBar
    }
}

private extension UIView {
    var enclosingViewController: UIViewController? {
        var responder: UIResponder? = self
        while let currentResponder = responder {
            if let viewController = currentResponder as? UIViewController {
                return viewController
            }
            responder = currentResponder.next
        }
        return nil
    }
}

private enum PulsarRootTab: String, Hashable, CaseIterable {
    case home
    case fitness
    case food
    case mindfulness

    var title: String {
        switch self {
        case .home: "Home"
        case .fitness: "Fitness"
        case .food: "Food"
        case .mindfulness: "Mindfulness"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .fitness: "figure.run"
        case .food: "leaf"
        case .mindfulness: "figure.mind.and.body"
        }
    }

    var tabBarTag: Int {
        switch self {
        case .home: 0
        case .fitness: 1
        case .food: 2
        case .mindfulness: 3
        }
    }

    var identifier: String {
        "pulsar.root.\(rawValue)"
    }

    init?(tabBarTag: Int) {
        switch tabBarTag {
        case 0: self = .home
        case 1: self = .fitness
        case 2: self = .food
        case 3: self = .mindfulness
        default: return nil
        }
    }

    init?(identifier: String) {
        guard identifier.hasPrefix("pulsar.root.") else { return nil }
        self.init(rawValue: String(identifier.dropFirst("pulsar.root.".count)))
    }
}

private enum PulsarPlusDestination: String, Identifiable {
    case lab
    case cycle

    var id: String { rawValue }
}

private struct PulsarNativeTabController: UIViewControllerRepresentable {
    @Binding var selectedTab: PulsarRootTab

    let homeViewModel: HomeViewModel
    let activeWorkoutManager: PulsarActiveWorkoutManager
    let runCoordinator: PulsarRunCoordinator
    let onOpenDestination: (PulsarPlusDestination) -> Void
    let onMetricsChange: (PulsarTabBarMetrics) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            selectedTab: $selectedTab,
            onOpenDestination: onOpenDestination,
            onMetricsChange: onMetricsChange
        )
    }

    func makeUIViewController(context: Context) -> PulsarNativeTabBarController {
        let controller = PulsarNativeTabBarController()
        context.coordinator.configure(controller)
        controller.installTabs(nativeTabs, selectedRootTab: selectedTab)
        return controller
    }

    func updateUIViewController(_ uiViewController: PulsarNativeTabBarController, context: Context) {
        context.coordinator.selectedTab = $selectedTab
        context.coordinator.onOpenDestination = onOpenDestination
        context.coordinator.onMetricsChange = onMetricsChange
        context.coordinator.configure(uiViewController)

        if !uiViewController.hasExpectedRootTabs(PulsarRootTab.allCases.map(\.identifier)) {
            uiViewController.installTabs(nativeTabs, selectedRootTab: selectedTab)
        }
        uiViewController.selectRootTab(selectedTab)
    }

    private var nativeTabs: [UITab] {
        var tabs = PulsarRootTab.allCases.map { nativeTab(for: $0) }
        tabs.append(plusActionTab())
        return tabs
    }

    private func nativeTab(for tab: PulsarRootTab) -> UITab {
        let nativeTab = UITab(
            title: tab.title,
            image: UIImage(systemName: tab.symbol),
            identifier: tab.identifier
        ) { _ in
            hostingController(for: tab)
        }
        nativeTab.preferredPlacement = .fixed
        nativeTab.allowsHiding = false
        return nativeTab
    }

    private func plusActionTab() -> UISearchTab {
        let tab = UISearchTab { _ in
            UIViewController()
        }
        tab.title = ""
        tab.image = UIImage(systemName: "plus")
        tab.preferredPlacement = .pinned
        tab.allowsHiding = false
        tab.automaticallyActivatesSearch = false
        tab.userInfo = PulsarNativeTabBarController.plusActionUserInfo
        tab.accessibilityIdentifier = "pulsar.plus.action"
        return tab
    }

    private func hostingController(for tab: PulsarRootTab) -> UIViewController {
        let controller = UIHostingController(rootView: rootView(for: tab))
        controller.title = tab.title
        controller.view.backgroundColor = .clear
        controller.view.isOpaque = false
        controller.edgesForExtendedLayout = [.top, .bottom]
        controller.extendedLayoutIncludesOpaqueBars = true
        return controller
    }

    @ViewBuilder
    private func rootView(for tab: PulsarRootTab) -> some View {
        switch tab {
        case .home:
            HomeView(viewModel: homeViewModel)
                .environmentObject(activeWorkoutManager)
                .environmentObject(runCoordinator)
        case .fitness:
            FitnessView(profileStore: homeViewModel.profileStore)
                .environmentObject(activeWorkoutManager)
                .environmentObject(runCoordinator)
        case .food:
            FoodView()
                .environmentObject(activeWorkoutManager)
                .environmentObject(runCoordinator)
        case .mindfulness:
            InsightsView()
                .environmentObject(activeWorkoutManager)
                .environmentObject(runCoordinator)
        }
    }

    final class Coordinator {
        var selectedTab: Binding<PulsarRootTab>
        var onOpenDestination: (PulsarPlusDestination) -> Void
        var onMetricsChange: (PulsarTabBarMetrics) -> Void

        init(
            selectedTab: Binding<PulsarRootTab>,
            onOpenDestination: @escaping (PulsarPlusDestination) -> Void,
            onMetricsChange: @escaping (PulsarTabBarMetrics) -> Void
        ) {
            self.selectedTab = selectedTab
            self.onOpenDestination = onOpenDestination
            self.onMetricsChange = onMetricsChange
        }

        func configure(_ controller: PulsarNativeTabBarController) {
            controller.onTabSelected = { [weak self] tab in
                self?.selectedTab.wrappedValue = tab
            }
            controller.onOpenDestination = { [weak self] destination in
                self?.onOpenDestination(destination)
            }
            controller.onMetricsChange = { [weak self] metrics in
                self?.onMetricsChange(metrics)
            }
        }
    }
}

private final class PulsarNativeTabBarController: UITabBarController, UITabBarControllerDelegate, UIEditMenuInteractionDelegate {
    static let plusActionUserInfo = "pulsar.plus.action"

    var onTabSelected: ((PulsarRootTab) -> Void)?
    var onOpenDestination: ((PulsarPlusDestination) -> Void)?
    var onMetricsChange: ((PulsarTabBarMetrics) -> Void)?

    private var lastSelectedRootTab: PulsarRootTab = .home
    private lazy var plusMenuInteraction = UIEditMenuInteraction(delegate: self)
    private var plusMenuTargetRect: CGRect = .null
    private var lastMetrics = PulsarTabBarMetrics()

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        view.backgroundColor = .clear
        view.isOpaque = false
        mode = .tabBar
        tabBarMinimizeBehavior = .onScrollDown
        tabBar.isTranslucent = true
        view.addInteraction(plusMenuInteraction)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        reportMetrics(for: tabBar.frame)
    }

    func installTabs(_ tabs: [UITab], selectedRootTab: PulsarRootTab) {
        self.tabs = tabs
        compactTabIdentifiers = nil
        selectRootTab(selectedRootTab)
    }

    func hasExpectedRootTabs(_ identifiers: [String]) -> Bool {
        let installedRootIdentifiers = tabs
            .filter { !isPlusActionTab($0) }
            .map(\.identifier)
        return installedRootIdentifiers == identifiers && tabs.contains(where: isPlusActionTab)
    }

    func selectRootTab(_ rootTab: PulsarRootTab) {
        lastSelectedRootTab = rootTab
        guard selectedTab?.identifier != rootTab.identifier,
              let tab = tab(forIdentifier: rootTab.identifier) else { return }
        selectedTab = tab
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
        guard isPlusActionTab(tab) else { return true }
        presentPlusMenu(from: tab)
        selectRootTab(lastSelectedRootTab)
        return false
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelectTab selectedTab: UITab, previousTab: UITab?) {
        guard let selectedRootTab = PulsarRootTab(identifier: selectedTab.identifier) else { return }
        lastSelectedRootTab = selectedRootTab
        onTabSelected?(selectedRootTab)
    }

    private func isPlusActionTab(_ tab: UITab) -> Bool {
        (tab.userInfo as? String) == Self.plusActionUserInfo
    }

    private func presentPlusMenu(from tab: UITab) {
        plusMenuTargetRect = plusTargetRect(for: tab)
        let configuration = UIEditMenuConfiguration(
            identifier: Self.plusActionUserInfo,
            sourcePoint: CGPoint(x: plusMenuTargetRect.midX, y: plusMenuTargetRect.minY)
        )
        configuration.preferredArrowDirection = .down
        plusMenuInteraction.presentEditMenu(with: configuration)
    }

    private func plusTargetRect(for tab: UITab) -> CGRect {
        guard isPlusActionTab(tab) else { return .null }
        let tabBarFrame = tabBar.convert(tabBar.bounds, to: view)
        let sideLength = min(72, max(48, tabBarFrame.height))
        let horizontalInset = max(0, (tabBarFrame.height - sideLength) / 2)
        return CGRect(
            x: tabBarFrame.maxX - sideLength - horizontalInset,
            y: tabBarFrame.midY - sideLength / 2,
            width: sideLength,
            height: sideLength
        )
    }

    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        menuFor configuration: UIEditMenuConfiguration,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        let menu = UIMenu(children: [
            UIAction(title: "Lab", image: UIImage(systemName: "testtube.2")) { [weak self] _ in
                self?.openPlusDestination(.lab)
            },
            UIAction(title: "Cycle", image: UIImage(systemName: "moonphase.first.quarter") ?? UIImage(systemName: "calendar")) { [weak self] _ in
                self?.openPlusDestination(.cycle)
            }
        ])
        menu.preferredElementSize = .large
        return menu
    }

    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        targetRectFor configuration: UIEditMenuConfiguration
    ) -> CGRect {
        plusMenuTargetRect
    }

    private func openPlusDestination(_ destination: PulsarPlusDestination) {
        selectRootTab(lastSelectedRootTab)
        onOpenDestination?(destination)
    }

    private func reportMetrics(for controlsFrame: CGRect) {
        guard let window = view.window else { return }
        let frameInWindow = view.convert(controlsFrame, to: window)
        let windowBounds = window.bounds
        let visibleHeight = max(0, windowBounds.height - frameInWindow.minY)
        let metrics = PulsarTabBarMetrics(
            height: controlsFrame.height,
            width: controlsFrame.width,
            minX: frameInWindow.minX,
            maxX: frameInWindow.maxX,
            minY: frameInWindow.minY,
            maxY: frameInWindow.maxY,
            visibleHeight: visibleHeight,
            bottomSafeAreaInset: window.safeAreaInsets.bottom,
            isMinimized: frameInWindow.width > 0 && frameInWindow.width < windowBounds.width * 0.72,
            isHidden: false
        )
        guard metrics != lastMetrics else { return }
        lastMetrics = metrics
        onMetricsChange?(metrics)
    }
}

private struct PulsarWorkoutMiniPlayerState: Equatable {
    enum Kind: Equatable {
        case run(PulsarOutdoorWorkoutKind)
        case gym
        case watchGym
    }

    let id: String
    let sessionID: UUID
    let kind: Kind
    let title: String
    let subtitle: String
    let metrics: String
    let detail: String
    let symbol: String
    let isPaused: Bool
}

private struct PulsarMiniWorkoutBarHost: View {
    let state: PulsarWorkoutMiniPlayerState
    let isInlinePlacement: Bool
    let placement: String
    let onOpen: () -> Void
    let onPrimaryAction: () -> Void

    var body: some View {
        miniBarContent
    }

    private var miniBarContent: some View {
        PulsarNativeWorkoutMiniBar(
            state: state,
            isInlinePlacement: isInlinePlacement,
            onOpen: onOpen,
            onPrimaryAction: onPrimaryAction
        )
        .padding(.horizontal, isInlinePlacement ? 6 : 0)
        .padding(.vertical, isInlinePlacement ? 2 : 0)
        .frame(height: isInlinePlacement ? 48 : 60)
        .frame(minWidth: 1, maxWidth: .infinity)
        .background(PulsarMiniWorkoutFrameReporter(sessionID: state.sessionID, placement: placement))
        .accessibilitySortPriority(10)
    }
}

private struct PulsarMiniWorkoutFrameReporter: View {
    let sessionID: UUID
    let placement: String
    @State private var lastLoggedFrameKey = ""

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    logFrame(proxy)
                }
                .onChange(of: proxy.size) { _, _ in
                    logFrame(proxy)
                }
                .onChange(of: proxy.frame(in: .global).minY) { _, _ in
                    logFrame(proxy)
                }
        }
        .allowsHitTesting(false)
    }

    private func logFrame(_ proxy: GeometryProxy) {
        let frame = proxy.frame(in: .global)
        guard frame.width > 0,
              frame.height > 0,
              frame.minY >= 0 else { return }
        let key = "\(Int(frame.width))x\(Int(frame.height))@\(Int(frame.minY))"
        guard key != lastLoggedFrameKey else { return }
        lastLoggedFrameKey = key
        PulsarUIDebugLogger.log("MiniWorkoutHost rendered frame=\(Int(frame.width))x\(Int(frame.height)) y=\(Int(frame.minY)) session=\(sessionID.uuidString) placement=\(placement)")
    }
}

private struct PulsarNativeWorkoutMiniBar: View {
    @Environment(\.colorScheme) private var colorScheme

    let state: PulsarWorkoutMiniPlayerState
    let isInlinePlacement: Bool
    let onOpen: () -> Void
    let onPrimaryAction: () -> Void

    var body: some View {
        HStack(spacing: isInlinePlacement ? 9 : 11) {
            workoutGlyph
                .frame(width: isInlinePlacement ? 36 : 44, height: isInlinePlacement ? 36 : 44)

            VStack(alignment: .leading, spacing: isInlinePlacement ? 1 : 2) {
                Text(state.title)
                    .font(.system(size: isInlinePlacement ? 15 : 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(isInlinePlacement ? state.metrics : "\(state.subtitle) • \(state.metrics)")
                    .font(.system(size: isInlinePlacement ? 13 : 14, weight: .regular, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .layoutPriority(1)

            Button(action: onPrimaryAction) {
                Image(systemName: primaryActionSymbol)
                    .font(.system(size: isInlinePlacement ? 18 : 24, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: isInlinePlacement ? 36 : 44, height: isInlinePlacement ? 36 : 44)
                    .modifier(PulsarMiniWorkoutControlModifier(isInlinePlacement: isInlinePlacement))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(primaryActionLabel)
        }
        .padding(.leading, isInlinePlacement ? 8 : 10)
        .padding(.trailing, isInlinePlacement ? 9 : 10)
        .frame(minWidth: 1, maxWidth: .infinity)
        .frame(height: isInlinePlacement ? 50 : 60)
        .contentShape(.rect(cornerRadius: barCornerRadius))
        .modifier(PulsarMiniWorkoutBarBackgroundModifier(
            tint: tint,
            cornerRadius: barCornerRadius,
            isInlinePlacement: isInlinePlacement
        ))
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text("Open live workout"), onOpen)
    }

    private var workoutGlyph: some View {
        Image(systemName: state.symbol)
            .font(.system(size: isInlinePlacement ? 16 : 18, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tileFill, in: .rect(cornerRadius: isInlinePlacement ? 14 : 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: isInlinePlacement ? 14 : 13, style: .continuous)
                    .stroke(tileStroke, lineWidth: 1)
            }
    }

    private var tileFill: some ShapeStyle {
        LinearGradient(
            colors: [
                tint.opacity(colorScheme == .dark ? 0.34 : 0.22),
                tint.opacity(colorScheme == .dark ? 0.20 : 0.14),
                Color.white.opacity(colorScheme == .dark ? 0.03 : 0.18)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var tileStroke: some ShapeStyle {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.24 : 0.58),
                tint.opacity(colorScheme == .dark ? 0.22 : 0.18)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var barCornerRadius: CGFloat {
        isInlinePlacement ? 25 : 30
    }

    private var tint: Color {
        switch state.kind {
        case .run(let workoutKind):
            workoutKind.accentColor
        case .gym:
            Color(red: 0.72, green: 0.66, blue: 1.0)
        case .watchGym:
            Color(red: 0.48, green: 0.84, blue: 1.0)
        }
    }

    private var primaryActionSymbol: String {
        switch state.kind {
        case .run:
            state.isPaused ? "play.fill" : "pause.fill"
        case .gym, .watchGym:
            "chevron.up"
        }
    }

    private var primaryActionLabel: String {
        switch state.kind {
        case .run:
            state.isPaused ? "Resume workout" : "Pause workout"
        case .gym, .watchGym:
            "Open workout"
        }
    }
}

private struct PulsarMiniWorkoutBarBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let tint: Color
    let cornerRadius: CGFloat
    let isInlinePlacement: Bool

    func body(content: Content) -> some View {
        if isInlinePlacement {
            inlineBackground(content)
        } else {
            dockBackground(content)
        }
    }

    @ViewBuilder
    private func inlineBackground(_ content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .background(inlineSurfaceFill, in: .rect(cornerRadius: cornerRadius, style: .continuous))
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius, style: .continuous))
                .overlay(alignment: .topLeading) {
                    Capsule(style: .continuous)
                        .fill(.white.opacity(colorScheme == .dark ? 0.10 : 0.34))
                        .frame(width: 46, height: 7)
                        .blur(radius: 5)
                        .offset(x: 13, y: 7)
                        .allowsHitTesting(false)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(inlineStroke, lineWidth: 1)
                }
                .shadow(color: tint.opacity(colorScheme == .dark ? 0.20 : 0.12), radius: 10, x: 0, y: 5)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.10), radius: 13, x: 0, y: 7)
        } else {
            content
                .background(inlineSurfaceFill, in: .rect(cornerRadius: cornerRadius, style: .continuous))
                .background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(inlineStroke, lineWidth: 1)
                }
                .shadow(color: tint.opacity(colorScheme == .dark ? 0.18 : 0.10), radius: 10, x: 0, y: 5)
                .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)
        }
    }

    @ViewBuilder
    private func dockBackground(_ content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .background(dockSurfaceFill, in: .rect(cornerRadius: cornerRadius, style: .continuous))
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius, style: .continuous))
                .overlay(alignment: .topLeading) {
                    Capsule(style: .continuous)
                        .fill(.white.opacity(colorScheme == .dark ? 0.07 : 0.24))
                        .frame(width: 56, height: 7)
                        .blur(radius: 6)
                        .offset(x: 18, y: 8)
                        .allowsHitTesting(false)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(dockStroke, lineWidth: 1)
                }
                .shadow(color: tint.opacity(colorScheme == .dark ? 0.14 : 0.07), radius: 10, x: 0, y: 5)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.20 : 0.08), radius: 14, x: 0, y: 8)
        } else {
            content
                .background(dockSurfaceFill, in: .rect(cornerRadius: cornerRadius, style: .continuous))
                .background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(dockStroke, lineWidth: 1)
                }
                .shadow(color: tint.opacity(colorScheme == .dark ? 0.12 : 0.06), radius: 10, x: 0, y: 5)
                .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 8)
        }
    }

    private var inlineSurfaceFill: some ShapeStyle {
        LinearGradient(
            colors: [
                Color(uiColor: .systemBackground).opacity(colorScheme == .dark ? 0.54 : 0.78),
                Color(uiColor: .secondarySystemBackground).opacity(colorScheme == .dark ? 0.46 : 0.66),
                tint.opacity(colorScheme == .dark ? 0.20 : 0.15)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var dockSurfaceFill: some ShapeStyle {
        LinearGradient(
            colors: [
                tint.opacity(colorScheme == .dark ? 0.18 : 0.16),
                Color(uiColor: .systemBackground).opacity(colorScheme == .dark ? 0.54 : 0.72),
                Color(uiColor: .secondarySystemBackground).opacity(colorScheme == .dark ? 0.48 : 0.62)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var inlineStroke: some ShapeStyle {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.22 : 0.64),
                tint.opacity(colorScheme == .dark ? 0.16 : 0.13),
                Color.black.opacity(colorScheme == .dark ? 0.12 : 0.04)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var dockStroke: some ShapeStyle {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.24 : 0.68),
                Color.white.opacity(colorScheme == .dark ? 0.08 : 0.22),
                tint.opacity(colorScheme == .dark ? 0.16 : 0.12)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct PulsarMiniWorkoutControlModifier: ViewModifier {
    let isInlinePlacement: Bool

    func body(content: Content) -> some View {
        content
            .contentShape(.rect(cornerRadius: isInlinePlacement ? 18 : 26, style: .continuous))
            .symbolRenderingMode(.monochrome)
    }
}

#Preview {
    PulsarRootView()
}
