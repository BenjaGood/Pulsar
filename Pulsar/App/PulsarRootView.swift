//
//  PulsarRootView.swift
//  Pulsar
//

import SwiftUI
import Combine
import UIKit

struct PulsarRootView: View {
    @State private var selectedTab: PulsarRootTab = .home
    @State private var tabBarMetrics = PulsarTabBarMetrics()
    @State private var lastVisibleTabBarHeight: CGFloat = 0
    @State private var workoutFailureNotice: PulsarWorkoutFailureNotice?
    @State private var lastFailedWorkoutSessionID: UUID?
    @State private var ignoredFailedSessionIDs = Set<UUID>()
    @State private var presentedPlusDestination: PulsarPlusDestination?
    @State private var isOrionChatPresented = false
    @State private var isPlusMenuMounted = false
    @State private var isPlusMenuExpanded = false
    @State private var plusMenuAnchorMetrics: PulsarTabBarMetrics?
    @StateObject private var homeViewModel = HomeViewModel()
    @StateObject private var homeBackgroundSettings = HomeBackgroundSettingsStore()
    @StateObject private var nutritionStore = PulsarNutritionStore()
    @StateObject private var mindfulnessStore = PulsarMindfulnessStore()
    @StateObject private var mindfulnessRouter = PulsarMindfulnessRouter()
    @StateObject private var deepLinkRouter = PulsarDeepLinkRouter.shared
    @StateObject private var workoutServices = PulsarRootWorkoutServices()
    private let activeWorkoutManager = PulsarActiveWorkoutManager.shared
    @StateObject private var completionPresentationStore = WorkoutCompletionPresentationStore()
    private let workoutLifecycle = PulsarWorkoutStartCoordinator.shared
    @StateObject private var orionChatViewModel = OrionChatViewModel()
    @StateObject private var orionAudioManager = OrionAudioManager()
    @StateObject private var bottomChromeLayoutStore = PulsarBottomChromeLayoutStore()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let root = rootShellWithLifecycle
        let _ = PulsarPerformanceSignposts.markRootInitialized()
        let _ = PulsarPerformanceDiagnostics.event("root.body")
        let _ = PulsarWorkoutStartupTrace.count("[RenderRate] PulsarRootView")
        root
    }

    private var runCoordinator: PulsarRunCoordinator {
        workoutServices.runCoordinator
    }

    private var watchSyncStore: PulsarWatchConnectivitySyncStore {
        workoutServices.watchSyncStore
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
            .font(PulsarTypography.Role.appBody.font)
            .alert(item: workoutFailureNoticeBinding) { notice in
                Alert(
                    title: Text("Workout connection lost"),
                    message: Text(notice.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .overlay(alignment: .topLeading) {
                PulsarRootWorkoutPresentationHost(
                    manager: activeWorkoutManager,
                    onDismiss: handleWorkoutPresentationDismissed
                ) { item in
                    presentedWorkoutView(item)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                        .presentationBackground(.regularMaterial)
                        .interactiveDismissDisabled(
                            shouldDisableWorkoutInteractiveDismiss(item.workout)
                        )
                }
            }
            .overlay {
                PulsarWorkoutLifecyclePhaseObserver(
                    coordinator: workoutLifecycle,
                    onPhaseChange: handleWorkoutLifecyclePhaseChanged
                )
            }
            .overlay {
                PulsarRootWorkoutChromeObservationProbe(
                    manager: activeWorkoutManager,
                    selectedTab: selectedTab,
                    onChange: handleWorkoutChromeObservationChange
                )
            }
            .fullScreenCover(item: $presentedPlusDestination) { destination in
                plusDestinationView(destination)
            }
            .fullScreenCover(isPresented: $isOrionChatPresented) {
                OrionChatView(viewModel: orionChatViewModel)
                    .presentationBackground(.clear)
                    .onAppear {
                        orionAudioManager.setPresentationActive(true)
                    }
                    .onDisappear {
                        orionAudioManager.setPresentationActive(false)
                    }
            }
    }

    private var rootShellWithWorkoutEventSubscriptions: some View {
        rootShellWithPresentation
            .onReceive(runCoordinator.$snapshot.map(\.phase).removeDuplicates()) { newPhase in
                handleRunPhaseChanged(newPhase)
            }
            .onReceive(runCoordinator.$summary.map { $0?.id }.removeDuplicates()) { _ in
                presentRunSummaryIfAvailable(source: "runSummaryChanged")
            }
            .onReceive(runCoordinator.$snapshot) { _ in
                cacheActiveWorkoutDisplayStateIfAvailable(reason: "runSnapshotChanged")
            }
            .onReceive(watchSyncStore.$activeWorkoutState.removeDuplicates()) { state in
                guard state?.phase != .failed else { return }
                let source = activeWorkoutSyncSource(for: state, fallback: "activeWorkoutSyncChanged")
                guard shouldApplyLiveActiveWorkoutSyncUpdate(state, source: source) else {
                    if let state, case .gym = state.kind {
                        PulsarSyncDebugLogger.log(
                            "Ignored unverified live gym publication without invoking restoration cleanup source=\(source) session=\(state.sessionId.uuidString) inFlight=\(workoutLifecycle.matchesCurrentInFlightSession(state.sessionId))"
                        )
                    }
                    return
                }
                applyActiveWorkoutSyncUpdate(state, source: source)
                cacheActiveWorkoutDisplayStateIfAvailable(reason: "activeWorkoutSyncChanged")
            }
            .onReceive(activeFinishedGymPublisher) { state in
                presentFinishedWatchGymSummaryIfNeeded(state, source: "activeGymStateChanged")
            }
            .onReceive(finishedGymPublisher) { state in
                presentFinishedWatchGymSummaryIfNeeded(state, source: "lastFinishedGymStateChanged")
            }
            .onReceive(watchSyncStore.$lastActiveWorkoutUpdateEvent.compactMap { $0 }) { event in
                guard event.state.phase == .failed || event.state.isEnded else { return }
                handleActiveWorkoutUpdateDecision(event.decision, state: event.state, source: event.source)
            }
            .onReceive(watchSyncStore.$lastConfirmedGymFinish.compactMap { $0 }.removeDuplicates()) { confirmation in
                handleConfirmedGymFinish(confirmation)
            }
    }

    private var activeFinishedGymPublisher: AnyPublisher<ActiveGymWorkoutState, Never> {
        watchSyncStore.$activeGymState
            .compactMap { state in state?.isFinished == true ? state : nil }
            .removeDuplicates { $0.sessionId == $1.sessionId }
            .eraseToAnyPublisher()
    }

    private var finishedGymPublisher: AnyPublisher<ActiveGymWorkoutState, Never> {
        watchSyncStore.$lastFinishedGymState
            .compactMap { $0 }
            .removeDuplicates { $0.sessionId == $1.sessionId }
            .eraseToAnyPublisher()
    }

    private var rootShellWithLifecycle: some View {
        rootShellWithWorkoutEventSubscriptions
            .task {
                let restorationSnapshot = makeRestoredWorkoutReconciliationSnapshot()
                syncCurrentActiveWorkoutSessionContext(reason: "rootTask")
                await homeViewModel.requestInitialAppEntrySync()
                syncAdaptiveStrainGuardPlan(reason: "rootTask")
                await syncDailyRewindReminder()
                syncSavedGymRoutinesToWatch(reason: "rootTask")
                watchSyncStore.pruneStaleActiveWorkoutState(reason: "rootTask")
                await GymLiveActivityManager.endStaleActivitiesIfNeeded(activeState: watchSyncStore.activeGymState)
                await reconcileRestoredActiveWorkoutOnAppEntry(
                    restorationSnapshot,
                    source: "rootTask"
                )
            }
            .onChange(of: selectedTab) { _, selectedTab in
                PulsarPerformanceSignposts.markTabRootSelectionObserved(selectedTab.performanceTab)
                guard let wallpaperToken = PulsarPerformanceSignposts.beginTabWallpaperTransition(
                    to: selectedTab.performanceTab
                ) else { return }
                Task { @MainActor in
                    await Task.yield()
                    PulsarPerformanceSignposts.markTabWallpaperDisplayed(wallpaperToken)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                orionAudioManager.setAppIsActive(newPhase == .active)
                let deferred = PulsarWorkoutStartCoordinator.shared.shouldDeferForegroundHealthRefresh
                PulsarWorkoutStartupTrace.lifecycle("scenePhase \(String(describing: newPhase))")
                PulsarWorkoutStartupTrace.diag(
                    "[Scene] scenePhase=\(String(describing: newPhase)) deferred=\(deferred) lifecycle=\(workoutLifecycle.phase.name) \(PulsarWorkoutStartupTrace.threadTag())"
                )
                guard newPhase == .active else {
                    homeViewModel.appDidResignActive()
                    return
                }
                Task {
                    let restorationSnapshot = makeRestoredWorkoutReconciliationSnapshot()
                    let perfToken = PulsarPerformanceDiagnostics.begin("app.activation")
                    defer { PulsarPerformanceDiagnostics.end(perfToken) }
                    await homeViewModel.appDidBecomeActive()
                    if PulsarWorkoutStartCoordinator.shared.shouldDeferForegroundHealthRefresh {
                        PulsarOuraLogger.log("sceneBecameActive work deferred; Watch start in progress")
                        PulsarWorkoutStartupTrace.diag(
                            "[ForegroundRefresh] sceneTask deferred=true lifecycle=\(PulsarWorkoutStartCoordinator.shared.phase.name) \(PulsarWorkoutStartupTrace.threadTag())"
                        )
                        return
                    }
                    PulsarWorkoutStartupTrace.diag(
                        "[ForegroundRefresh] sceneTask deferred=false startingExtraWork lifecycle=\(PulsarWorkoutStartCoordinator.shared.phase.name) \(PulsarWorkoutStartupTrace.threadTag())"
                    )
                    syncAdaptiveStrainGuardPlan(reason: "sceneBecameActive")
                    mindfulnessStore.reload()
                    await syncDailyRewindReminder()
                    syncSavedGymRoutinesToWatch(reason: "sceneBecameActive")
                    watchSyncStore.pruneStaleActiveWorkoutState(reason: "sceneBecameActive")
                    await GymLiveActivityManager.endStaleActivitiesIfNeeded(activeState: watchSyncStore.activeGymState)
                    await reconcileRestoredActiveWorkoutOnAppEntry(
                        restorationSnapshot,
                        source: "sceneBecameActive"
                    )
                    PulsarWorkoutStartupTrace.diag(
                        "[ForegroundRefresh] sceneTask extraWorkReturned lifecycle=\(PulsarWorkoutStartCoordinator.shared.phase.name) \(PulsarWorkoutStartupTrace.threadTag())"
                    )
                }
            }
            .onChange(of: homeViewModel.dashboard) { _, _ in
                syncAdaptiveStrainGuardPlan(reason: "homeDashboardChanged")
            }
            .onReceive(deepLinkRouter.$pendingRoute.compactMap { $0 }) { route in
                handleDeepLinkRoute(route)
            }
            .onReceive(IntelligentNotificationPreferencesStore.shared.$preferences) { _ in
                Task {
                    await syncDailyRewindReminder()
                }
            }
            .onOpenURL { url in
                deepLinkRouter.open(url)
            }
            .onAppear {
                PulsarPerformanceDiagnostics.startMainActorStallMonitor()
                PulsarPerformanceDiagnostics.instanceMounted("root")
                configureOrion()
                orionAudioManager.bind(to: orionChatViewModel)
                orionAudioManager.setAppIsActive(scenePhase == .active)
                syncCurrentActiveWorkoutSessionContext(reason: "rootAppear")
                handlePendingDeepLinkRouteIfNeeded()
                PulsarArchitectureDebugLogger.log("Using MiniWorkoutHost placement=\(miniWorkoutPlacementDescription)")
                PulsarUIDebugLogger.log("MiniWorkoutHost mounted at root")
                activeWorkoutManager.reconcilePresentationIntegrity(reason: "rootAppear")
                cacheActiveWorkoutDisplayStateIfAvailable(reason: "rootAppear")
                logMiniWorkoutVisibility()
            }
            .onDisappear {
                PulsarPerformanceDiagnostics.instanceUnmounted("root")
            }
    }

    private func configureOrion() {
        orionChatViewModel.configure(
            service: OrionService(configuration: .load()),
            contextProvider: OrionContextProvider(
                homeViewModel: homeViewModel,
                nutritionStore: nutritionStore
            )
        )
    }

    private func syncSavedGymRoutinesToWatch(reason: String) {
        PulsarRoutineStore.shared.syncRoutinesToWatch(reason: reason, broadcast: true)
    }

    private func handlePendingDeepLinkRouteIfNeeded() {
        guard let route = deepLinkRouter.pendingRoute else { return }
        handleDeepLinkRoute(route)
    }

    private func handleDeepLinkRoute(_ route: PulsarDeepLinkRoute) {
        switch route {
        case .mindfulnessDailyRewind(let dateKey):
            dismissPlusMenu()
            selectedTab = .mindfulness
            mindfulnessRouter.presentDailyRewind(dateKey: dateKey, source: .notification)
            deepLinkRouter.consume(route)
        }
    }

    private func syncDailyRewindReminder() async {
        await DailyRewindNotificationScheduler.shared.syncReminder(
            journalCompletedToday: mindfulnessStore.hasEntry(on: Date())
        )
    }

    private func syncAdaptiveStrainGuardPlan(reason: String) {
        let plan = homeViewModel.adaptiveStrainPlan()
        runCoordinator.setAdaptiveStrainPlan(plan, reason: reason)
        activeWorkoutManager.setAdaptiveStrainPlan(plan, reason: reason)
    }

    private func handleWorkoutChromeObservationChange(
        from previous: PulsarRootWorkoutChromeObservation,
        to current: PulsarRootWorkoutChromeObservation
    ) {
        if previous.shouldShowMiniWorkoutBar != current.shouldShowMiniWorkoutBar {
            cacheActiveWorkoutDisplayStateIfAvailable(reason: "miniBarVisibilityChanged")
            logMiniWorkoutVisibility()
            if current.shouldShowMiniWorkoutBar, let sessionID = current.activeSessionID {
                PulsarUIDebugLogger.log("MiniWorkout visible session=\(sessionID.uuidString) placement=\(miniWorkoutPlacementDescription)")
            }
        }

        if previous.presentation != current.presentation {
            cacheActiveWorkoutDisplayStateIfAvailable(reason: "presentationChanged")
            logMiniWorkoutVisibility()
        }

        if previous.activeSessionID != current.activeSessionID {
            if current.activeSessionID != nil {
                isOrionChatPresented = false
            }
            syncCurrentActiveWorkoutSessionContext(reason: "activeWorkoutChanged")
            pruneLastKnownWorkoutDisplayStates()
            cacheActiveWorkoutDisplayStateIfAvailable(reason: "activeWorkoutChanged")
            logMiniWorkoutVisibility()
        }

        if previous.selectedTab != current.selectedTab {
            logMiniWorkoutVisibility()
        }
    }

    private var rootShell: some View {
        ZStack(alignment: .bottom) {
            PulsarRootLiveChromeObserver(
                activeWorkoutManager: activeWorkoutManager,
                runCoordinator: runCoordinator,
                watchSyncStore: watchSyncStore,
                tabBarMetrics: tabBarMetrics,
                displayScale: displayScale,
                bottomChromeLayoutStore: bottomChromeLayoutStore,
                makeMiniPlayerState: visibleActiveWorkoutMiniPlayerState
            ) { miniPlayerState, showsOrion, layoutController in
                ZStack(alignment: .bottom) {
                    nativeTabs(
                        activeWorkoutMiniPlayerState: miniPlayerState,
                        showsOrionAccessory: showsOrion && usesNativeOrionTabAccessory
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(edges: [.top, .bottom])

                    rootMiniWorkoutHost(
                        state: miniPlayerState,
                        layoutController: layoutController
                    )
                    rootOrionHost(showsOrion: showsOrion)
                }
            }

            if isPlusMenuMounted {
                PulsarPlusMorphingMenu(
                    isExpanded: isPlusMenuExpanded,
                    tabBarMetrics: plusMenuAnchorMetrics ?? tabBarMetrics,
                    onOpenDestination: openPlusDestination,
                    onToggle: togglePlusMenu,
                    onDismiss: dismissPlusMenu
                )
                .zIndex(1000)
            }
        }
        .overlay(alignment: .top) {
            rootSyncStatusHost
                .allowsHitTesting(false)
        }
    }

    private func nativeTabs(
        activeWorkoutMiniPlayerState: PulsarWorkoutMiniPlayerState?,
        showsOrionAccessory: Bool
    ) -> some View {
        PulsarNativeTabController(
            selectedTab: $selectedTab,
            homeViewModel: homeViewModel,
            homeBackgroundSettings: homeBackgroundSettings,
            nutritionStore: nutritionStore,
            activeWorkoutManager: activeWorkoutManager,
            runCoordinator: runCoordinator,
            completionPresentationStore: completionPresentationStore,
            mindfulnessStore: mindfulnessStore,
            mindfulnessRouter: mindfulnessRouter,
            isPlusActionHidden: isPlusMenuMounted,
            isPlusMenuMounted: $isPlusMenuMounted,
            isPlusMenuExpanded: $isPlusMenuExpanded,
            plusMenuAnchorMetrics: $plusMenuAnchorMetrics,
            tabBarMetrics: $tabBarMetrics,
            lastVisibleTabBarHeight: $lastVisibleTabBarHeight,
            activeWorkoutMiniPlayerState: activeWorkoutMiniPlayerState,
            showsOrionAccessory: showsOrionAccessory,
            isOrionChatPresented: $isOrionChatPresented,
            orionChatViewModel: orionChatViewModel,
            bottomChromeLayoutStore: bottomChromeLayoutStore,
            canOpenOrion: shouldShowOrionBar
        )
    }

    private var rootSyncStatusHost: some View {
        PulsarRootSyncStatusHost()
    }

    @ViewBuilder
    private func rootOrionHost(showsOrion: Bool) -> some View {
        if showsOrion && !usesNativeOrionTabAccessory {
            GeometryReader { proxy in
                let compactFrame = isOrionBarCompact ? rootOrionCompactFrame(in: proxy) : nil

                ZStack(alignment: .top) {
                    Color.clear
                        .allowsHitTesting(false)

                    if let compactFrame {
                        OrionBarView(
                            isInlinePlacement: true,
                            onOpen: openOrion
                        )
                            .frame(width: rootOrionWidth(in: proxy, compactFrame: compactFrame), height: rootOrionBarHeight)
                            .position(
                                x: rootOrionCenterX(in: proxy, compactFrame: compactFrame),
                                y: rootOrionCenterY(in: proxy, compactFrame: compactFrame)
                            )
                            .transition(rootOrionModeTransition)
                    } else {
                        OrionBarView(
                            isInlinePlacement: false,
                            onOpen: openOrion
                        )
                            .frame(width: rootOrionWidth(in: proxy, compactFrame: nil), height: rootOrionBarHeight)
                            .position(
                                x: rootOrionCenterX(in: proxy, compactFrame: nil),
                                y: rootOrionCenterY(in: proxy, compactFrame: nil)
                            )
                            .transition(rootOrionModeTransition)
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .zIndex(998)
            .transition(rootOrionTransition)
            .animation(rootOrionModeAnimation, value: isOrionBarCompact)
        }
    }

    @ViewBuilder
    private func rootMiniWorkoutHost(
        state: PulsarWorkoutMiniPlayerState?,
        layoutController: PulsarBottomChromeLayoutController
    ) -> some View {
        if !usesNativeMiniWorkoutTabAccessory,
           let state {
            GeometryReader { proxy in
                ZStack(alignment: .top) {
                    Color.clear
                        .allowsHitTesting(false)

                    PulsarMiniWorkoutBarHost(
                        state: state,
                        isInlinePlacement: isMiniWorkoutCollapsed,
                        usesNativeAccessoryChrome: false,
                        layoutController: layoutController,
                        onOpen: openActiveWorkoutMiniPlayer
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
            .animation(.spring(response: 0.36, dampingFraction: 0.86), value: isMiniWorkoutCollapsed)
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

    private func visibleActiveWorkoutMiniPlayerState() -> PulsarWorkoutMiniPlayerState? {
        shouldShowMiniWorkoutBar ? activeWorkoutMiniPlayerState : nil
    }

    private var shouldShowOrionBar: Bool {
        PulsarRootLiveChromeIdentity.resolve(
            presentationState: activeWorkoutManager.presentationState
        ).showsOrion
    }

    private var rootOrionTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    private var rootOrionModeTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985))
    }

    private var rootOrionModeAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.16) : .smooth(duration: 0.24)
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
        if #available(iOS 26.0, *) {
            return true
        }
        return false
    }

    private var usesNativeOrionTabAccessory: Bool {
        if #available(iOS 26.0, *) {
            return true
        }
        return false
    }


    private var rootMiniWorkoutHorizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 56 : HomePremiumDesign.Layout.screenMargin
    }

    private var isMiniWorkoutCollapsed: Bool {
        tabBarMetrics.isMinimized
    }

    private var isOrionBarCompact: Bool {
        false
    }

    private var rootMiniWorkoutHeight: CGFloat {
        isMiniWorkoutCollapsed ? 48 : 60
    }

    private var rootOrionBarHeight: CGFloat {
        isOrionBarCompact ? 44 : 50
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

    private func rootOrionCenterY(in proxy: GeometryProxy, compactFrame: CGRect?) -> CGFloat {
        guard proxy.size.height > rootOrionBarHeight else {
            return rootOrionBarHeight / 2
        }
        if let compactFrame {
            return compactFrame.midY
        }
        let rootFrame = proxy.frame(in: .global)
        let tabTopY = tabBarMetrics.minY - rootFrame.minY

        if tabTopY > rootOrionBarHeight,
           tabTopY < proxy.size.height {
            let proposed = max(
                rootOrionBarHeight / 2 + rootMiniWorkoutGap,
                tabTopY - rootMiniWorkoutGap - rootOrionBarHeight / 2
            )
            return min(proposed, proxy.size.height - rootOrionBarHeight / 2)
        }

        let fallbackTabChromeHeight = max(tabBarMetrics.visibleHeight, lastVisibleTabBarHeight, tabBarMetrics.bottomSafeAreaInset + 58, 72)
        let proposed = max(
            rootOrionBarHeight / 2 + rootMiniWorkoutGap,
            proxy.size.height - fallbackTabChromeHeight - rootMiniWorkoutGap - rootOrionBarHeight / 2
        )
        return min(proposed, proxy.size.height - rootOrionBarHeight / 2)
    }

    private func rootOrionCenterX(in proxy: GeometryProxy, compactFrame: CGRect?) -> CGFloat {
        if let compactFrame {
            return compactFrame.midX
        }
        return proxy.size.width / 2
    }

    private func rootOrionWidth(in proxy: GeometryProxy, compactFrame: CGRect?) -> CGFloat {
        if let compactFrame {
            return max(1, compactFrame.width)
        }

        let availableWidth = max(1, proxy.size.width - rootMiniWorkoutHorizontalPadding * 2)
        return min(availableWidth, rootMiniWorkoutMaxWidth)
    }

    private func rootOrionCompactFrame(in proxy: GeometryProxy) -> CGRect? {
        let rootFrame = proxy.frame(in: .global)
        guard tabBarMetrics.hasCompactControlLayout else { return nil }

        let tabControlFrame = CGRect(
            x: tabBarMetrics.selectedControlFrame.minX - rootFrame.minX,
            y: tabBarMetrics.selectedControlFrame.minY - rootFrame.minY,
            width: tabBarMetrics.selectedControlFrame.width,
            height: tabBarMetrics.selectedControlFrame.height
        )
        let plusFrame = CGRect(
            x: tabBarMetrics.plusControlFrame.minX - rootFrame.minX,
            y: tabBarMetrics.plusControlFrame.minY - rootFrame.minY,
            width: tabBarMetrics.plusControlFrame.width,
            height: tabBarMetrics.plusControlFrame.height
        )
        let sidePadding: CGFloat = 12
        let compactGap: CGFloat = 10

        let leadingBound = max(proxy.safeAreaInsets.leading + sidePadding, tabControlFrame.maxX + compactGap)
        let trailingBound = min(proxy.size.width - proxy.safeAreaInsets.trailing - sidePadding, plusFrame.minX - compactGap)
        let availableWidth = trailingBound - leadingBound
        guard availableWidth > 120 else { return nil }

        let controlCenterY = (tabControlFrame.midY + plusFrame.midY) / 2
        let midY = min(max(controlCenterY, rootOrionBarHeight / 2), proxy.size.height - rootOrionBarHeight / 2)

        return CGRect(
            x: leadingBound,
            y: midY - rootOrionBarHeight / 2,
            width: availableWidth,
            height: rootOrionBarHeight
        )
    }

    private func rootPlusActionFrame(in proxy: GeometryProxy, tabFrame: CGRect) -> CGRect {
        let tabHeight = max(tabFrame.height, 58)
        let sideLength = min(60, max(56, tabHeight * 0.82))
        let originX = max(
            proxy.safeAreaInsets.leading + 12,
            proxy.size.width - proxy.safeAreaInsets.trailing - sideLength - 12
        )

        return CGRect(
            x: originX,
            y: tabFrame.midY - sideLength / 2,
            width: sideLength,
            height: sideLength
        )
    }

    private func rootLeadingTabControlFrame(in proxy: GeometryProxy, rootFrame: CGRect, centerY: CGFloat) -> CGRect {
        let hasValidTabMetrics = tabBarMetrics.width > 0 &&
            tabBarMetrics.height > 0 &&
            tabBarMetrics.minY > 0 &&
            tabBarMetrics.minY < proxy.size.height
        let tabFrame = hasValidTabMetrics
            ? CGRect(
                x: tabBarMetrics.minX - rootFrame.minX,
                y: tabBarMetrics.minY - rootFrame.minY,
                width: tabBarMetrics.width,
                height: tabBarMetrics.height
            )
            : CGRect(
                x: proxy.safeAreaInsets.leading + 12,
                y: proxy.size.height - max(tabBarMetrics.visibleHeight, proxy.safeAreaInsets.bottom + 58, 86),
                width: 60,
                height: 60
            )
        let tabHeight = max(tabFrame.height, 58)
        let sideLength = min(60, max(56, tabHeight * 0.82))
        let horizontalInset = max(0, (tabHeight - sideLength) / 2)
        let originX = max(proxy.safeAreaInsets.leading + 12, tabFrame.minX + horizontalInset)
        let originY = centerY - sideLength / 2

        return CGRect(
            x: originX,
            y: originY,
            width: sideLength,
            height: sideLength
        )
    }

    private func rootBottomControlCenterY(in proxy: GeometryProxy, rootFrame: CGRect) -> CGFloat {
        let tabHeight = max(tabBarMetrics.height, 58)
        let sideLength = min(60, max(56, tabHeight * 0.82))
        let safeAreaBottom = max(proxy.safeAreaInsets.bottom, tabBarMetrics.bottomSafeAreaInset, 0)
        let bottomGap: CGFloat = safeAreaBottom > 0 ? 14 : 8
        let fallbackCenterY = proxy.size.height - safeAreaBottom - bottomGap - sideLength / 2

        guard tabBarMetrics.minY > 0,
              tabBarMetrics.minY < proxy.size.height,
              tabBarMetrics.height > 0 else {
            return min(max(fallbackCenterY, sideLength / 2), proxy.size.height - sideLength / 2)
        }

        let metricsCenterY = tabBarMetrics.minY - rootFrame.minY + tabBarMetrics.height / 2
        let alignedCenterY = max(metricsCenterY, fallbackCenterY)
        return min(max(alignedCenterY, sideLength / 2), proxy.size.height - sideLength / 2)
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
            return watchGymMiniPlayerState(for: activeWorkout)
                ?? syncMiniPlayerState(for: activeWorkout)
                ?? PulsarWorkoutMiniPlayerPresenter.watchGymFallback(activeWorkout: activeWorkout)
        }
    }

    private var cachedActiveWorkoutMiniPlayerState: PulsarWorkoutMiniPlayerState? {
        guard let activeWorkout = activeWorkoutManager.activeWorkout,
              activeWorkoutManager.presentation == .minimized(activeWorkout.sessionID) else { return nil }
        guard let cached = workoutServices.lastKnownActiveWorkoutDisplayStates[activeWorkout.sessionID] else { return nil }
        PulsarStateDebugLogger.log("Using last known mini workout display state session=\(activeWorkout.sessionID.uuidString)")
        return cached
    }

    private func runMiniPlayerState(for activeWorkout: PulsarActiveWorkout) -> PulsarWorkoutMiniPlayerState? {
        let snapshot = runCoordinator.snapshot
        if snapshot.pulsarWorkoutSessionId == nil {
            PulsarStateDebugLogger.log("Refused to render mini workout because sessionID was nil")
        }
        return PulsarWorkoutMiniPlayerPresenter.run(
            activeWorkout: activeWorkout,
            snapshot: snapshot,
            syncedSessionID: watchSyncStore.activeWorkoutState?.sessionId
        )
    }

    private func gymMiniPlayerState(for activeWorkout: PulsarActiveWorkout) -> PulsarWorkoutMiniPlayerState? {
        PulsarWorkoutMiniPlayerPresenter.gym(
            activeWorkout: activeWorkout,
            viewModel: activeWorkoutManager.gymSessionViewModel,
            isMinimized: activeWorkoutManager.isGymWorkoutMinimized
        )
    }

    private func watchGymMiniPlayerState(for activeWorkout: PulsarActiveWorkout) -> PulsarWorkoutMiniPlayerState? {
        PulsarWorkoutMiniPlayerPresenter.watchGym(
            activeWorkout: activeWorkout,
            state: watchSyncStore.activeGymState,
            isRoutable: watchSyncStore.activeGymState.map(watchSyncStore.isRoutableActiveGymState) ?? false,
            hasLocalGymSession: activeWorkoutManager.gymSessionViewModel != nil
        )
    }

    private func syncMiniPlayerState(for activeWorkout: PulsarActiveWorkout) -> PulsarWorkoutMiniPlayerState? {
        PulsarWorkoutMiniPlayerPresenter.synced(
            activeWorkout: activeWorkout,
            state: watchSyncStore.activeWorkoutState
        )
    }

    private func openPlusDestination(_ destination: PulsarPlusDestination) {
        playPlusMenuHaptic(.light)
        dismissPlusMenu()
        DispatchQueue.main.async {
            presentedPlusDestination = destination
        }
    }

    private func togglePlusMenu() {
        playPlusMenuHaptic(isPlusMenuExpanded ? .soft : .light)
        if isPlusMenuExpanded {
            dismissPlusMenu()
        } else if isPlusMenuMounted {
            withAnimation(plusMenuAnimation) {
                isPlusMenuExpanded = true
            }
        } else {
            presentPlusMenu()
        }
    }

    private func presentPlusMenu() {
        plusMenuAnchorMetrics = tabBarMetrics
        isPlusMenuMounted = true
        DispatchQueue.main.async {
            withAnimation(plusMenuAnimation) {
                isPlusMenuExpanded = true
            }
        }
    }

    private func dismissPlusMenu() {
        guard isPlusMenuMounted else { return }
        withAnimation(plusMenuAnimation) {
            isPlusMenuExpanded = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + plusMenuDismissDelay) {
            guard !isPlusMenuExpanded else { return }
            isPlusMenuMounted = false
            plusMenuAnchorMetrics = nil
        }
    }

    private func dismissPlusDestination() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        presentedPlusDestination = nil
    }

    private func openOrion() {
        guard shouldShowOrionBar else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        dismissPlusMenu()
        orionChatViewModel.startNewConversation()
        isOrionChatPresented = true
    }

    private func playPlusMenuHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    private var plusMenuAnimation: Animation {
        .spring(response: 0.44, dampingFraction: 0.88, blendDuration: 0.08)
    }

    private var plusMenuDismissDelay: TimeInterval {
        0.46
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

    private func handleWorkoutPresentationDismissed() {
        guard let dismissal = activeWorkoutManager.consumePendingDismissedCurrentWorkout() else { return }

        switch dismissal.workout {
        case .run:
            guard runCoordinator.snapshot.phase.isActiveWorkoutPhase else { return }
        case .gym:
            guard activeWorkoutManager.gymSessionViewModel?.session.id == dismissal.sessionID,
                  activeWorkoutManager.gymSessionViewModel?.summary == nil else { return }
        case .watchGym:
            guard let activeWorkout = activeWorkoutManager.activeWorkout,
                  case .watchGym = activeWorkout.kind,
                  activeWorkout.phase != "finished" else { return }
        }
        _ = activeWorkoutManager.finalizeWorkoutPresentationDismissal(
            dismissal,
            reason: "rootWorkoutSheetOnDismiss"
        )
    }

    private func handleRunPhaseChanged(_ newPhase: PulsarRunPhase) {
        guard let activeWorkout = activeWorkoutManager.activeWorkout,
              case .run = activeWorkout.kind else { return }

        guard newPhase.isTerminalActiveWorkoutClearPhase else {
            PulsarStateDebugLogger.log("Blocked active run clear from non-terminal local phase session=\(activeWorkout.sessionID.uuidString) phase=\(newPhase.rawValue)")
            return
        }

        let sessionID = runCoordinator.snapshot.pulsarWorkoutSessionId ?? activeWorkout.sessionID
        if newPhase == .finished, let summary = runCoordinator.summary {
            let summarySessionID = summary.pulsarWorkoutSessionId ?? sessionID
            guard workoutLifecycle.canPresentSummary(sessionID: summarySessionID),
                  completionPresentationStore.canPresentSummary(sessionID: summarySessionID) else {
                PulsarWorkoutLifecycleLogger.log(
                    .summaryPresentationBlocked,
                    sessionID: summarySessionID,
                    source: "runCoordinatorPhaseChanged",
                    detail: "reason=notEligibleOrConsumed"
                )
                return
            }
            completionPresentationStore.markPending(
                WorkoutCompletionPresentation(
                    sessionID: summarySessionID,
                    kind: .run(summary),
                    presentedAt: Date(),
                    source: .localFinish
                )
            )
            activeWorkoutManager.presentRunSummary(summary.workoutKind, sessionID: summarySessionID)
            PulsarStateDebugLogger.log("[PulsarSummary] Deferred active run clear until summary dismissal session=\(summarySessionID.uuidString)")
            return
        }

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

    private func handleWorkoutLifecyclePhaseChanged(_ newPhase: PulsarWorkoutStartPhase) {
        switch newPhase {
        case .active(let transaction):
            completionPresentationStore.markEligibleForSummary(sessionID: transaction.sessionID)
            if let authoritativeSessionID = transaction.authoritativeSessionID {
                completionPresentationStore.markEligibleForSummary(sessionID: authoritativeSessionID)
            }
        case .completed(let transaction):
            completionPresentationStore.markEligibleForSummary(sessionID: transaction.sessionID)
            if let authoritativeSessionID = transaction.authoritativeSessionID {
                completionPresentationStore.markEligibleForSummary(sessionID: authoritativeSessionID)
            }
            PulsarStateDebugLogger.log(
                "Workout lifecycle completed session=\(transaction.sessionID.uuidString) policy=\(workoutLifecycle.presentationPolicy)"
            )
        case .failed(let transaction, let error):
            PulsarStateDebugLogger.log(
                "Workout lifecycle failed session=\(transaction.sessionID.uuidString) error=\(error) policy=\(workoutLifecycle.presentationPolicy)"
            )
        case .cancelled(let transaction):
            PulsarStateDebugLogger.log(
                "Workout lifecycle cancelled session=\(transaction.sessionID.uuidString) policy=\(workoutLifecycle.presentationPolicy)"
            )
        default:
            break
        }
    }

    private func handleConfirmedGymFinish(_ confirmation: GymWorkoutFinishConfirmation) {
        let currentWorkout = activeWorkoutManager.activeWorkout
        let isCurrentWatchGym = currentWorkout?.sessionID == confirmation.sessionID &&
            currentWorkout?.kind == .watchGym
        let isSummaryEligible = completionPresentationStore.isEligibleForSummary(
            sessionID: confirmation.sessionID
        ) || workoutLifecycle.canPresentSummary(sessionID: confirmation.sessionID)

        switch PulsarConfirmedGymFinishDisposition.resolve(
            isCurrentWatchGym: isCurrentWatchGym,
            isSummaryEligible: isSummaryEligible,
            isLaunchCoverOwning: activeWorkoutManager.isLaunchCoverOwningPresentation,
            alreadyRetainedSession: activeWorkoutManager.retainedFinishedWatchGymSessionID == confirmation.sessionID
        ) {
        case .retainForSummary:
            completionPresentationStore.markEligibleForSummary(sessionID: confirmation.sessionID)
            activeWorkoutManager.presentWatchGymSummary(sessionID: confirmation.sessionID)
            syncCurrentActiveWorkoutSessionContext(reason: "confirmedGymFinishAwaitingSummary")
            PulsarUIDebugLogger.log(
                "[PulsarWorkoutPresentation] workoutID=\(confirmation.sessionID.uuidString) phase=finished presentation=summaryPending action=retainUntilDismissed reason=\(confirmation.source)"
            )
        case .clearNeverActive:
            activeWorkoutManager.clearWatchGymWorkout(
                sessionID: confirmation.sessionID,
                phase: "finished",
                source: confirmation.source,
                reason: "confirmedGymFinishNeverActive"
            )
            completionPresentationStore.consume(
                sessionID: confirmation.sessionID,
                reason: "confirmedGymFinishNeverActive.\(confirmation.source)"
            )
            syncCurrentActiveWorkoutSessionContext(reason: "confirmedGymFinishNeverActive")
        case .ignore:
            PulsarWorkoutStartupTrace.diag(
                "[Presentation] confirmedGymFinish ignored session=\(confirmation.sessionID.uuidString) source=\(confirmation.source) launchOwned=\(activeWorkoutManager.isLaunchCoverOwningPresentation)"
            )
        }
    }

    private func presentRunSummaryIfAvailable(source: String) {
        guard let summary = runCoordinator.summary else { return }
        let summarySessionID = summary.pulsarWorkoutSessionId
            ?? runCoordinator.snapshot.pulsarWorkoutSessionId
            ?? activeWorkoutManager.activeWorkout?.sessionID
            ?? summary.id
        guard workoutLifecycle.canPresentSummary(sessionID: summarySessionID) else {
            PulsarWorkoutLifecycleLogger.log(
                .summaryPresentationBlocked,
                sessionID: summarySessionID,
                source: source,
                detail: "reason=sessionNeverReachedActive route=run"
            )
            return
        }
        guard completionPresentationStore.canPresentSummary(sessionID: summarySessionID) else {
            PulsarStateDebugLogger.log("[PulsarSummary] Skipped consumed or ineligible run summary source=\(source) session=\(summarySessionID.uuidString)")
            return
        }
        completionPresentationStore.markPending(
            WorkoutCompletionPresentation(
                sessionID: summarySessionID,
                kind: .run(summary),
                presentedAt: Date(),
                source: source.hasPrefix("root") ? .rootSync : .localFinish
            )
        )
        activeWorkoutManager.presentRunSummary(summary.workoutKind, sessionID: summarySessionID)
        PulsarStateDebugLogger.log("[PulsarSummary] Presented run summary source=\(source) session=\(summarySessionID.uuidString)")
    }

    private func presentFinishedWatchGymSummaryIfNeeded(_ state: ActiveGymWorkoutState?, source: String) {
        guard let state, state.isFinished else { return }
        PulsarWorkoutLifecycleLogger.log(
            .summaryPresentationAttempted,
            sessionID: state.sessionId,
            source: source,
            detail: "route=watchGym"
        )
        if activeWorkoutManager.gymSessionViewModel?.session.id == state.sessionId {
            PulsarStateDebugLogger.log("[PulsarSummary] Skipped watch gym summary because local gym summary owns session source=\(source) session=\(state.sessionId.uuidString)")
            return
        }
        if let activeWorkout = activeWorkoutManager.activeWorkout,
           activeWorkout.kind == .watchGym,
           activeWorkout.sessionID != state.sessionId {
            PulsarWorkoutLifecycleLogger.log(
                .summaryPresentationBlocked,
                sessionID: state.sessionId,
                source: source,
                detail: "reason=currentWatchGymSessionMismatch currentSessionID=\(activeWorkout.sessionID.uuidString)"
            )
            return
        }
        if PulsarWorkoutStartCoordinator.shared.phase.isInProgress,
           let startingSessionID = PulsarWorkoutStartCoordinator.shared.currentTransaction?.sessionID,
           startingSessionID != state.sessionId {
            PulsarWorkoutLifecycleLogger.log(
                .summaryPresentationBlocked,
                sessionID: state.sessionId,
                source: source,
                detail: "reason=startInProgressSessionMismatch currentSessionID=\(startingSessionID.uuidString)"
            )
            return
        }
        guard completionPresentationStore.isEligibleForSummary(sessionID: state.sessionId) ||
                workoutLifecycle.canPresentSummary(sessionID: state.sessionId) else {
            PulsarWorkoutLifecycleLogger.log(
                .summaryPresentationBlocked,
                sessionID: state.sessionId,
                source: source,
                detail: "reason=sessionNeverObservedActive route=watchGym"
            )
            return
        }
        guard completionPresentationStore.shouldAutoPresent(sessionID: state.sessionId) else {
            PulsarStateDebugLogger.log("[PulsarSummary] Skipped consumed watch gym summary source=\(source) session=\(state.sessionId.uuidString)")
            return
        }
        if activeWorkoutManager.retainedFinishedWatchGymSessionID == state.sessionId {
            PulsarWorkoutStartupTrace.diag(
                "[Presentation] finishedGymSummary duplicateNoOp source=\(source) session=\(state.sessionId.uuidString)"
            )
            return
        }
        completionPresentationStore.markPending(
            WorkoutCompletionPresentation(
                sessionID: state.sessionId,
                kind: .gym(PulsarGymWorkoutSummary(activeGymState: state)),
                presentedAt: Date(),
                source: source.contains("restore") ? .restored : .watchSync
            )
        )
        activeWorkoutManager.presentWatchGymSummary(sessionID: state.sessionId)
        PulsarStateDebugLogger.log("[PulsarSummary] Watch gym summary presentation requested source=\(source) session=\(state.sessionId.uuidString)")
    }

    private func dismissWorkoutCompletion(
        sessionID: UUID?,
        kind: WorkoutCompletionDismissalKind,
        source: String
    ) {
        guard let sessionID else {
            switch kind {
            case .gym:
                activeWorkoutManager.completeGymWorkout()
            case .watchGym:
                activeWorkoutManager.clearWatchGymWorkout(
                    phase: "finished",
                    source: source,
                    reason: "summaryDismissedMissingSession"
                )
            case .run:
                runCoordinator.resetAfterSummary()
                activeWorkoutManager.clearRunWorkout(
                    phase: "finished",
                    source: source,
                    reason: "summaryDismissedMissingSession"
                )
            }
            activeWorkoutManager.presentedWorkout = nil
            return
        }

        completionPresentationStore.consume(sessionID: sessionID, reason: source)
        watchSyncStore.tombstoneActiveWorkoutSession(sessionID, reason: "completionConsumed.\(source)")
        watchSyncStore.clearFinishedGymPresentationState(sessionID: sessionID, reason: "completionConsumed.\(source)")

        switch kind {
        case .gym:
            activeWorkoutManager.completeGymWorkout()
        case .watchGym:
            activeWorkoutManager.clearWatchGymWorkout(
                sessionID: sessionID,
                phase: "finished",
                source: source,
                reason: "summaryDismissed"
            )
        case .run:
            runCoordinator.resetAfterSummary()
            activeWorkoutManager.clearRunWorkout(
                sessionID: sessionID,
                phase: "finished",
                source: source,
                reason: "summaryDismissed"
            )
        }

        if activeWorkoutManager.presentedWorkout != nil {
            activeWorkoutManager.presentedWorkout = nil
        }
        syncCurrentActiveWorkoutSessionContext(reason: "completionDismissed.\(source)")
    }

    private func cacheActiveWorkoutDisplayStateIfAvailable(reason: String) {
        guard let activeWorkout = activeWorkoutManager.activeWorkout,
              activeWorkoutManager.presentation == .minimized(activeWorkout.sessionID),
              let state = currentActiveWorkoutMiniPlayerState,
              state.sessionID == activeWorkout.sessionID else { return }

        guard workoutServices.lastKnownActiveWorkoutDisplayStates[state.sessionID] != state else { return }
        workoutServices.lastKnownActiveWorkoutDisplayStates[state.sessionID] = state
        pruneLastKnownWorkoutDisplayStates()
        PulsarStateDebugLogger.log("Cached mini workout display state session=\(state.sessionID.uuidString) reason=\(reason)")
    }

    private func pruneLastKnownWorkoutDisplayStates() {
        guard let activeSessionID = activeWorkoutManager.activeWorkout?.sessionID else {
            workoutServices.lastKnownActiveWorkoutDisplayStates.removeAll()
            return
        }
        workoutServices.lastKnownActiveWorkoutDisplayStates =
            workoutServices.lastKnownActiveWorkoutDisplayStates.filter { $0.key == activeSessionID }
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

    private func makeRestoredWorkoutReconciliationSnapshot() -> PulsarRestoredWorkoutReconciliationSnapshot {
        PulsarRestoredWorkoutReconciliationSnapshot(
            workoutState: watchSyncStore.activeWorkoutState,
            gymState: watchSyncStore.activeGymState
        )
    }

    private func reconcileRestoredActiveWorkoutOnAppEntry(
        _ restorationSnapshot: PulsarRestoredWorkoutReconciliationSnapshot,
        source: String
    ) async {
        guard let state = restorationSnapshot.workoutState else {
            if !runCoordinator.hasAnyValidatedLiveWorkoutSession {
                await runCoordinator.endStaleLiveActivities(reason: "no validated active workout on launch")
            }
            syncCurrentActiveWorkoutSessionContext(reason: "\(source).noRestoredActiveWorkout")
            return
        }

        guard restorationSnapshot.stillMatches(
            workoutState: watchSyncStore.activeWorkoutState,
            gymState: watchSyncStore.activeGymState
        ) else {
            PulsarWorkoutStartupTrace.lifecycle(
                "[WorkoutReconcile] incomingWorkoutID=\(state.sessionId.uuidString) canonicalWorkoutID=\(watchSyncStore.activeWorkoutState?.sessionId.uuidString ?? "none") incomingRequestID=\(restorationSnapshot.gymIdentity?.requestID?.uuidString ?? "none") canonicalRequestID=\(watchSyncStore.activeGymState?.requestID?.uuidString ?? "none") source=\(source) decision=rejectStaleOperation reason=stateChangedWhileReconciliationSuspended"
            )
            return
        }

        guard shouldApplyLiveActiveWorkoutSyncUpdate(state, source: source) else {
            await discardStaleRestoredActiveWorkout(
                state,
                restorationSnapshot: restorationSnapshot,
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
            let mirrorSnapshot = GymMirroredSessionBridge.shared.snapshot
            if mirrorSnapshot.hasAttachedLiveMirror,
               mirrorSnapshot.sessionID == state.sessionId {
                return true
            }
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
            if activeWorkoutManager.activeWorkout?.sessionID == state.sessionId {
                return true
            }
            if let transaction = PulsarWorkoutStartCoordinator.shared.currentTransaction,
               transaction.sessionID == state.sessionId || transaction.authoritativeSessionID == state.sessionId {
                return true
            }
            if source.hasPrefix("received"),
               state.lastUpdatedFrom == .appleWatch,
               state.isFreshRestoreConfirmation(),
               activeGymState.isFreshRestoreConfirmation() {
                return true
            }
            PulsarSyncDebugLogger.log("active workout restore rejected: no live gym authority source=\(source) session=\(state.sessionId.uuidString)")
            return false
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
        restorationSnapshot: PulsarRestoredWorkoutReconciliationSnapshot,
        source: String,
        reason: String
    ) async {
        guard restorationSnapshot.stillMatches(
            workoutState: watchSyncStore.activeWorkoutState,
            gymState: watchSyncStore.activeGymState
        ) else {
            PulsarWorkoutStartupTrace.lifecycle(
                "[GymTerminalCleanup] source=discardedStaleRestoredActiveWorkout.\(source) expectedWorkoutID=\(state.sessionId.uuidString) actualCurrentWorkoutID=\(watchSyncStore.activeWorkoutState?.sessionId.uuidString ?? "none") requestID=\(restorationSnapshot.gymIdentity?.requestID?.uuidString ?? "none") generation=\(restorationSnapshot.gymIdentity?.lifecycleGeneration ?? state.sessionGeneration ?? 0) localLaunchContextExists=\(PulsarWorkoutStartCoordinator.shared.matchesCurrentInFlightSession(state.sessionId)) canonicalActiveGymStateExists=\(watchSyncStore.activeGymState != nil) routineID=\(restorationSnapshot.gymIdentity?.routineID.uuidString ?? "none") exerciseCount=\(restorationSnapshot.gymIdentity?.exerciseIDs.count ?? 0) decision=rejected reason=stateChanged"
            )
            return
        }

        let hasInFlightLifecycleAuthority = PulsarWorkoutStartCoordinator.shared.matchesCurrentInFlightSession(
            state.sessionId
        )
        let mirrorSnapshot = GymMirroredSessionBridge.shared.snapshot
        let hasAuthoritativeGymMirror: Bool
        if case .gym = state.kind {
            hasAuthoritativeGymMirror = mirrorSnapshot.hasAttachedLiveMirror &&
                mirrorSnapshot.sessionID == state.sessionId
        } else {
            hasAuthoritativeGymMirror = false
        }
        let hasCanonicalManagerRuntime = activeWorkoutManager.activeWorkout?.sessionID == state.sessionId &&
            PulsarWorkoutStartCoordinator.shared.didReachActive(sessionID: state.sessionId)
        guard !hasInFlightLifecycleAuthority,
              !hasAuthoritativeGymMirror,
              !hasCanonicalManagerRuntime else {
            let authorityReason = hasInFlightLifecycleAuthority
                ? "inFlightStartTransaction"
                : hasAuthoritativeGymMirror ? "liveHealthKitMirror" : "activeManager"
            PulsarWorkoutStartupTrace.lifecycle(
                "[GymTerminalCleanup] source=discardedStaleRestoredActiveWorkout.\(source) expectedWorkoutID=\(state.sessionId.uuidString) actualCurrentWorkoutID=\(watchSyncStore.activeWorkoutState?.sessionId.uuidString ?? "none") requestID=\(restorationSnapshot.gymIdentity?.requestID?.uuidString ?? PulsarWorkoutStartCoordinator.shared.currentTransaction?.requestID?.uuidString ?? "none") generation=\(restorationSnapshot.gymIdentity?.lifecycleGeneration ?? state.sessionGeneration ?? 0) localLaunchContextExists=\(hasInFlightLifecycleAuthority) canonicalActiveGymStateExists=\(watchSyncStore.activeGymState != nil) routineID=\(restorationSnapshot.gymIdentity?.routineID.uuidString ?? "none") exerciseCount=\(restorationSnapshot.gymIdentity?.exerciseIDs.count ?? 0) decision=rejected reason=\(authorityReason)"
            )
            return
        }
        PulsarSyncDebugLogger.log("active workout restore rejected: \(reason) source=\(source) session=\(state.sessionId.uuidString) phase=\(state.phase.rawValue)")
        switch state.kind {
        case .outdoor:
            watchSyncStore.tombstoneActiveWorkoutSession(state.sessionId, reason: "discardedStaleRestoredActiveWorkout.\(source)")
            watchSyncStore.clearActiveWorkoutState(reason: "discardedStaleRestoredActiveWorkout.\(source)", broadcastEndedState: false)
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
            } else {
                watchSyncStore.tombstoneActiveWorkoutSession(state.sessionId, reason: "discardedStaleRestoredActiveWorkout.\(source)")
                if watchSyncStore.activeWorkoutState?.sessionId == state.sessionId {
                    watchSyncStore.clearActiveWorkoutState(reason: "discardedStaleRestoredActiveWorkout.\(source)", broadcastEndedState: false)
                }
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
            if !localRunIsActive, state.startedFrom.isAppleWatchRecorder {
                let adoption = PulsarWorkoutStartCoordinator.shared.adoptRemoteActiveWorkout(
                    sessionID: state.sessionId,
                    kind: .run(workoutKind),
                    workoutType: workoutKind.rawValue,
                    authority: runCoordinator.hasValidatedLiveWorkoutSession(sessionID: state.sessionId)
                        ? .mirroredHealthKit
                        : .freshWatchConnectivity,
                    source: "\(source).watchRun"
                )
                guard adoption == .applied || adoption == .duplicate else {
                    let existingSessionID = PulsarWorkoutStartCoordinator.shared.currentTransaction?.sessionID
                    PulsarSyncDebugLogger.log("iPhone active workout UI route skipped because remote state was not verified reason=\(source) session=\(state.sessionId.uuidString) existing=\(existingSessionID?.uuidString ?? "none") transition=\(String(describing: adoption))")
                    return
                }
            }
            runCoordinator.reconcileActiveWorkoutSyncState(state)
            PulsarSyncDebugLogger.log("active workout UI presentation allowed: valid active session source=\(source) session=\(state.sessionId.uuidString) type=\(workoutKind.rawValue)")
            PulsarWorkoutStartCoordinator.shared.markSessionReachedActive(
                sessionID: state.sessionId,
                source: "liveRunSyncApplied"
            )
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
            if PulsarGymCrossDeviceStartFeature.isEnabled,
               PulsarWorkoutStartCoordinator.shared.phase.isInProgress,
               !PulsarWorkoutStartCoordinator.shared.isCrossDeviceGymStartVerified {
                PulsarSyncDebugLogger.log("iPhone active gym mirror UI route skipped pending verification reason=\(source) session=\(state.sessionId.uuidString)")
                return
            }
            let adoption = PulsarWorkoutStartCoordinator.shared.adoptRemoteActiveWorkout(
                sessionID: state.sessionId,
                kind: .watchGym,
                workoutType: state.kind.workoutTypeRawValue,
                authority: PulsarWorkoutStartCoordinator.shared.currentTransaction == nil
                    ? .freshWatchConnectivity
                    : .existingCoordinator,
                source: "\(source).watchGym"
            )
            guard adoption == .applied || adoption == .duplicate else {
                let existingSessionID = PulsarWorkoutStartCoordinator.shared.currentTransaction?.sessionID
                PulsarSyncDebugLogger.log("iPhone active gym mirror UI route skipped because remote state was not verified reason=\(source) session=\(state.sessionId.uuidString) existing=\(existingSessionID?.uuidString ?? "none") transition=\(String(describing: adoption))")
                return
            }
            PulsarPerformanceDiagnostics.checkpoint("workout.gym.authorityValidated")
            guard activeWorkoutManager.gymSessionViewModel == nil else { return }
            PulsarSyncDebugLogger.log("active workout UI presentation allowed: valid active session source=\(source) session=\(state.sessionId.uuidString) type=\(state.kind.workoutTypeRawValue)")
            completionPresentationStore.markEligibleForSummary(sessionID: state.sessionId)
            PulsarWorkoutStartCoordinator.shared.markSessionReachedActive(
                sessionID: state.sessionId,
                source: "liveGymSyncApplied"
            )
            if activeWorkoutManager.reconcileActiveWorkoutPresentation(
                route: .watchGym,
                sessionID: state.sessionId,
                phase: state.phase.rawValue,
                reason: source
            ) {
                PulsarPerformanceDiagnostics.checkpoint("workout.gym.presentationExpanded")
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
            if let summary = runCoordinator.summary {
                let summarySessionID = summary.pulsarWorkoutSessionId ?? state.sessionId
                guard workoutLifecycle.canPresentSummary(sessionID: summarySessionID),
                      completionPresentationStore.canPresentSummary(sessionID: summarySessionID) else {
                    PulsarWorkoutLifecycleLogger.log(
                        .summaryPresentationBlocked,
                        sessionID: summarySessionID,
                        source: source,
                        detail: "reason=notEligibleOrConsumed route=endedRunSync"
                    )
                    return
                }
                completionPresentationStore.markPending(
                    WorkoutCompletionPresentation(
                        sessionID: summarySessionID,
                        kind: .run(summary),
                        presentedAt: Date(),
                        source: .rootSync
                    )
                )
                activeWorkoutManager.presentRunSummary(summary.workoutKind, sessionID: summarySessionID)
                PulsarSyncDebugLogger.log("[PulsarSummary] Presented ended run sync summary source=\(source) session=\(summarySessionID.uuidString)")
            } else {
                activeWorkoutManager.clearRunWorkout(
                    sessionID: state.sessionId,
                    phase: state.phase.rawValue,
                    source: source,
                    reason: "endedActiveWorkoutSync"
                )
            }
        case .gym:
            if let finishedState = watchSyncStore.lastFinishedGymState {
                presentFinishedWatchGymSummaryIfNeeded(finishedState, source: source)
            } else if activeWorkoutManager.isLaunchCoverOwningPresentation,
                      activeWorkoutManager.activeWorkout?.sessionID == state.sessionId {
                PulsarWorkoutStartupTrace.diag(
                    "[Presentation] endedActiveWorkoutSync retained launch cover session=\(state.sessionId.uuidString) source=\(source)"
                )
            } else {
                activeWorkoutManager.clearWatchGymWorkout(
                    sessionID: state.sessionId,
                    phase: state.phase.rawValue,
                    source: source,
                    reason: "endedActiveWorkoutSync"
                )
            }
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
            "shouldShowMiniWorkoutBar=\(shouldShow) session=\(activeWorkoutManager.activeWorkout?.sessionID.uuidString ?? "none") phase=\(activeWorkoutPhaseDescription) presentation=\(activeWorkoutManager.presentation) selectedTab=\(selectedTab.rawValue) miniState=\(state?.id ?? "none") placement=\(miniWorkoutPlacementDescription)"
        )
        PulsarWorkoutStartupTrace.diag(
            "[WorkoutUI] chrome shouldShowMini=\(shouldShow) session=\(activeWorkoutManager.activeWorkout?.sessionID.uuidString ?? "none") presentationState=\(activeWorkoutManager.presentationState.diagnosticName) coarse=\(activeWorkoutManager.presentation) sheetItem=\(activeWorkoutManager.presentedWorkoutItem != nil) selectedTab=\(selectedTab.rawValue) \(PulsarWorkoutStartupTrace.threadTag())"
        )
        if shouldShow, let sessionID = state?.sessionID {
            PulsarUIDebugLogger.log("MiniWorkoutHost shouldShow=true session=\(sessionID.uuidString)")
        }
    }

    private func updateTabBarMetrics(_ metrics: PulsarTabBarMetrics) {
        guard tabBarMetrics != metrics else { return }
        tabBarMetrics = metrics
        if metrics.visibleHeight > 1,
           abs(lastVisibleTabBarHeight - metrics.visibleHeight) > 0.5 {
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

        if let gymState = watchSyncStore.activeGymState,
           gymState.sessionId == activeSessionID {
            return gymState.isFinished ? "ended" : "active"
        }

        if let phase = activeWorkoutManager.activeWorkout?.phase {
            return phase
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

    private func shouldDisableWorkoutInteractiveDismiss(_ workout: PulsarPresentedWorkout) -> Bool {
        switch workout {
        case .run:
            return runCoordinator.summary != nil || runCoordinator.snapshot.phase == .finishing
        case .gym:
            return activeWorkoutManager.gymSessionViewModel?.summary != nil ||
                activeWorkoutManager.gymSessionViewModel?.isFinishing == true
        case .watchGym:
            if watchSyncStore.activeGymState?.isFinished == true {
                return true
            }
            return watchSyncStore.lastFinishedGymState?.sessionId == activeWorkoutManager.activeWorkout?.sessionID
        }
    }

    @ViewBuilder
    private func presentedWorkoutView(_ item: PulsarPresentedWorkoutItem) -> some View {
        switch item.workout {
        case .run(let workoutKind):
            PulsarRunExperienceView(
                coordinator: runCoordinator,
                workoutKind: workoutKind,
                profile: homeViewModel.profileStore.profile,
                onMinimize: {
                    activeWorkoutManager.minimizeRunWorkout(
                        workoutKind,
                        sessionID: item.sessionID
                    )
                },
                onSummaryDone: { summary in
                    dismissWorkoutCompletion(
                        sessionID: summary.pulsarWorkoutSessionId ?? activeWorkoutManager.activeWorkout?.sessionID,
                        kind: .run,
                        source: "runSummaryDone"
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
                        dismissWorkoutCompletion(
                            sessionID: viewModel.session.id,
                            kind: .gym,
                            source: "gymSummaryDone"
                        )
                    }
                )
            } else {
                Color.clear
                    .onAppear {
                        activeWorkoutManager.completeGymWorkout()
                    }
            }
        case .watchGym:
            GymWatchMirroredWorkoutView(
                syncStore: watchSyncStore,
                expectedSessionID: item.sessionID,
                profile: homeViewModel.profileStore.profile,
                diagnosticHost: "rootSheet",
                onMinimize: {
                    activeWorkoutManager.minimizeWatchGymWorkout(sessionID: item.sessionID)
                },
                onSummaryDone: {
                    dismissWorkoutCompletion(
                        sessionID: item.sessionID,
                        kind: .watchGym,
                        source: "watchGymSummaryDone"
                    )
                }
            )
            .environmentObject(completionPresentationStore)
        }
    }
}

/// Owns only the workout sheet modifier. Keeping this leaf separate prevents
/// `SheetPresentationModifier` from copying the root's full tab, lifecycle,
/// and subscription graph whenever the workout route changes.
private struct PulsarRootWorkoutPresentationHost<PresentedContent: View>: View {
    @ObservedObject var manager: PulsarActiveWorkoutManager
    let onDismiss: () -> Void
    @ViewBuilder let content: (PulsarPresentedWorkoutItem) -> PresentedContent

    private var itemBinding: Binding<PulsarPresentedWorkoutItem?> {
        Binding(
            get: { manager.presentedWorkoutItem },
            set: { manager.updatePresentedWorkoutItemFromSheet($0) }
        )
    }

    var body: some View {
        let _ = PulsarWorkoutStartupTrace.count("[RenderRate] WorkoutHost")
        let _ = {
            if let item = manager.presentedWorkoutItem {
                PulsarWorkoutStartupTrace.diagOnce(
                    "workoutUI.hostBodyEvaluated.\(item.sessionID.uuidString)",
                    "[WorkoutUI] hostBodyEvaluated sheetItem=\(item.sessionID.uuidString) presentationState=\(manager.presentationState.diagnosticName) \(PulsarWorkoutStartupTrace.threadTag())"
                )
            }
            return true
        }()
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .sheet(item: itemBinding, onDismiss: onDismiss) { item in
                let _ = PulsarWorkoutStartupTrace.diagOnce(
                    "workoutUI.presentationRequested.\(item.sessionID.uuidString)",
                    "[WorkoutUI] presentationRequested session=\(item.sessionID.uuidString) route=\(item.workout.id) \(PulsarWorkoutStartupTrace.threadTag())"
                )
                content(item)
                    .background {
                        PulsarWorkoutPresentationLifecycleProbe(sessionID: item.sessionID)
                            .frame(width: 0, height: 0)
                            .accessibilityHidden(true)
                    }
                    .onAppear {
                        PulsarWorkoutStartupTrace.diag(
                            "[WorkoutUI] hostOnAppear session=\(item.sessionID.uuidString) \(PulsarWorkoutStartupTrace.threadTag())"
                        )
                        PulsarPerformanceDiagnostics.instanceMounted("workout.rootPresenter")
                        PulsarPerformanceDiagnostics.checkpoint("workout.rootPresenter.appear")
                    }
                    .onDisappear {
                        PulsarWorkoutStartupTrace.diag(
                            "[WorkoutUI] hostOnDisappear session=\(item.sessionID.uuidString) \(PulsarWorkoutStartupTrace.threadTag())"
                        )
                        PulsarPerformanceDiagnostics.instanceUnmounted("workout.rootPresenter")
                        PulsarPerformanceDiagnostics.checkpoint("workout.rootPresenter.disappear")
                    }
            }
    }
}

#if os(iOS)
private struct PulsarWorkoutPresentationLifecycleProbe: UIViewControllerRepresentable {
    let sessionID: UUID

    func makeUIViewController(context: Context) -> ProbeController {
        let controller = ProbeController()
        controller.sessionID = sessionID
        return controller
    }

    func updateUIViewController(_ uiViewController: ProbeController, context: Context) {
        uiViewController.sessionID = sessionID
    }

    final class ProbeController: UIViewController {
        var sessionID = UUID()
        private var didLogWillAppear = false
        private var didLogDidAppear = false

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            guard !didLogWillAppear else { return }
            didLogWillAppear = true
            PulsarWorkoutStartupTrace.diag(
                "[WorkoutUI] presentationControllerWillPresent session=\(sessionID.uuidString) animated=\(animated) \(PulsarWorkoutStartupTrace.threadTag())"
            )
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !didLogDidAppear else { return }
            didLogDidAppear = true
            PulsarWorkoutStartupTrace.diag(
                "[WorkoutUI] presentationControllerDidPresent session=\(sessionID.uuidString) animated=\(animated) \(PulsarWorkoutStartupTrace.threadTag())"
            )
            PulsarWorkoutStartupTrace.diag(
                "[WorkoutUI] firstFrame session=\(sessionID.uuidString) \(PulsarWorkoutStartupTrace.threadTag())"
            )
        }
    }
}
#endif

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
    var selectedControlFrame: CGRect = .zero
    var plusControlFrame: CGRect = .zero
    var visibleControlCount = 0
    var isMinimized = false
    var isHidden = false

    var hasCompactControlLayout: Bool {
        selectedControlFrame.width > 1 &&
            selectedControlFrame.height > 1 &&
            plusControlFrame.width > 1 &&
            plusControlFrame.height > 1 &&
            plusControlFrame.minX > selectedControlFrame.maxX + 80 &&
            visibleControlCount <= 2
    }

    func quantized() -> PulsarTabBarMetrics {
        var metrics = self
        metrics.height = PulsarLayoutQuantization.quantize(height)
        metrics.width = PulsarLayoutQuantization.quantize(width)
        metrics.minX = PulsarLayoutQuantization.quantize(minX)
        metrics.maxX = PulsarLayoutQuantization.quantize(maxX)
        metrics.minY = PulsarLayoutQuantization.quantize(minY)
        metrics.maxY = PulsarLayoutQuantization.quantize(maxY)
        metrics.visibleHeight = PulsarLayoutQuantization.quantize(visibleHeight)
        metrics.bottomSafeAreaInset = PulsarLayoutQuantization.quantize(bottomSafeAreaInset)
        metrics.selectedControlFrame = PulsarLayoutQuantization.quantize(selectedControlFrame)
        metrics.plusControlFrame = PulsarLayoutQuantization.quantize(plusControlFrame)
        return metrics
    }
}

struct PulsarTabWallpaper: View {
    enum Style {
        case fitness
        case food
        case mindfulness
    }

    let style: Style

    @ViewBuilder
    var body: some View {
        switch style {
        case .fitness, .food:
            PulsarRootFitnessWallpaper(image: nil)
        case .mindfulness:
            PulsarRootMindfulnessWallpaper(image: nil)
        }
    }
}

private struct PulsarRootFitnessWallpaper: View {
    let image: UIImage?

    var body: some View {
        PulsarFitnessMonochromeBackground()
    }
}

private struct PulsarRootFoodWallpaper: View {
    let image: UIImage?

    var body: some View {
        GeometryReader { proxy in
            sourceImage
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0),
                            Color.black.opacity(0.16)
                        ],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .frame(height: proxy.size.height * 0.42)
                    .allowsHitTesting(false)
                }
                .ignoresSafeArea()
        }
    }

    private var sourceImage: Image {
        image.map(Image.init(uiImage:)) ?? Image("NutritionBackground")
    }
}

private struct PulsarRootMindfulnessWallpaper: View {
    let image: UIImage?

    var body: some View {
        sourceImage
            .resizable()
            .scaledToFill()
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [.black.opacity(0.48), .black.opacity(0.13), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 280)
            }
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.22), .black.opacity(0.66)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 430)
            }
            .ignoresSafeArea()
    }

    private var sourceImage: Image {
        image.map(Image.init(uiImage:)) ?? Image("MindfulnessBackground")
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

private struct PulsarTabBarControlMetrics {
    var selectedFrame: CGRect = .zero
    var plusFrame: CGRect = .zero
    var visibleCount = 0

    var isCompact: Bool {
        visibleCount <= 2 &&
            selectedFrame.width > 1 &&
            plusFrame.width > 1 &&
            plusFrame.minX > selectedFrame.maxX + 80
    }
}

private extension UITabBar {
    func pulsarVisibleControlMetrics(in window: UIWindow?) -> PulsarTabBarControlMetrics {
        var controls: [UIControl] = []
        pulsarCollectVisibleControls(in: self, into: &controls)

        let frames = controls
            .map { control in
                control.superview?.convert(control.frame, to: window) ?? control.frame
            }
            .filter { frame in
                frame.width > 1 && frame.height > 1
            }
            .sorted { lhs, rhs in
                if abs(lhs.minX - rhs.minX) > 0.5 {
                    return lhs.minX < rhs.minX
                }
                return lhs.minY < rhs.minY
            }

        guard let selectedFrame = frames.first,
              let plusFrame = frames.last,
              selectedFrame != plusFrame else {
            return PulsarTabBarControlMetrics(visibleCount: frames.count)
        }

        return PulsarTabBarControlMetrics(
            selectedFrame: selectedFrame,
            plusFrame: plusFrame,
            visibleCount: frames.count
        )
    }

    private func pulsarCollectVisibleControls(in view: UIView, into controls: inout [UIControl]) {
        for subview in view.subviews {
            guard !subview.isHidden,
                  subview.alpha > 0.05,
                  subview.bounds.width > 1,
                  subview.bounds.height > 1 else {
                continue
            }

            if let control = subview as? UIControl {
                controls.append(control)
            }

            pulsarCollectVisibleControls(in: subview, into: &controls)
        }
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
        case .mindfulness: "camera.macro"
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

    var performanceTab: PulsarPerformanceTab {
        switch self {
        case .home: .home
        case .fitness: .fitness
        case .food: .food
        case .mindfulness: .mindfulness
        }
    }

    var wallpaperAssetName: String? {
        switch self {
        case .home: nil
        case .fitness: "FitnessBackground"
        case .food: "NutritionBackground"
        case .mindfulness: "MindfulnessBackground"
        }
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

    var title: String {
        switch self {
        case .lab: "Lab"
        case .cycle: "Cycle"
        }
    }

    var symbolName: String {
        switch self {
        case .lab: "flask"
        case .cycle: "arrow.triangle.2.circlepath"
        }
    }
}

private struct PulsarPlusMorphingMenu: View {
    let isExpanded: Bool
    let tabBarMetrics: PulsarTabBarMetrics
    let onOpenDestination: (PulsarPlusDestination) -> Void
    let onToggle: () -> Void
    let onDismiss: () -> Void
    @Namespace private var morphNamespace

    var body: some View {
        GeometryReader { proxy in
            let layout = layout(in: proxy)

            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: layout.dismissLayerHeight)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onDismiss)

                    Spacer(minLength: 0)
                        .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                if isExpanded {
                    expandedMenu(layout: layout)
                        .zIndex(10)
                        .transition(.identity)
                } else {
                    compactPlusButton(layout: layout)
                        .zIndex(10)
                        .transition(.identity)
                }

                if isExpanded {
                    plusCollapseHitTarget(layout: layout)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func compactPlusButton(layout: PulsarPlusMenuLayout) -> some View {
        Button(action: onToggle) {
            ZStack {
                morphSurface(cornerRadius: layout.plusButtonFrame.width / 2)
                    .matchedGeometryEffect(
                        id: "plusMorphSurface",
                        in: morphNamespace,
                        properties: .frame,
                        anchor: .center
                    )

                Image(systemName: "plus")
                    .font(.system(size: 35, weight: .light))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.primary.opacity(0.85))
                    .transition(.opacity.combined(with: .scale(scale: 0.78)))
            }
        }
        .buttonStyle(.plain)
        .frame(width: layout.plusButtonFrame.width, height: layout.plusButtonFrame.height)
        .contentShape(Circle())
        .position(x: layout.plusButtonFrame.midX, y: layout.plusButtonFrame.midY)
        .accessibilityLabel("Open quick actions")
    }

    private func plusCollapseHitTarget(layout: PulsarPlusMenuLayout) -> some View {
        let hitSideLength = max(layout.plusButtonFrame.width + 36, 100)

        return Circle()
            .fill(Color.black.opacity(0.001))
            .frame(width: hitSideLength, height: hitSideLength)
        .contentShape(Circle())
        .allowsHitTesting(isExpanded)
        .onTapGesture(perform: onToggle)
        .position(x: layout.plusButtonFrame.midX, y: layout.plusButtonFrame.midY)
        .zIndex(100)
        .accessibilityLabel("Close quick actions")
    }

    private func expandedMenu(layout: PulsarPlusMenuLayout) -> some View {
        ZStack {
            morphSurface(cornerRadius: expandedCornerRadius)
                .matchedGeometryEffect(
                    id: "plusMorphSurface",
                    in: morphNamespace,
                    properties: .frame,
                    anchor: .center
                )

            VStack(alignment: .leading, spacing: rowSpacing) {
                PulsarPlusActionItem(destination: .lab) {
                    onOpenDestination(.lab)
                }

                PulsarPlusActionItem(destination: .cycle) {
                    onOpenDestination(.cycle)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, menuVerticalPadding)
            .opacity(isExpanded ? 1 : 0)
            .offset(y: isExpanded ? 0 : 12)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .animation(.easeOut(duration: 0.22).delay(0.1), value: isExpanded)
        }
        .frame(width: layout.expandedFrame.width, height: layout.expandedFrame.height)
        .contentShape(.rect(cornerRadius: expandedCornerRadius, style: .continuous))
        .position(x: layout.expandedFrame.midX, y: layout.expandedFrame.midY)
        .allowsHitTesting(isExpanded)
    }

    @ViewBuilder
    private func morphSurface(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 0) {
                Color.clear
                    .modifier(PulsarBottomChromeGlassModifier(
                        cornerRadius: cornerRadius,
                        usesNativeAccessoryChrome: false
                    ))
                    .compositingGroup()
            }
        } else {
            Color.clear
                .modifier(PulsarBottomChromeGlassModifier(
                    cornerRadius: cornerRadius,
                    usesNativeAccessoryChrome: false
                ))
                .compositingGroup()
        }
    }

    private func layout(in proxy: GeometryProxy) -> PulsarPlusMenuLayout {
        let tabChromeHeight = tabBarChromeHeight(in: proxy)
        let width = menuWidth(in: proxy)
        let height = menuHeight
        let bottomPadding = tabChromeHeight + verticalGapAboveTabBar
        let plusButtonFrame = plusButtonFrame(in: proxy, tabChromeHeight: tabChromeHeight)
        let expandedFrame = CGRect(
            x: plusButtonFrame.maxX - width,
            y: proxy.size.height - bottomPadding - height,
            width: width,
            height: height
        )

        return PulsarPlusMenuLayout(
            expandedFrame: expandedFrame,
            plusButtonFrame: plusButtonFrame,
            dismissLayerHeight: max(0, proxy.size.height - tabChromeHeight)
        )
    }

    private var rowHeight: CGFloat { 56 }
    private var rowSpacing: CGFloat { 6 }
    private var menuVerticalPadding: CGFloat { 16 }
    private var menuActionCount: CGFloat { 2 }

    private var menuHeight: CGFloat {
        menuActionCount * rowHeight
            + (menuActionCount - 1) * rowSpacing
            + menuVerticalPadding * 2
    }

    private var expandedCornerRadius: CGFloat {
        36
    }

    private func menuWidth(in proxy: GeometryProxy) -> CGFloat {
        min(max(204, proxy.size.width - 64), 224)
    }

    private func tabBarChromeHeight(in proxy: GeometryProxy) -> CGFloat {
        if tabBarMetrics.minY > 0, tabBarMetrics.minY < proxy.size.height {
            return max(proxy.size.height - tabBarMetrics.minY, proxy.safeAreaInsets.bottom + 58)
        }

        return max(
            tabBarMetrics.visibleHeight,
            tabBarMetrics.bottomSafeAreaInset + 58,
            72
        )
    }

    private var verticalGapAboveTabBar: CGFloat {
        42
    }

    private func plusButtonFrame(in proxy: GeometryProxy, tabChromeHeight: CGFloat) -> CGRect {
        let tabHeight = max(tabBarMetrics.height, 58)
        let sideLength = min(60, max(56, tabHeight * 0.82))
        let horizontalInset = max(0, (tabHeight - sideLength) / 2)
        let tabMaxX = tabBarMetrics.maxX > 0 ? min(tabBarMetrics.maxX, proxy.size.width) : proxy.size.width
        let tabMinY = tabBarMetrics.minY > 0 && tabBarMetrics.minY < proxy.size.height
            ? tabBarMetrics.minY
            : proxy.size.height - tabChromeHeight
        let tabMidY = tabMinY + tabHeight / 2

        return CGRect(
            x: tabMaxX - sideLength - horizontalInset,
            y: tabMidY - sideLength / 2,
            width: sideLength,
            height: sideLength
        )
    }
}

private struct PulsarPlusActionItem: View {
    let destination: PulsarPlusDestination
    let action: () -> Void
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 24
    @ScaledMetric(relativeTo: .body) private var iconFrame: CGFloat = 32
    @ScaledMetric(relativeTo: .body) private var rowMinHeight: CGFloat = 56

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: destination.symbolName)
                    .font(.system(size: iconSize, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.primary.opacity(0.85))
                    .frame(width: iconFrame, height: iconFrame)

                Text(destination.title)
                    .pulsarTextStyle(.bodyEmphasis)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: rowMinHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(destination.title)")
    }
}

private struct PulsarPlusMenuLayout {
    let expandedFrame: CGRect
    let plusButtonFrame: CGRect
    let dismissLayerHeight: CGFloat
}

private struct PulsarRootSyncStatusHost: View {
    @ObservedObject private var center: PulsarSyncBannerCenter = .shared

    var body: some View {
        Group {
            if center.state != .hidden {
                PulsarSyncStatusPill(center: center)
                    .frame(maxWidth: 420)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .transition(
                        .opacity
                            .combined(with: .scale(scale: 0.98, anchor: .top))
                    )
            }
        }
        .animation(.smooth(duration: 0.28), value: center.state)
        .allowsHitTesting(false)
    }
}

private enum PremiumHomeTabBar {
    static func apply(to tabBar: UITabBar, usesLightPalette: Bool) {
        let selectedColor = PulsarTabPalette.selectedTabAccentUIColor
        let normalColor = usesLightPalette
            ? UIColor(red: 0.24, green: 0.27, blue: 0.33, alpha: 0.78)
            : UIColor.white.withAlphaComponent(0.58)
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = nil
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear
        appearance.selectionIndicatorImage = selectionIndicatorImage(usesLightPalette: usesLightPalette)

        configure(appearance.stackedLayoutAppearance, normalColor: normalColor, selectedColor: selectedColor)
        configure(appearance.inlineLayoutAppearance, normalColor: normalColor, selectedColor: selectedColor)
        configure(appearance.compactInlineLayoutAppearance, normalColor: normalColor, selectedColor: selectedColor)

        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.tintColor = selectedColor
        tabBar.unselectedItemTintColor = normalColor
        tabBar.isTranslucent = true
        tabBar.backgroundColor = .clear
        tabBar.backgroundImage = UIImage()
        tabBar.shadowImage = UIImage()
        tabBar.layer.shadowColor = UIColor.black.cgColor
        tabBar.layer.shadowOpacity = 0.035
        tabBar.layer.shadowRadius = 9
        tabBar.layer.shadowOffset = CGSize(width: 0, height: 5)
    }

    private static func configure(
        _ itemAppearance: UITabBarItemAppearance,
        normalColor: UIColor,
        selectedColor: UIColor
    ) {
        itemAppearance.normal.iconColor = normalColor
        itemAppearance.normal.titleTextAttributes = [
            .foregroundColor: normalColor,
            .font: UIFont.systemFont(ofSize: 12, weight: .medium)
        ]
        itemAppearance.selected.iconColor = selectedColor
        itemAppearance.selected.titleTextAttributes = [
            .foregroundColor: selectedColor,
            .font: UIFont.systemFont(ofSize: 12, weight: .semibold)
        ]
        itemAppearance.normal.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: 1)
        itemAppearance.selected.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: 1)
    }

    private static func selectionIndicatorImage(usesLightPalette: Bool) -> UIImage {
        let size = CGSize(width: 52, height: 40)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let rect = CGRect(x: 5, y: 7, width: size.width - 10, height: size.height - 14)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2)
            context.cgContext.setShadow(
                offset: .zero,
                blur: 10,
                color: UIColor(red: 0.42, green: 0.95, blue: 0.54, alpha: 0.11).cgColor
            )
            let fillColor = usesLightPalette
                ? PulsarTabPalette.selectedTabAccentUIColor.withAlphaComponent(0.075)
                : UIColor(red: 0.25, green: 0.62, blue: 0.36, alpha: 0.070)
            fillColor.setFill()
            path.fill()
            context.cgContext.setShadow(offset: .zero, blur: 0, color: nil)

            (usesLightPalette ? UIColor.black.withAlphaComponent(0.055) : UIColor.white.withAlphaComponent(0.12)).setStroke()
            path.lineWidth = 0.55
            path.stroke()
        }
        return image.resizableImage(
            withCapInsets: UIEdgeInsets(top: 0, left: size.width / 2, bottom: 0, right: size.width / 2),
            resizingMode: .stretch
        )
    }
}

private struct PulsarNativeTabController: UIViewControllerRepresentable {
    @Binding var selectedTab: PulsarRootTab

    let homeViewModel: HomeViewModel
    let homeBackgroundSettings: HomeBackgroundSettingsStore
    let nutritionStore: PulsarNutritionStore
    let activeWorkoutManager: PulsarActiveWorkoutManager
    let runCoordinator: PulsarRunCoordinator
    let completionPresentationStore: WorkoutCompletionPresentationStore
    let mindfulnessStore: PulsarMindfulnessStore
    let mindfulnessRouter: PulsarMindfulnessRouter
    let isPlusActionHidden: Bool
    @Binding var isPlusMenuMounted: Bool
    @Binding var isPlusMenuExpanded: Bool
    @Binding var plusMenuAnchorMetrics: PulsarTabBarMetrics?
    @Binding var tabBarMetrics: PulsarTabBarMetrics
    @Binding var lastVisibleTabBarHeight: CGFloat
    let activeWorkoutMiniPlayerState: PulsarWorkoutMiniPlayerState?
    let showsOrionAccessory: Bool
    @Binding var isOrionChatPresented: Bool
    let orionChatViewModel: OrionChatViewModel
    let bottomChromeLayoutStore: PulsarBottomChromeLayoutStore
    let canOpenOrion: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            selectedTab: $selectedTab,
            isPlusMenuMounted: $isPlusMenuMounted,
            isPlusMenuExpanded: $isPlusMenuExpanded,
            plusMenuAnchorMetrics: $plusMenuAnchorMetrics,
            tabBarMetrics: $tabBarMetrics,
            lastVisibleTabBarHeight: $lastVisibleTabBarHeight,
            activeWorkoutManager: activeWorkoutManager,
            activeWorkoutMiniPlayerState: activeWorkoutMiniPlayerState,
            isOrionChatPresented: $isOrionChatPresented,
            orionChatViewModel: orionChatViewModel,
            canOpenOrion: canOpenOrion
        )
    }

    func makeUIViewController(context: Context) -> PulsarNativeTabBarController {
        let controller = PulsarNativeTabBarController()
        context.coordinator.configure(controller)
        controller.installTabs(nativeTabs, selectedRootTab: selectedTab)
        controller.updatePlusActionVisibility(isHidden: isPlusActionHidden)
        controller.stageGlobalBottomAccessory(
            workoutState: activeWorkoutMiniPlayerState,
            onOpenWorkout: context.coordinator.openActiveWorkout,
            showsOrion: showsOrionAccessory,
            onOpenOrion: context.coordinator.openOrion
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: PulsarNativeTabBarController, context: Context) {
        context.coordinator.selectedTab = $selectedTab
        context.coordinator.isPlusMenuMounted = $isPlusMenuMounted
        context.coordinator.isPlusMenuExpanded = $isPlusMenuExpanded
        context.coordinator.plusMenuAnchorMetrics = $plusMenuAnchorMetrics
        context.coordinator.tabBarMetrics = $tabBarMetrics
        context.coordinator.lastVisibleTabBarHeight = $lastVisibleTabBarHeight
        context.coordinator.activeWorkoutMiniPlayerState = activeWorkoutMiniPlayerState
        context.coordinator.isOrionChatPresented = $isOrionChatPresented
        context.coordinator.canOpenOrion = canOpenOrion
        context.coordinator.configure(uiViewController)

        if !uiViewController.hasExpectedRootTabs(PulsarRootTab.allCases.map(\.identifier)) {
            uiViewController.installTabs(nativeTabs, selectedRootTab: selectedTab)
        }
        uiViewController.updatePlusActionVisibility(isHidden: isPlusActionHidden)
        uiViewController.selectRootTab(selectedTab)
        uiViewController.stageGlobalBottomAccessory(
            workoutState: activeWorkoutMiniPlayerState,
            onOpenWorkout: context.coordinator.openActiveWorkout,
            showsOrion: showsOrionAccessory,
            onOpenOrion: context.coordinator.openOrion
        )
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
        tab.image = UIImage(
            systemName: "plus",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        )
        tab.preferredPlacement = .pinned
        tab.allowsHiding = false
        tab.automaticallyActivatesSearch = false
        tab.userInfo = PulsarNativeTabBarController.plusActionUserInfo
        tab.accessibilityIdentifier = "pulsar.plus.action"
        tab.accessibilityLabel = "Open quick actions"
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
            HomeView(
                viewModel: homeViewModel,
                backgroundSettings: homeBackgroundSettings,
                bottomChromeLayoutStore: bottomChromeLayoutStore
            )
        case .fitness:
            FitnessView(
                profileStore: homeViewModel.profileStore,
                bottomChromeLayoutStore: bottomChromeLayoutStore,
                runCoordinator: runCoordinator,
                activeWorkoutManager: activeWorkoutManager
            )
                .environmentObject(activeWorkoutManager)
                .environmentObject(completionPresentationStore)
        case .food:
            FoodView(
                store: nutritionStore,
                profileStore: homeViewModel.profileStore,
                bottomChromeLayoutStore: bottomChromeLayoutStore
            )
        case .mindfulness:
            PulsarInstrumentedRootDestination(destination: .mindfulness) {
                InsightsView(
                    homeViewModel: homeViewModel,
                    mindfulnessStore: mindfulnessStore,
                    mindfulnessRouter: mindfulnessRouter,
                    bottomChromeLayoutStore: bottomChromeLayoutStore
                )
            }
        }
    }

    @MainActor
    final class Coordinator {
        var selectedTab: Binding<PulsarRootTab>
        var isPlusMenuMounted: Binding<Bool>
        var isPlusMenuExpanded: Binding<Bool>
        var plusMenuAnchorMetrics: Binding<PulsarTabBarMetrics?>
        var tabBarMetrics: Binding<PulsarTabBarMetrics>
        var lastVisibleTabBarHeight: Binding<CGFloat>
        let activeWorkoutManager: PulsarActiveWorkoutManager
        var activeWorkoutMiniPlayerState: PulsarWorkoutMiniPlayerState?
        var isOrionChatPresented: Binding<Bool>
        let orionChatViewModel: OrionChatViewModel
        var canOpenOrion: Bool
        private var plusMenuDismissTask: Task<Void, Never>?

        init(
            selectedTab: Binding<PulsarRootTab>,
            isPlusMenuMounted: Binding<Bool>,
            isPlusMenuExpanded: Binding<Bool>,
            plusMenuAnchorMetrics: Binding<PulsarTabBarMetrics?>,
            tabBarMetrics: Binding<PulsarTabBarMetrics>,
            lastVisibleTabBarHeight: Binding<CGFloat>,
            activeWorkoutManager: PulsarActiveWorkoutManager,
            activeWorkoutMiniPlayerState: PulsarWorkoutMiniPlayerState?,
            isOrionChatPresented: Binding<Bool>,
            orionChatViewModel: OrionChatViewModel,
            canOpenOrion: Bool
        ) {
            self.selectedTab = selectedTab
            self.isPlusMenuMounted = isPlusMenuMounted
            self.isPlusMenuExpanded = isPlusMenuExpanded
            self.plusMenuAnchorMetrics = plusMenuAnchorMetrics
            self.tabBarMetrics = tabBarMetrics
            self.lastVisibleTabBarHeight = lastVisibleTabBarHeight
            self.activeWorkoutManager = activeWorkoutManager
            self.activeWorkoutMiniPlayerState = activeWorkoutMiniPlayerState
            self.isOrionChatPresented = isOrionChatPresented
            self.orionChatViewModel = orionChatViewModel
            self.canOpenOrion = canOpenOrion
        }

        func configure(_ controller: PulsarNativeTabBarController) {
            controller.onTabSelected = { [weak self] tab, token in
                guard let self else { return }
                PulsarPerformanceSignposts.beginTabRootSelection(token)
                guard self.selectedTab.wrappedValue != tab else {
                    PulsarPerformanceSignposts.markTabRootSelectionObserved(tab.performanceTab)
                    PulsarPerformanceSignposts.markTabSelectionApplied(token)
                    return
                }
                self.selectedTab.wrappedValue = tab
                PulsarPerformanceSignposts.markTabSelectionApplied(token)
            }
            controller.onTogglePlusMenu = { [weak self] in
                self?.togglePlusMenu()
            }
            controller.onMetricsChange = { [weak self] metrics in
                self?.updateTabBarMetrics(metrics)
            }
        }

        func openActiveWorkout() {
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

        func openOrion() {
            guard canOpenOrion else { return }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            dismissPlusMenu()
            orionChatViewModel.startNewConversation()
            isOrionChatPresented.wrappedValue = true
        }

        private func togglePlusMenu() {
            playPlusMenuHaptic(isPlusMenuExpanded.wrappedValue ? .soft : .light)
            if isPlusMenuExpanded.wrappedValue {
                dismissPlusMenu()
            } else if isPlusMenuMounted.wrappedValue {
                plusMenuDismissTask?.cancel()
                withAnimation(plusMenuAnimation) {
                    isPlusMenuExpanded.wrappedValue = true
                }
            } else {
                presentPlusMenu()
            }
        }

        private func presentPlusMenu() {
            plusMenuDismissTask?.cancel()
            plusMenuAnchorMetrics.wrappedValue = tabBarMetrics.wrappedValue
            isPlusMenuMounted.wrappedValue = true
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self else { return }
                withAnimation(self.plusMenuAnimation) {
                    self.isPlusMenuExpanded.wrappedValue = true
                }
            }
        }

        private func dismissPlusMenu() {
            guard isPlusMenuMounted.wrappedValue else { return }
            withAnimation(plusMenuAnimation) {
                isPlusMenuExpanded.wrappedValue = false
            }
            plusMenuDismissTask?.cancel()
            plusMenuDismissTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(460))
                guard !Task.isCancelled,
                      let self,
                      !self.isPlusMenuExpanded.wrappedValue else { return }
                self.isPlusMenuMounted.wrappedValue = false
                self.plusMenuAnchorMetrics.wrappedValue = nil
            }
        }

        private func playPlusMenuHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            generator.impactOccurred()
        }

        private var plusMenuAnimation: Animation {
            .spring(response: 0.44, dampingFraction: 0.88, blendDuration: 0.08)
        }

        private func updateTabBarMetrics(_ metrics: PulsarTabBarMetrics) {
            guard tabBarMetrics.wrappedValue != metrics else { return }
            tabBarMetrics.wrappedValue = metrics
            if metrics.visibleHeight > 1,
               abs(lastVisibleTabBarHeight.wrappedValue - metrics.visibleHeight) > 0.5 {
                lastVisibleTabBarHeight.wrappedValue = metrics.visibleHeight
            }
            PulsarUIDebugLogger.log("Native tab bar metrics visibleHeight=\(Int(metrics.visibleHeight)) height=\(Int(metrics.height)) width=\(Int(metrics.width)) minY=\(Int(metrics.minY)) minimized=\(metrics.isMinimized) hidden=\(metrics.isHidden)")
            if let state = activeWorkoutMiniPlayerState {
                PulsarUIDebugLogger.log("MiniWorkout preserved during scroll session=\(state.sessionID.uuidString)")
            }
        }

        deinit {
            plusMenuDismissTask?.cancel()
        }
    }
}

private struct PulsarInstrumentedRootDestination<Content: View>: View {
    let destination: PulsarPerformanceTab
    @ViewBuilder let content: Content

    var body: some View {
        PulsarPerformanceSignposts.measureTabDestinationBody(destination) {
            content
        }
        .onAppear {
            PulsarPerformanceSignposts.markTabDestinationAppeared(destination)
            PulsarPerformanceSignposts.markTabDestinationUseful(
                destination,
                cacheState: .notApplicable
            )
        }
    }
}

private final class PulsarNativeTabBarController: UITabBarController, UITabBarControllerDelegate {
    static let plusActionUserInfo = "pulsar.plus.action"

    var onTabSelected: ((PulsarRootTab, PulsarTabSelectionToken) -> Void)?
    var onTogglePlusMenu: (() -> Void)?
    var onMetricsChange: ((PulsarTabBarMetrics) -> Void)?

    private var lastSelectedRootTab: PulsarRootTab = .home
    private var lastMetrics = PulsarTabBarMetrics()
    private var bottomAccessoryContentView: UIView?
    private var bottomAccessoryHostingController: UIViewController?
    private var bottomAccessoryLayoutController: PulsarBottomChromeLayoutController?
    private var lastBottomAccessoryState: PulsarNativeBottomAccessoryState?
    private var bottomAccessoryUpdateTask: Task<Void, Never>?
    private var accessoryReconciler = PulsarNativeBottomAccessoryReconciler()
    private var desiredAccessoryWorkoutState: PulsarWorkoutMiniPlayerState?
    private var desiredOnOpenWorkout: () -> Void = {}
    private var desiredOnOpenOrion: () -> Void = {}
    private var pendingReportedMetrics: PulsarTabBarMetrics?
    private var metricsPublishTask: Task<Void, Never>?
    #if DEBUG
    private var accessoryApplyTimestamps: [Date] = []
    #endif
    private var plusActionToggleOverlay: UIButton?
    private weak var observedContentScrollView: UIScrollView?
    private weak var observedContentViewController: UIViewController?
    private weak var observedContentPanGesture: UIPanGestureRecognizer?
    private var directionalBottomChromeIntentTracker = PulsarDirectionalBottomChromeIntentTracker()
    private var isSuppressingTabBarMinimizeBehavior = false
    private var lastReconciledBottomChromeInputs: PulsarBottomChromeReconciliationInputs?
    private var isBottomChromeReconciliationScheduled = false
    private var isReconcilingBottomChrome = false
    private var pendingBottomChromeReconciliationRequiresLayout = false
    private var bottomChromeReconciliationTask: Task<Void, Never>?
    private var pendingTabSelectionToken: PulsarTabSelectionToken?
    private var scheduledTabSelectionToken: PulsarTabSelectionToken?
    private var preselectedRootTab: PulsarRootTab?
    private var preselectedTabSelectionToken: PulsarTabSelectionToken?
    private var didCountNativeTabControllerInstance = false
    private var didCountBottomAccessoryHostInstance = false

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        view.backgroundColor = .clear
        view.isOpaque = false
        mode = .tabBar
        tabBarMinimizeBehavior = .onScrollDown
        tabBar.isTranslucent = true
        PremiumHomeTabBar.apply(to: tabBar, usesLightPalette: true)
        PulsarPerformanceDiagnostics.instanceMounted("nativeTabController")
        didCountNativeTabControllerInstance = true
    }

    deinit {
        bottomAccessoryUpdateTask?.cancel()
        metricsPublishTask?.cancel()
        observedContentPanGesture?.removeTarget(self, action: #selector(handleSelectedContentPan(_:)))
        let shouldUnmountBottomAccessoryHost = didCountBottomAccessoryHostInstance
        let shouldUnmountNativeTabController = didCountNativeTabControllerInstance
        if shouldUnmountBottomAccessoryHost || shouldUnmountNativeTabController {
            Task { @MainActor in
                if shouldUnmountBottomAccessoryHost {
                    PulsarPerformanceDiagnostics.instanceUnmounted("bottomAccessoryHost")
                }
                if shouldUnmountNativeTabController {
                    PulsarPerformanceDiagnostics.instanceUnmounted("nativeTabController")
                }
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !isBottomChromeReconciliationScheduled,
              !isReconcilingBottomChrome else { return }
        reconcileBottomChromeLayout(selectionToken: chromeSelectionToken)
    }

    private func reconcileBottomChromeLayout(
        forcePendingTabBarLayout: Bool = false,
        selectionToken: PulsarTabSelectionToken?
    ) {
        guard !isReconcilingBottomChrome else {
            PulsarPerformanceSignposts.measureTabChromeReconciliation(
                selectionToken: selectionToken,
                forced: forcePendingTabBarLayout,
                duplicate: true
            ) {}
            return
        }
        let inputsBeforeForcedLayout = bottomChromeReconciliationInputs
        guard inputsBeforeForcedLayout != lastReconciledBottomChromeInputs else {
            PulsarPerformanceSignposts.measureTabChromeReconciliation(
                selectionToken: selectionToken,
                forced: forcePendingTabBarLayout,
                duplicate: true
            ) {}
            return
        }

        isReconcilingBottomChrome = true
        defer { isReconcilingBottomChrome = false }
        PulsarPerformanceSignposts.measureTabChromeReconciliation(
            selectionToken: selectionToken,
            forced: forcePendingTabBarLayout,
            duplicate: false
        ) {
            if forcePendingTabBarLayout {
                tabBar.setNeedsLayout()
                tabBar.layoutIfNeeded()
            }

            let inputs = bottomChromeReconciliationInputs
            guard inputs != lastReconciledBottomChromeInputs else { return }

            updateFloatingTabBarChrome()
            updateSelectedContentBottomSafeArea()
            extendSelectedContentBehindBottomChrome()
            updateSelectedContentScrollViewObservation()
            reportMetrics(for: tabBar.frame)
            positionPlusActionToggleOverlay()
            lastReconciledBottomChromeInputs = bottomChromeReconciliationInputs
        }
    }

    private var bottomChromeReconciliationInputs: PulsarBottomChromeReconciliationInputs {
        PulsarBottomChromeReconciliationInputs(
            containerBounds: PulsarLayoutQuantization.quantize(view.bounds),
            safeAreaInsets: PulsarLayoutQuantization.quantize(view.safeAreaInsets),
            tabBarFrame: PulsarLayoutQuantization.quantize(tabBar.frame),
            tabBarBounds: PulsarLayoutQuantization.quantize(tabBar.bounds),
            isTabBarHidden: tabBar.isHidden,
            selectedViewController: selectedViewController.map(ObjectIdentifier.init),
            selectedContentScrollView: selectedContentScrollView.map(ObjectIdentifier.init),
            hasPlusActionOverlay: plusActionToggleOverlay != nil,
            accessoryState: accessoryReconciler.applied.layoutState
        )
    }

    private func scheduleBottomChromeLayoutReconciliation(forcePendingTabBarLayout: Bool = true) {
        pendingBottomChromeReconciliationRequiresLayout =
            pendingBottomChromeReconciliationRequiresLayout || forcePendingTabBarLayout
        guard !isBottomChromeReconciliationScheduled else {
            PulsarPerformanceSignposts.measureTabChromeReconciliation(
                selectionToken: chromeSelectionToken,
                forced: forcePendingTabBarLayout,
                duplicate: true
            ) {}
            return
        }
        isBottomChromeReconciliationScheduled = true
        scheduledTabSelectionToken = chromeSelectionToken

        let coordinator = transitionCoordinator ?? selectedViewController?.transitionCoordinator
        if let coordinator, coordinator.isAnimated {
            let registered = coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                self?.completeScheduledBottomChromeLayoutReconciliation()
            }
            if registered {
                return
            }
        }

        bottomChromeReconciliationTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            self?.completeScheduledBottomChromeLayoutReconciliation()
        }
    }

    private func completeScheduledBottomChromeLayoutReconciliation() {
        guard isBottomChromeReconciliationScheduled else { return }
        let requiresLayout = pendingBottomChromeReconciliationRequiresLayout
        isBottomChromeReconciliationScheduled = false
        pendingBottomChromeReconciliationRequiresLayout = false
        bottomChromeReconciliationTask = nil
        let selectionToken = scheduledTabSelectionToken
        scheduledTabSelectionToken = nil
        reconcileBottomChromeLayout(
            forcePendingTabBarLayout: requiresLayout,
            selectionToken: selectionToken
        )
        if let selectionToken {
            PulsarPerformanceSignposts.markTabTransitionDone(selectionToken)
            if pendingTabSelectionToken == selectionToken {
                pendingTabSelectionToken = nil
            }
        }

        if pendingTabSelectionToken != nil {
            scheduleBottomChromeLayoutReconciliation(forcePendingTabBarLayout: false)
        }
    }

    private var chromeSelectionToken: PulsarTabSelectionToken? {
        preselectedTabSelectionToken ?? pendingTabSelectionToken
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
        guard selectedTab?.identifier != rootTab.identifier,
              let tab = tab(forIdentifier: rootTab.identifier) else { return }

        preselectedRootTab = nil
        preselectedTabSelectionToken = nil
        let token = PulsarPerformanceSignposts.beginTabSelection(
            from: lastSelectedRootTab.performanceTab,
            to: rootTab.performanceTab
        )
        pendingTabSelectionToken = token
        selectedTab = tab
        PulsarPerformanceSignposts.markTabSelectionApplied(token)
        if rootTab != lastSelectedRootTab {
            lastSelectedRootTab = rootTab
            PremiumHomeTabBar.apply(to: tabBar, usesLightPalette: rootTab == .home)
            if rootTab != .home {
                endDirectionalBottomChromeExpansionGesture()
            }
        }
        scheduleBottomChromeLayoutReconciliation()
    }

    func updatePlusActionVisibility(isHidden: Bool) {
        if let tab = tabs.first(where: isPlusActionTab),
           tab.isHidden != isHidden {
            tab.isHidden = isHidden
            tab.isEnabled = !isHidden
        }

        updatePlusActionToggleOverlay(isVisible: isHidden)
    }

    func stageGlobalBottomAccessory(
        workoutState: PulsarWorkoutMiniPlayerState?,
        onOpenWorkout: @escaping () -> Void,
        showsOrion: Bool,
        onOpenOrion: @escaping () -> Void
    ) {
        guard #available(iOS 26.0, *) else { return }

        desiredOnOpenWorkout = onOpenWorkout
        desiredOnOpenOrion = onOpenOrion
        desiredAccessoryWorkoutState = workoutState

        let identity = PulsarNativeBottomAccessoryIdentity(
            workoutState: workoutState,
            showsOrion: showsOrion
        )
        let result = accessoryReconciler.register(
            identity,
            workoutContent: workoutState
        )
        PulsarWorkoutStartupTrace.count(result.rateBucket)

        switch result {
        case .noOp:
            return
        case .coalesced:
            return
        case .updateContent:
            applyAccessoryContentUpdate(workoutState: workoutState)
        case .applyIdentity:
            noteAccessoryApplyRateIfNeeded()
            PulsarWorkoutStartupTrace.diag(
                "[BottomAccessory] request desired=\(accessoryReconciler.desired.diagnosticName) applied=\(accessoryReconciler.applied.diagnosticName) pending=\(accessoryReconciler.pending?.diagnosticName ?? "none") result=apply \(PulsarWorkoutStartupTrace.threadTag())"
            )
            scheduleAccessoryTransitionIfNeeded()
        }
    }

    private func noteAccessoryApplyRateIfNeeded() {
        #if DEBUG
        let now = Date()
        accessoryApplyTimestamps.append(now)
        accessoryApplyTimestamps.removeAll { now.timeIntervalSince($0) > 1 }
        if accessoryApplyTimestamps.count > 20 {
            PulsarWorkoutStartupTrace.diag(
                "[BottomAccessory] rateWarning appliesInLastSecond=\(accessoryApplyTimestamps.count) desired=\(accessoryReconciler.desired.diagnosticName) applied=\(accessoryReconciler.applied.diagnosticName)"
            )
            accessoryApplyTimestamps.removeAll()
        }
        #endif
    }

    private func scheduleAccessoryTransitionIfNeeded() {
        guard bottomAccessoryUpdateTask == nil else { return }
        bottomAccessoryUpdateTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            self?.applyPendingBottomAccessoryConfiguration()
        }
    }

    private func applyPendingBottomAccessoryConfiguration() {
        bottomAccessoryUpdateTask = nil
        let identity = accessoryReconciler.desired
        let workoutState = desiredAccessoryWorkoutState
        updateGlobalBottomAccessory(
            identity: identity,
            workoutState: workoutState,
            onOpenWorkout: desiredOnOpenWorkout,
            onOpenOrion: desiredOnOpenOrion
        )
        if accessoryReconciler.markApplied(identity, workoutContent: workoutState) {
            scheduleAccessoryTransitionIfNeeded()
        }
    }

    private func applyAccessoryContentUpdate(workoutState: PulsarWorkoutMiniPlayerState?) {
        guard let workoutState else { return }
        let nextState = PulsarNativeBottomAccessoryState.workout(workoutState)
        lastBottomAccessoryState = nextState
        guard let hostingController = bottomAccessoryHostingController as? UIHostingController<PulsarNativeBottomAccessoryView> else {
            return
        }
        let layoutController = bottomAccessoryLayoutController ?? PulsarBottomChromeLayoutController()
        layoutController.setSystemRequiresInline(true)
        bottomAccessoryLayoutController = layoutController
        hostingController.rootView = PulsarNativeBottomAccessoryView(
            layoutController: layoutController,
            state: nextState,
            onOpenWorkout: desiredOnOpenWorkout,
            onOpenOrion: desiredOnOpenOrion
        )
        (bottomAccessoryContentView as? PulsarMiniWorkoutAccessoryContentView)?.state = nextState
    }

    private func updateGlobalBottomAccessory(
        identity: PulsarNativeBottomAccessoryIdentity,
        workoutState: PulsarWorkoutMiniPlayerState?,
        onOpenWorkout: @escaping () -> Void,
        onOpenOrion: @escaping () -> Void
    ) {
        guard #available(iOS 26.0, *) else { return }

        switch identity {
        case .none:
            removeGlobalBottomAccessory(animated: false)
            return
        case .orion:
            installGlobalBottomAccessory(
                .orion,
                onOpenWorkout: onOpenWorkout,
                onOpenOrion: onOpenOrion
            )
        case .workout:
            guard let workoutState else {
                removeGlobalBottomAccessory(animated: false)
                return
            }
            installGlobalBottomAccessory(
                .workout(workoutState),
                onOpenWorkout: onOpenWorkout,
                onOpenOrion: onOpenOrion
            )
        }
    }

    private func installGlobalBottomAccessory(
        _ nextState: PulsarNativeBottomAccessoryState,
        onOpenWorkout: @escaping () -> Void,
        onOpenOrion: @escaping () -> Void
    ) {
        if nextState == lastBottomAccessoryState, bottomAccessoryContentView != nil {
            return
        }
        lastBottomAccessoryState = nextState
        if nextState != .orion {
            endDirectionalBottomChromeExpansionGesture()
        }

        let layoutController = bottomAccessoryLayoutController ?? PulsarBottomChromeLayoutController()
        layoutController.setSystemRequiresInline(true)
        bottomAccessoryLayoutController = layoutController
        let rootView = PulsarNativeBottomAccessoryView(
            layoutController: layoutController,
            state: nextState,
            onOpenWorkout: onOpenWorkout,
            onOpenOrion: onOpenOrion
        )

        if let hostingController = bottomAccessoryHostingController as? UIHostingController<PulsarNativeBottomAccessoryView> {
            hostingController.rootView = rootView
            (bottomAccessoryContentView as? PulsarMiniWorkoutAccessoryContentView)?.state = nextState
            return
        }

        let contentView = PulsarMiniWorkoutAccessoryContentView(state: nextState)
        let hostingController = UIHostingController(rootView: rootView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.isOpaque = false
        addChild(hostingController)
        contentView.install(hostingController.view)
        hostingController.didMove(toParent: self)

        bottomAccessoryContentView = contentView
        bottomAccessoryHostingController = hostingController
        PulsarWorkoutStartupTrace.diag(
            "[BottomAccessory] set begin state=\(nextState.diagnosticName) \(PulsarWorkoutStartupTrace.threadTag())"
        )
        setBottomAccessory(UITabAccessory(contentView: contentView), animated: false)
        PulsarWorkoutStartupTrace.diag(
            "[BottomAccessory] set end state=\(nextState.diagnosticName) \(PulsarWorkoutStartupTrace.threadTag())"
        )
        PulsarPerformanceDiagnostics.instanceMounted("bottomAccessoryHost")
        didCountBottomAccessoryHostInstance = true
    }

    private func removeGlobalBottomAccessory(animated: Bool) {
        let hasInstalledAccessory = bottomAccessoryHostingController != nil || bottomAccessoryContentView != nil
        guard hasInstalledAccessory else {
            lastBottomAccessoryState = nil
            return
        }
        if #available(iOS 26.0, *) {
            PulsarWorkoutStartupTrace.diag(
                "[BottomAccessory] setBottomAccessory(nil) begin animated=\(animated) \(PulsarWorkoutStartupTrace.threadTag())"
            )
            setBottomAccessory(nil, animated: animated)
            PulsarWorkoutStartupTrace.diag(
                "[BottomAccessory] setBottomAccessory(nil) end animated=\(animated) \(PulsarWorkoutStartupTrace.threadTag())"
            )
        }
        bottomAccessoryHostingController?.willMove(toParent: nil)
        bottomAccessoryHostingController?.view.removeFromSuperview()
        bottomAccessoryHostingController?.removeFromParent()
        bottomAccessoryHostingController = nil
        bottomAccessoryContentView = nil
        bottomAccessoryLayoutController = nil
        lastBottomAccessoryState = nil
        if didCountBottomAccessoryHostInstance {
            PulsarPerformanceDiagnostics.instanceUnmounted("bottomAccessoryHost")
            didCountBottomAccessoryHostInstance = false
        }
        endDirectionalBottomChromeExpansionGesture()
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
        if isPlusActionTab(tab) {
            preselectedRootTab = nil
            preselectedTabSelectionToken = nil
            onTogglePlusMenu?()
            selectRootTab(lastSelectedRootTab)
            return false
        }

        guard let rootTab = PulsarRootTab(identifier: tab.identifier),
              rootTab != lastSelectedRootTab else {
            preselectedRootTab = nil
            preselectedTabSelectionToken = nil
            return true
        }

        // Start before UIKit resolves the destination's lazy content provider.
        // This lets dest_body cover work that can occur before either didSelect
        // callback while still applying the SwiftUI binding only after selection.
        preselectedRootTab = rootTab
        preselectedTabSelectionToken = PulsarPerformanceSignposts.beginTabSelection(
            from: lastSelectedRootTab.performanceTab,
            to: rootTab.performanceTab
        )
        return true
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelectTab selectedTab: UITab, previousTab: UITab?) {
        guard let selectedRootTab = PulsarRootTab(identifier: selectedTab.identifier) else { return }
        handleRootTabSelection(selectedRootTab)
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        guard let selectedRootTab = selectedTab.flatMap({ PulsarRootTab(identifier: $0.identifier) }) else { return }
        handleRootTabSelection(selectedRootTab)
    }

    private func handleRootTabSelection(_ selectedRootTab: PulsarRootTab) {
        guard selectedRootTab != lastSelectedRootTab else { return }
        let token: PulsarTabSelectionToken
        if preselectedRootTab == selectedRootTab,
           let preselectedTabSelectionToken {
            token = preselectedTabSelectionToken
        } else {
            token = PulsarPerformanceSignposts.beginTabSelection(
                from: lastSelectedRootTab.performanceTab,
                to: selectedRootTab.performanceTab
            )
        }
        preselectedRootTab = nil
        preselectedTabSelectionToken = nil
        lastSelectedRootTab = selectedRootTab
        PremiumHomeTabBar.apply(to: tabBar, usesLightPalette: selectedRootTab == .home)
        pendingTabSelectionToken = token
        onTabSelected?(selectedRootTab, token)
        if selectedRootTab != .home {
            endDirectionalBottomChromeExpansionGesture()
        }
        scheduleBottomChromeLayoutReconciliation()
    }

    private func isPlusActionTab(_ tab: UITab) -> Bool {
        (tab.userInfo as? String) == Self.plusActionUserInfo
    }

    private func updatePlusActionToggleOverlay(isVisible: Bool) {
        guard isVisible else {
            plusActionToggleOverlay?.removeFromSuperview()
            plusActionToggleOverlay = nil
            return
        }

        let overlay = plusActionToggleOverlay ?? UIButton(type: .custom)
        if plusActionToggleOverlay == nil {
            overlay.backgroundColor = .clear
            overlay.accessibilityIdentifier = "pulsar.plus.action.toggle-overlay"
            overlay.accessibilityLabel = "Close quick actions"
            overlay.addTarget(self, action: #selector(handlePlusActionOverlayTap), for: .touchUpInside)
            view.addSubview(overlay)
            plusActionToggleOverlay = overlay
        }

        positionPlusActionToggleOverlay()
        view.bringSubviewToFront(overlay)
    }

    private func positionPlusActionToggleOverlay() {
        guard let overlay = plusActionToggleOverlay else { return }
        let frame = plusActionToggleOverlayFrame()
        guard overlay.frame != frame else { return }
        overlay.frame = frame
    }

    private func plusActionToggleOverlayFrame() -> CGRect {
        let tabFrame = tabBar.frame
        let tabHeight = max(tabFrame.height, 58)
        let sideLength = min(60, max(56, tabHeight * 0.82))
        let horizontalInset = max(0, (tabHeight - sideLength) / 2)
        let minX: CGFloat = 12
        let maxX = max(minX, view.bounds.width - sideLength - 12)
        let originX: CGFloat

        if tabFrame.width > 0,
           tabFrame.width < view.bounds.width * 0.72,
           tabFrame.maxX < view.bounds.width - sideLength {
            originX = min(max(tabFrame.maxX + 24, minX), maxX)
        } else {
            originX = min(max(tabFrame.maxX - sideLength - horizontalInset, minX), maxX)
        }

        let plusFrame = CGRect(
            x: originX,
            y: tabFrame.midY - sideLength / 2,
            width: sideLength,
            height: sideLength
        )
        let hitSideLength = max(sideLength + 36, 100)

        return CGRect(
            x: plusFrame.midX - hitSideLength / 2,
            y: plusFrame.midY - hitSideLength / 2,
            width: hitSideLength,
            height: hitSideLength
        )
    }

    @objc private func handlePlusActionOverlayTap() {
        onTogglePlusMenu?()
    }

    private func reportMetrics(for controlsFrame: CGRect) {
        guard let window = view.window else { return }
        let frameInWindow = view.convert(controlsFrame, to: window)
        let windowBounds = window.bounds
        let controlMetrics = tabBar.pulsarVisibleControlMetrics(in: window)
        let rawVisibleHeight = max(0, windowBounds.height - frameInWindow.minY)
        let maximumChromeHeight = max(controlsFrame.height + window.safeAreaInsets.bottom + 24, 86)
        let visibleHeight = min(rawVisibleHeight, maximumChromeHeight)
        let metrics = PulsarTabBarMetrics(
            height: controlsFrame.height,
            width: controlsFrame.width,
            minX: frameInWindow.minX,
            maxX: frameInWindow.maxX,
            minY: frameInWindow.minY,
            maxY: frameInWindow.maxY,
            visibleHeight: visibleHeight,
            bottomSafeAreaInset: window.safeAreaInsets.bottom,
            selectedControlFrame: controlMetrics.selectedFrame,
            plusControlFrame: controlMetrics.plusFrame,
            visibleControlCount: controlMetrics.visibleCount,
            isMinimized: frameInWindow.width > 0 && frameInWindow.width < windowBounds.width * 0.72 || controlMetrics.isCompact,
            isHidden: false
        ).quantized()
        guard metrics != lastMetrics else { return }
        lastMetrics = metrics
        pendingReportedMetrics = metrics
        PulsarPerformanceDiagnostics.event("tab.metrics.accepted")
        guard metricsPublishTask == nil else { return }
        metricsPublishTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.metricsPublishTask = nil
            guard let published = self.pendingReportedMetrics else { return }
            self.pendingReportedMetrics = nil
            self.onMetricsChange?(published)
        }
    }

    private func updateFloatingTabBarChrome() {
        let isFloating = tabBar.frame.width > 0 && tabBar.frame.width < view.bounds.width * 0.90
        guard isFloating else {
            tabBar.layer.cornerRadius = 0
            tabBar.layer.shadowPath = nil
            tabBar.layer.backgroundColor = nil
            tabBar.layer.borderWidth = 0
            return
        }

        let radius = min(tabBar.bounds.height / 2, 36)
        tabBar.layer.cornerCurve = .continuous
        tabBar.layer.cornerRadius = radius
        tabBar.layer.masksToBounds = false
        tabBar.layer.backgroundColor = nil
        tabBar.layer.borderColor = nil
        tabBar.layer.borderWidth = 0
        tabBar.layer.shadowOpacity = 0
        tabBar.layer.shadowPath = nil
    }

    private func updateSelectedContentBottomSafeArea() {
        guard let selectedViewController else { return }
        let targetInset: CGFloat = 0
        guard abs(selectedViewController.additionalSafeAreaInsets.bottom - targetInset) > 0.5 else { return }

        selectedViewController.additionalSafeAreaInsets.bottom = targetInset
    }

    private func updateSelectedContentScrollViewObservation() {
        guard let selectedViewController else { return }
        let scrollView = selectedContentScrollView
        let didChangeObservedScrollView = observedContentViewController !== selectedViewController
            || observedContentScrollView !== scrollView

        if didChangeObservedScrollView {
            selectedViewController.setContentScrollView(scrollView, for: .bottom)
            observedContentViewController = selectedViewController
            observedContentScrollView = scrollView
            attachDirectionalPanObservation(to: scrollView)
            endDirectionalBottomChromeExpansionGesture()
            return
        }

        if observedContentPanGesture == nil {
            attachDirectionalPanObservation(to: scrollView)
        }
    }

    private func attachDirectionalPanObservation(to scrollView: UIScrollView?) {
        detachDirectionalPanObservation()
        guard let scrollView else { return }
        let panGesture = scrollView.panGestureRecognizer
        panGesture.addTarget(self, action: #selector(handleSelectedContentPan(_:)))
        observedContentPanGesture = panGesture
    }

    private func detachDirectionalPanObservation() {
        observedContentPanGesture?.removeTarget(self, action: #selector(handleSelectedContentPan(_:)))
        observedContentPanGesture = nil
    }

    @objc private func handleSelectedContentPan(_ gesture: UIPanGestureRecognizer) {
        guard let phase = PulsarDirectionalPanPhase(gestureState: gesture.state) else { return }

        let context = PulsarDirectionalBottomChromeIntentContext(
            isHomeSelected: lastSelectedRootTab == .home,
            isOrionAccessory: lastBottomAccessoryState == .orion,
            isCompact: lastBottomAccessoryState != nil
        )
        let translationY = gesture.translation(in: gesture.view).y
        let intent = directionalBottomChromeIntentTracker.update(
            translationY: translationY,
            phase: phase,
            context: context
        )

        if intent == .expand {
            suppressTabBarMinimizeBehaviorForCurrentGesture()
        }

        if phase.isTerminal {
            restoreNativeTabBarMinimizeBehavior()
        }
    }

    private func suppressTabBarMinimizeBehaviorForCurrentGesture() {
        guard !isSuppressingTabBarMinimizeBehavior else { return }
        isSuppressingTabBarMinimizeBehavior = true
        tabBarMinimizeBehavior = .never
    }

    private func restoreNativeTabBarMinimizeBehavior() {
        guard isSuppressingTabBarMinimizeBehavior else { return }
        isSuppressingTabBarMinimizeBehavior = false
        tabBarMinimizeBehavior = .onScrollDown
    }

    private func endDirectionalBottomChromeExpansionGesture() {
        directionalBottomChromeIntentTracker.reset()
        restoreNativeTabBarMinimizeBehavior()
    }

    private var selectedContentScrollView: UIScrollView? {
        guard let contentView = selectedViewController?.view else { return nil }
        return contentView.pulsarPrimaryBottomChromeScrollView
            ?? contentView.pulsarBestVerticalContentScrollView
    }

    private func extendSelectedContentBehindBottomChrome() {
        guard let contentView = selectedViewController?.view,
              let containerView = contentView.superview else { return }

        var ancestor: UIView? = containerView
        while let current = ancestor, current !== view {
            current.clipsToBounds = false
            ancestor = current.superview
        }
        contentView.clipsToBounds = false

        let targetFrame = view.convert(view.bounds, to: containerView)
        if abs(contentView.frame.minX - targetFrame.minX) > 0.5 ||
            abs(contentView.frame.minY - targetFrame.minY) > 0.5 ||
            abs(contentView.frame.width - targetFrame.width) > 0.5 ||
            abs(contentView.frame.height - targetFrame.height) > 0.5 {
            contentView.frame = targetFrame
        }

        view.bringSubviewToFront(tabBar)
    }
}

private struct PulsarBottomChromeReconciliationInputs: Equatable {
    var containerBounds: CGRect
    var safeAreaInsets: UIEdgeInsets
    var tabBarFrame: CGRect
    var tabBarBounds: CGRect
    var isTabBarHidden: Bool
    var selectedViewController: ObjectIdentifier?
    var selectedContentScrollView: ObjectIdentifier?
    var hasPlusActionOverlay: Bool
    var accessoryState: PulsarNativeBottomAccessoryLayoutState?
}

private enum PulsarNativeBottomAccessoryState: Equatable {
    case orion
    case workout(PulsarWorkoutMiniPlayerState)

    var diagnosticName: String {
        switch self {
        case .orion: "orion"
        case .workout: "workout"
        }
    }

    var layoutState: PulsarNativeBottomAccessoryLayoutState {
        switch self {
        case .orion: .orion
        case .workout: .workout
        }
    }
}

private struct PulsarNativeBottomAccessoryView: View {
    let layoutController: PulsarBottomChromeLayoutController
    let state: PulsarNativeBottomAccessoryState
    let onOpenWorkout: () -> Void
    let onOpenOrion: () -> Void

    var body: some View {
        Group {
            switch state {
            case .orion:
                OrionBarView(
                    isInlinePlacement: true,
                    usesNativeAccessoryChrome: true,
                    onOpen: onOpenOrion
                )
            case .workout(let workoutState):
                PulsarMiniWorkoutBarHost(
                    state: workoutState,
                    isInlinePlacement: true,
                    usesNativeAccessoryChrome: true,
                    layoutController: layoutController,
                    onOpen: onOpenWorkout
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@available(iOS 26.0, *)
private final class PulsarMiniWorkoutAccessoryContentView: UIView {
    var state: PulsarNativeBottomAccessoryState {
        didSet {
            guard state.layoutState != oldValue.layoutState else { return }
            invalidateIntrinsicContentSize()
        }
    }

    init(state: PulsarNativeBottomAccessoryState) {
        self.state = state
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        // Width belongs to UITabAccessory. Height depends only on accessory
        // kind and the compact native contract, never on the trait or SwiftUI
        // layout that UIKit is resolving.
        let height = PulsarNativeBottomAccessorySizing.height(for: state.layoutState)
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    func install(_ hostedView: UIView) {
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        hostedView.backgroundColor = .clear
        hostedView.isOpaque = false
        addSubview(hostedView)
        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

}

@MainActor
private final class PulsarRootWorkoutServices: ObservableObject {
    let runCoordinator = PulsarRunCoordinator()
    let watchSyncStore = PulsarWatchConnectivitySyncStore.shared
    var lastKnownActiveWorkoutDisplayStates: [UUID: PulsarWorkoutMiniPlayerState] = [:]
}

private struct PulsarRootLiveChromeObserver<Content: View>: View {
    let activeWorkoutManager: PulsarActiveWorkoutManager
    let tabBarMetrics: PulsarTabBarMetrics
    let displayScale: CGFloat
    let bottomChromeLayoutStore: PulsarBottomChromeLayoutStore
    @StateObject private var layoutController = PulsarBottomChromeLayoutController()
    @StateObject private var projectionModel: PulsarRootLiveChromeProjectionModel

    let makeMiniPlayerState: () -> PulsarWorkoutMiniPlayerState?
    @ViewBuilder let content: (
        PulsarWorkoutMiniPlayerState?,
        Bool,
        PulsarBottomChromeLayoutController
    ) -> Content

    init(
        activeWorkoutManager: PulsarActiveWorkoutManager,
        runCoordinator: PulsarRunCoordinator,
        watchSyncStore: PulsarWatchConnectivitySyncStore,
        tabBarMetrics: PulsarTabBarMetrics,
        displayScale: CGFloat,
        bottomChromeLayoutStore: PulsarBottomChromeLayoutStore,
        makeMiniPlayerState: @escaping () -> PulsarWorkoutMiniPlayerState?,
        @ViewBuilder content: @escaping (
            PulsarWorkoutMiniPlayerState?,
            Bool,
            PulsarBottomChromeLayoutController
        ) -> Content
    ) {
        self.activeWorkoutManager = activeWorkoutManager
        self.tabBarMetrics = tabBarMetrics
        self.displayScale = displayScale
        self.bottomChromeLayoutStore = bottomChromeLayoutStore
        self.makeMiniPlayerState = makeMiniPlayerState
        self.content = content
        _projectionModel = StateObject(
            wrappedValue: PulsarRootLiveChromeProjectionModel(
                activeWorkoutManager: activeWorkoutManager,
                runCoordinator: runCoordinator,
                watchSyncStore: watchSyncStore
            )
        )
    }

    var body: some View {
        let _ = projectionModel.revision
        let observesLiveChrome = projectionModel.observesLiveChrome
        let miniPlayerState = observesLiveChrome ? makeMiniPlayerState() : nil
        let chromeIdentity = PulsarRootLiveChromeIdentity.resolve(
            presentationState: activeWorkoutManager.presentationState
        )
        let layoutInputs = PulsarBottomChromeLayoutInputs(
            safeAreaBottom: tabBarMetrics.bottomSafeAreaInset,
            displayScale: displayScale,
            showsMiniWorkout: chromeIdentity.showsMiniWorkout,
            showsOrion: chromeIdentity.showsOrion
        )

        content(miniPlayerState, chromeIdentity.showsOrion, layoutController)
            .animation(
                .spring(response: 0.42, dampingFraction: 0.88),
                value: miniPlayerState?.sessionID
            )
            .animation(
                .spring(response: 0.36, dampingFraction: 0.88),
                value: chromeIdentity.showsOrion
            )
            .onChange(of: layoutInputs, initial: true) { _, inputs in
                bottomChromeLayoutStore.update(
                    safeAreaBottom: inputs.safeAreaBottom,
                    accessoryHeight: inputs.accessoryHeight,
                    displayScale: inputs.displayScale
                )
            }
    }
}

/// Owns Combine subscriptions outside the SwiftUI modifier graph. Expanded and
/// launch-owned workouts keep the native-tab subtree mounted but suppress all
/// mini-player invalidations until a minimized presentation actually needs it.
@MainActor
private final class PulsarRootLiveChromeProjectionModel: ObservableObject {
    @Published private(set) var revision = 0
    private(set) var observesLiveChrome: Bool

    private let activeWorkoutManager: PulsarActiveWorkoutManager
    private var lastPublishedIdentity: PulsarRootLiveChromeIdentity
    private var subscriptions = Set<AnyCancellable>()
    private var localGymSubscriptions = Set<AnyCancellable>()

    init(
        activeWorkoutManager: PulsarActiveWorkoutManager,
        runCoordinator: PulsarRunCoordinator,
        watchSyncStore: PulsarWatchConnectivitySyncStore
    ) {
        self.activeWorkoutManager = activeWorkoutManager
        lastPublishedIdentity = PulsarRootLiveChromeIdentity.resolve(
            presentationState: activeWorkoutManager.presentationState
        )
        observesLiveChrome = Self.shouldObserve(activeWorkoutManager.presentationState)

        runCoordinator.$snapshot
            .map { PulsarRootRunMiniPlayerProjection(snapshot: $0) }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.invalidateIfObserving() }
            .store(in: &subscriptions)

        watchSyncStore.$activeWorkoutState
            .map { $0.map(PulsarRootSyncedWorkoutMiniPlayerProjection.init(state:)) }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.invalidateIfObserving() }
            .store(in: &subscriptions)

        watchSyncStore.$activeGymState
            .map { state in
                state.map {
                    PulsarRootWatchGymMiniPlayerProjection(
                        state: $0,
                        isRoutable: watchSyncStore.isRoutableActiveGymState($0)
                    )
                }
            }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.invalidateIfObserving() }
            .store(in: &subscriptions)

        activeWorkoutManager.$presentationState
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] state in
                self?.presentationDidChange(state)
            }
            .store(in: &subscriptions)

        activeWorkoutManager.$activeWorkout
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.rebindLocalGymSubscriptions()
                self?.publishChromeIdentityIfNeeded()
                self?.invalidateIfObserving()
            }
            .store(in: &subscriptions)

        activeWorkoutManager.$gymSessionViewModel
            .removeDuplicates(by: { $0 === $1 })
            .dropFirst()
            .sink { [weak self] _ in
                self?.rebindLocalGymSubscriptions()
                self?.invalidateIfObserving()
            }
            .store(in: &subscriptions)

        activeWorkoutManager.$isGymWorkoutMinimized
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.rebindLocalGymSubscriptions()
                self?.invalidateIfObserving()
            }
            .store(in: &subscriptions)

        rebindLocalGymSubscriptions()
    }

    private func presentationDidChange(_ state: PulsarActiveWorkoutPresentationState) {
        observesLiveChrome = Self.shouldObserve(state)
        rebindLocalGymSubscriptions()
        publishChromeIdentityIfNeeded()
    }

    private func publishChromeIdentityIfNeeded() {
        let next = PulsarRootLiveChromeIdentity.resolve(
            presentationState: activeWorkoutManager.presentationState
        )
        guard next != lastPublishedIdentity else { return }
        lastPublishedIdentity = next
        PulsarWorkoutStartupTrace.diag(
            "[BottomAccessory] chromeIdentity mini=\(next.miniSessionID?.uuidString ?? "none") orion=\(next.showsOrion) observe=\(observesLiveChrome) presentation=\(activeWorkoutManager.presentationState.diagnosticName) \(PulsarWorkoutStartupTrace.threadTag())"
        )
        invalidate()
    }

    private func rebindLocalGymSubscriptions() {
        localGymSubscriptions.removeAll()
        guard observesLiveChrome,
              activeWorkoutManager.isGymWorkoutMinimized,
              activeWorkoutManager.activeWorkout?.kind == .gym,
              let viewModel = activeWorkoutManager.gymSessionViewModel else { return }

        PulsarLocalGymMiniPlayerClockUpdates.publisher(for: viewModel.clock)
            .sink { [weak self] _ in self?.invalidateIfObserving() }
            .store(in: &localGymSubscriptions)
        PulsarLocalGymMiniPlayerContentUpdates.publisher(for: viewModel)
            .sink { [weak self] _ in self?.invalidateIfObserving() }
            .store(in: &localGymSubscriptions)
    }

    private func invalidateIfObserving() {
        guard observesLiveChrome else { return }
        invalidate()
    }

    private func invalidate() {
        revision &+= 1
        PulsarPerformanceDiagnostics.event("workout.chromeProjection")
    }

    private static func shouldObserve(_ state: PulsarActiveWorkoutPresentationState) -> Bool {
        switch state {
        case .minimized:
            true
        case .hidden, .launchOwned, .handoffPending, .expanded, .dismissing, .minimizing:
            false
        }
    }
}

nonisolated private struct PulsarRootRunMiniPlayerProjection: Equatable {
    var sessionID: UUID?
    var phase: PulsarRunPhase
    var source: PulsarRunRecordingSource
    var elapsedTime: TimeInterval
    var movingTime: TimeInterval
    var distanceMeters: Double
    var currentPaceSecondsPerKilometer: Double?
    var activeEnergyKilocalories: Double?
    var currentHeartRate: Double?
    var stepCount: Int?
    var cadenceStepsPerMinute: Double?

    init(snapshot: PulsarRunMetricSnapshot) {
        sessionID = snapshot.pulsarWorkoutSessionId
        phase = snapshot.phase
        source = snapshot.source
        elapsedTime = snapshot.elapsedTime
        movingTime = snapshot.movingTime
        distanceMeters = snapshot.distanceMeters
        currentPaceSecondsPerKilometer = snapshot.currentPaceSecondsPerKilometer
        activeEnergyKilocalories = snapshot.activeEnergyKilocalories
        currentHeartRate = snapshot.currentHeartRate
        stepCount = snapshot.stepCount
        cadenceStepsPerMinute = snapshot.cadenceStepsPerMinute
    }
}

nonisolated private struct PulsarRootSyncedWorkoutMiniPlayerProjection: Equatable {
    var sessionID: UUID
    var kindRawValue: String
    var displayName: String
    var startedFrom: PulsarWorkoutStartedFrom
    var lastUpdatedFrom: PulsarWorkoutStartedFrom
    var phase: PulsarActiveWorkoutSyncPhase
    var elapsedSeconds: Int
    var movingSeconds: Int?
    var distanceMeters: Double?
    var currentPaceSecondsPerKilometer: Double?
    var currentHeartRate: Double?
    var activeEnergyKilocalories: Double?
    var stepCount: Int?
    var cadenceStepsPerMinute: Double?

    init(state: PulsarActiveWorkoutSyncState) {
        sessionID = state.sessionId
        kindRawValue = state.kind.workoutTypeRawValue
        displayName = state.displayName
        startedFrom = state.startedFrom
        lastUpdatedFrom = state.lastUpdatedFrom
        phase = state.phase
        elapsedSeconds = state.elapsedSeconds
        movingSeconds = state.movingSeconds
        distanceMeters = state.distanceMeters
        currentPaceSecondsPerKilometer = state.currentPaceSecondsPerKilometer
        currentHeartRate = state.currentHeartRate
        activeEnergyKilocalories = state.activeEnergyKilocalories
        stepCount = state.stepCount
        cadenceStepsPerMinute = state.cadenceStepsPerMinute
    }
}

nonisolated private struct PulsarRootWatchGymMiniPlayerProjection: Equatable {
    var sessionID: UUID
    var routineName: String
    var elapsedSeconds: Int
    var currentExerciseName: String?
    var completedSets: Int
    var totalSets: Int
    var currentHeartRate: Double?
    var isFinished: Bool
    var isRoutable: Bool

    init(state: ActiveGymWorkoutState, isRoutable: Bool) {
        sessionID = state.sessionId
        routineName = state.routineName
        elapsedSeconds = state.elapsedSeconds
        if state.exercises.indices.contains(state.currentExerciseIndex) {
            currentExerciseName = state.exercises[state.currentExerciseIndex].exerciseName
        } else {
            currentExerciseName = state.exercises.first(where: { exercise in
                exercise.sets.contains(where: { !$0.isCompleted })
            })?.exerciseName ?? state.exercises.last?.exerciseName
        }
        completedSets = state.completedSets
        totalSets = state.totalSets
        currentHeartRate = state.currentHeartRate
        isFinished = state.isFinished
        self.isRoutable = isRoutable
    }
}

private struct PulsarWorkoutLifecyclePhaseObserver: View {
    @ObservedObject var coordinator: PulsarWorkoutStartCoordinator
    let onPhaseChange: (PulsarWorkoutStartPhase) -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: coordinator.phase) { _, newPhase in
                onPhaseChange(newPhase)
            }
    }
}

private struct PulsarRootWorkoutChromeObservationProbe: View {
    @ObservedObject var manager: PulsarActiveWorkoutManager
    let selectedTab: PulsarRootTab
    let onChange: (PulsarRootWorkoutChromeObservation, PulsarRootWorkoutChromeObservation) -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: observation) { previous, current in
                onChange(previous, current)
            }
    }

    private var observation: PulsarRootWorkoutChromeObservation {
        let identity = PulsarRootLiveChromeIdentity.resolve(
            presentationState: manager.presentationState
        )
        return PulsarRootWorkoutChromeObservation(
            shouldShowMiniWorkoutBar: identity.showsMiniWorkout,
            presentation: manager.presentation,
            activeSessionID: manager.activeWorkout?.sessionID,
            selectedTab: selectedTab
        )
    }
}

private struct PulsarRootWorkoutChromeObservation: Equatable {
    var shouldShowMiniWorkoutBar: Bool
    var presentation: PulsarActiveWorkoutPresentation
    var activeSessionID: UUID?
    var selectedTab: PulsarRootTab
}

enum PulsarConfirmedGymFinishDisposition: Equatable {
    case retainForSummary
    case clearNeverActive
    case ignore

    static func resolve(
        isCurrentWatchGym: Bool,
        isSummaryEligible: Bool,
        isLaunchCoverOwning: Bool = false,
        alreadyRetainedSession: Bool = false
    ) -> PulsarConfirmedGymFinishDisposition {
        if alreadyRetainedSession { return .ignore }
        if isLaunchCoverOwning && isCurrentWatchGym { return .retainForSummary }
        if isCurrentWatchGym && isSummaryEligible { return .retainForSummary }
        if isCurrentWatchGym { return .clearNeverActive }
        return .ignore
    }
}

private struct PulsarMiniWorkoutBarHost: View {
    let state: PulsarWorkoutMiniPlayerState
    let isInlinePlacement: Bool
    let usesNativeAccessoryChrome: Bool
    @ObservedObject var layoutController: PulsarBottomChromeLayoutController
    let onOpen: () -> Void

    var body: some View {
        let _ = PulsarPerformanceDiagnostics.event("workout.miniHost.body")
        PulsarWorkoutMiniPlayerView(
            state: state,
            usesNativeAccessoryChrome: usesNativeAccessoryChrome,
            layoutController: layoutController,
            onOpen: onOpen
        )
        .padding(.horizontal, isInlinePlacement ? 6 : 0)
        .padding(.vertical, isInlinePlacement ? 2 : 0)
        .frame(
            height: usesNativeAccessoryChrome
                ? PulsarWorkoutMiniPlayerSizing.stableNativeAccessoryHeight
                : (layoutController.effectiveLayout == .compact ? 48 : 60)
        )
        .frame(minWidth: 1, maxWidth: .infinity)
        .accessibilitySortPriority(10)
    }
}

#Preview {
    PulsarRootView()
}
