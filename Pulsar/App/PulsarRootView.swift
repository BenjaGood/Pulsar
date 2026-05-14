//
//  PulsarRootView.swift
//  Pulsar
//

import SwiftUI

struct PulsarRootView: View {
    @State private var selectedTab: PulsarTab? = .home
    @State private var selectedExtraModule: PulsarExtraModule?
    @State private var isShowingMoreMenu = false
    @StateObject private var homeViewModel = HomeViewModel()
    @StateObject private var runCoordinator = PulsarRunCoordinator()
    @StateObject private var watchSyncStore = PulsarWatchConnectivitySyncStore.shared
    @StateObject private var activeWorkoutManager = PulsarActiveWorkoutManager()
    @StateObject private var bottomChromeState = PulsarBottomChromeState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            activeRootContent
                .id(activeRootDestinationKey)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity.combined(with: .scale(scale: 0.995)))

            if isShowingMoreMenu {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        closeMoreMenu()
                    }
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
        .tint(.accentColor)
        .overlay(alignment: .bottom) {
            PulsarBottomChrome(
                selectedTab: selectedTab,
                selectedExtraModule: selectedExtraModule,
                isShowingMoreMenu: isShowingMoreMenu,
                compactProgress: bottomChromeState.compactProgress,
                mode: bottomChromeMode,
                miniPlayer: activeWorkoutMiniPlayerState,
                onMiniPlayerTapped: openActiveWorkoutMiniPlayer,
                onMiniPlayerPrimaryAction: handleActiveWorkoutMiniPlayerAction,
                onMoreTapped: toggleMoreMenu,
                onTabSelected: selectTab,
                onHeightChanged: bottomChromeState.updateVisibleChromeHeight
            )
            .zIndex(10)
        }
        .overlay(alignment: .bottomTrailing) {
            if isShowingMoreMenu {
                PulsarMoreModulesMenu(
                    onLabTapped: openLab,
                    onCycleTapped: openCycle,
                    onDismiss: {
                        closeMoreMenu()
                    }
                )
                .padding(.horizontal, 14)
                .padding(.bottom, moreMenuBottomPadding)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.92, anchor: .bottomTrailing).combined(with: .opacity),
                    removal: .scale(scale: 0.96, anchor: .bottomTrailing).combined(with: .opacity)
                ))
                .zIndex(20)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: isShowingMoreMenu)
        .environment(\.pulsarBottomChromeState, bottomChromeState)
        .environmentObject(bottomChromeState)
        .environmentObject(activeWorkoutManager)
        .environmentObject(runCoordinator)
        .fullScreenCover(item: $activeWorkoutManager.presentedWorkout) { workout in
            presentedWorkoutView(workout)
        }
        .task {
            await homeViewModel.requestInitialAppEntrySync()
            watchSyncStore.pruneStaleActiveWorkoutState(reason: "rootTask")
            await GymLiveActivityManager.endStaleActivitiesIfNeeded(activeState: watchSyncStore.activeGymState)
            reconcileActiveWorkoutRoute(watchSyncStore.activeWorkoutState, reason: "rootTask")
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else {
                isShowingMoreMenu = false
                return
            }
            Task {
                await homeViewModel.appDidBecomeActive()
                watchSyncStore.pruneStaleActiveWorkoutState(reason: "sceneBecameActive")
                await GymLiveActivityManager.endStaleActivitiesIfNeeded(activeState: watchSyncStore.activeGymState)
                reconcileActiveWorkoutRoute(watchSyncStore.activeWorkoutState, reason: "sceneBecameActive")
            }
        }
        .onChange(of: runCoordinator.snapshot.phase) { _, newPhase in
            if !newPhase.isActiveWorkoutPhase {
                activeWorkoutManager.clearRunWorkout()
            }
        }
        .onChange(of: watchSyncStore.activeGymState?.isFinished) { _, isFinished in
            if isFinished == true {
                activeWorkoutManager.clearWatchGymWorkout()
            }
        }
        .onChange(of: watchSyncStore.activeWorkoutState) { _, state in
            reconcileActiveWorkoutRoute(state, reason: "activeWorkoutSyncChanged")
        }
        .onChange(of: activeWorkoutMiniPlayerState?.id) { _, newID in
            if newID != nil {
                bottomChromeState.expandForInteraction()
            }
        }
        .onChange(of: bottomChromeMode) { _, newMode in
            #if DEBUG
            print("[BottomChrome] mode=\(newMode) hasWorkout=\(activeWorkoutMiniPlayerState != nil)")
            #endif
        }
    }

    @ViewBuilder
    private var activeRootContent: some View {
        if let selectedExtraModule {
            switch selectedExtraModule {
            case .lab:
                LabView(profileStore: homeViewModel.profileStore)
            case .cycle:
                CycleView()
            }
        } else {
            switch selectedTab ?? .home {
            case .home:
                HomeView(viewModel: homeViewModel)
            case .fitness:
                FitnessView(profileStore: homeViewModel.profileStore)
                    .environmentObject(runCoordinator)
            case .food:
                FoodView()
            case .insights:
                InsightsView()
            }
        }
    }

    private var activeRootDestinationKey: String {
        if let selectedExtraModule {
            return "module-\(selectedExtraModule.rawValue)"
        }

        return "tab-\((selectedTab ?? .home).rawValue)"
    }

    private var activeWorkoutMiniPlayerState: PulsarWorkoutMiniPlayerState? {
        if let runState = runMiniPlayerState {
            return runState
        }

        if let gymState = gymMiniPlayerState {
            return gymState
        }

        return watchGymMiniPlayerState
    }

    private var runMiniPlayerState: PulsarWorkoutMiniPlayerState? {
        let snapshot = runCoordinator.snapshot
        guard snapshot.phase.isActiveWorkoutPhase,
              activeWorkoutManager.minimizedRunWorkoutKind != nil,
              activeWorkoutManager.presentedWorkout != .run(snapshot.workoutKind) else { return nil }

        let heartRateText = snapshot.currentHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "HR unavailable"
        let detail = snapshot.distanceMeters > 10
            ? "\(PulsarRunFormatters.distance(snapshot.distanceMeters)) · \(PulsarRunFormatters.pace(snapshot.currentPaceSecondsPerKilometer))"
            : snapshot.source.label

        return PulsarWorkoutMiniPlayerState(
            id: "run-\(snapshot.workoutKind.rawValue)",
            kind: .run(snapshot.workoutKind),
            title: snapshot.workoutKind.displayName,
            subtitle: snapshot.phase == .paused ? "Paused" : "Live workout",
            metrics: "\(PulsarRunFormatters.duration(snapshot.elapsedTime)) · \(heartRateText)",
            detail: detail,
            symbol: snapshot.workoutKind.systemImageName,
            isPaused: snapshot.phase == .paused
        )
    }

    private var gymMiniPlayerState: PulsarWorkoutMiniPlayerState? {
        guard let viewModel = activeWorkoutManager.gymSessionViewModel,
              viewModel.summary == nil,
              activeWorkoutManager.isGymWorkoutMinimized,
              activeWorkoutManager.presentedWorkout != .gym else { return nil }

        let heartRateText = viewModel.currentHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "HR unavailable"
        return PulsarWorkoutMiniPlayerState(
            id: "gym-\(viewModel.session.id.uuidString)",
            kind: .gym,
            title: viewModel.session.routineName,
            subtitle: "Gym workout",
            metrics: "\(PulsarGymFormatters.duration(viewModel.elapsedSeconds)) · \(heartRateText)",
            detail: "\(viewModel.completedSetsCount)/\(viewModel.totalSetsCount) sets",
            symbol: "dumbbell.fill",
            isPaused: false
        )
    }

    private var watchGymMiniPlayerState: PulsarWorkoutMiniPlayerState? {
        guard let state = watchSyncStore.activeGymState,
              !state.isFinished,
              watchSyncStore.isRoutableActiveGymState(state),
              activeWorkoutManager.gymSessionViewModel == nil,
              activeWorkoutManager.presentedWorkout != .watchGym else { return nil }

        let heartRateText = state.currentHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "HR unavailable"
        return PulsarWorkoutMiniPlayerState(
            id: "watch-gym-\(state.sessionId.uuidString)",
            kind: .watchGym,
            title: state.routineName,
            subtitle: "Apple Watch Gym",
            metrics: "\(PulsarGymFormatters.duration(state.elapsedSeconds)) · \(heartRateText)",
            detail: state.progressText,
            symbol: "applewatch",
            isPaused: false
        )
    }

    private var moreMenuBottomPadding: CGFloat {
        bottomChromeState.visibleChromeHeight + 12
    }

    private var bottomChromeMode: PulsarBottomChromeMode {
        PulsarBottomChromeMode(
            phase: bottomChromeState.phase,
            hasWorkout: activeWorkoutMiniPlayerState != nil
        )
    }

    private func selectTab(_ tab: PulsarTab) {
        UISelectionFeedbackGenerator().selectionChanged()
        bottomChromeState.prepareForRootTransition()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.88, blendDuration: 0.06)) {
            selectedTab = tab
            selectedExtraModule = nil
        }
        closeMoreMenu(emitHaptic: false, restoreCompactIfScrolledDown: false)
    }

    private func toggleMoreMenu() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        if !isShowingMoreMenu {
            bottomChromeState.expandForInteraction()
        } else {
            bottomChromeState.restoreCompactIfScrolledDown()
        }
        isShowingMoreMenu.toggle()
    }

    private func closeMoreMenu(emitHaptic: Bool = true, restoreCompactIfScrolledDown: Bool = true) {
        guard isShowingMoreMenu else { return }
        if emitHaptic {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        isShowingMoreMenu = false
        if restoreCompactIfScrolledDown {
            bottomChromeState.restoreCompactIfScrolledDown()
        }
    }

    private func openCycle() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        bottomChromeState.prepareForRootTransition()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.88, blendDuration: 0.06)) {
            selectedTab = nil
            selectedExtraModule = .cycle
            isShowingMoreMenu = false
        }
    }

    private func openLab() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        bottomChromeState.prepareForRootTransition()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.88, blendDuration: 0.06)) {
            selectedTab = nil
            selectedExtraModule = .lab
            isShowingMoreMenu = false
        }
    }

    private func openActiveWorkoutMiniPlayer() {
        guard let state = activeWorkoutMiniPlayerState else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        bottomChromeState.expandForInteraction()
        switch state.kind {
        case .run(let workoutKind):
            activeWorkoutManager.presentRunWorkout(workoutKind)
        case .gym:
            activeWorkoutManager.presentGymWorkout()
        case .watchGym:
            activeWorkoutManager.presentWatchGymWorkout()
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

    private func reconcileActiveWorkoutRoute(_ state: PulsarActiveWorkoutSyncState?, reason: String) {
        guard let state else { return }
        if state.isEnded {
            if case .outdoor = state.kind {
                activeWorkoutManager.clearRunWorkout()
            } else if case .gym = state.kind {
                activeWorkoutManager.clearWatchGymWorkout()
            }
            return
        }

        switch state.kind {
        case .outdoor(let workoutKind):
            let localRunIsActive = runCoordinator.snapshot.phase.isActiveWorkoutPhase &&
                runCoordinator.snapshot.pulsarWorkoutSessionId == state.sessionId
            guard localRunIsActive || watchSyncStore.isRoutableActiveWorkoutState(state) else {
                activeWorkoutManager.clearRunWorkout()
                PulsarSyncDebugLogger.log("iPhone active workout UI route skipped reason=\(reason) session=\(state.sessionId.uuidString) type=\(workoutKind.rawValue) staleReason=\(state.staleRouteReason() ?? "unknown")")
                return
            }
            runCoordinator.reconcileActiveWorkoutSyncState(state)
            guard activeWorkoutManager.presentedWorkout != .run(workoutKind) else { return }
            activeWorkoutManager.presentRunWorkout(workoutKind)
            PulsarSyncDebugLogger.log("iPhone active workout UI route opened reason=\(reason) session=\(state.sessionId.uuidString) type=\(workoutKind.rawValue)")
        case .gym:
            let activeGymState = watchSyncStore.activeGymState
            let gymStateIsRoutable = activeGymState?.sessionId == state.sessionId &&
                activeGymState.map { watchSyncStore.isRoutableActiveGymState($0) } == true
            guard gymStateIsRoutable || watchSyncStore.isRoutableActiveWorkoutState(state) else {
                activeWorkoutManager.clearWatchGymWorkout()
                PulsarSyncDebugLogger.log("iPhone active gym mirror UI route skipped reason=\(reason) session=\(state.sessionId.uuidString) type=\(state.kind.workoutTypeRawValue) staleReason=\(state.staleRouteReason() ?? activeGymState?.staleRouteReason() ?? "unknown")")
                return
            }
            guard activeWorkoutManager.gymSessionViewModel == nil else { return }
            guard activeWorkoutManager.presentedWorkout != .watchGym else { return }
            activeWorkoutManager.presentWatchGymWorkout()
            PulsarSyncDebugLogger.log("iPhone active gym mirror UI route opened reason=\(reason) session=\(state.sessionId.uuidString) type=\(state.kind.workoutTypeRawValue)")
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
                    activeWorkoutManager.minimizeRunWorkout(runCoordinator.snapshot.workoutKind)
                }
            )
        case .gym:
            if let viewModel = activeWorkoutManager.gymSessionViewModel {
                GymWorkoutSessionView(
                    viewModel: viewModel,
                    onMinimize: {
                        activeWorkoutManager.minimizeGymWorkout()
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
                activeWorkoutManager.minimizeWatchGymWorkout()
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
}

private enum PulsarTab: String, Hashable, CaseIterable {
    case home
    case fitness
    case food
    case insights

    var title: String {
        switch self {
        case .home: "Home"
        case .fitness: "Fitness"
        case .food: "Food"
        case .insights: "Mindfulness"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .fitness: "figure.run"
        case .food: "leaf.circle.fill"
        case .insights: "figure.mind.and.body"
        }
    }
}

private enum PulsarExtraModule: String, Hashable, CaseIterable {
    case lab
    case cycle

    var title: String {
        switch self {
        case .lab: "Lab"
        case .cycle: "Cycle"
        }
    }

    var subtitle: String {
        switch self {
        case .lab: "Biological age, biomarkers, and health trajectory"
        case .cycle: "Phases, symptoms, and wellness trends"
        }
    }

    var symbol: String {
        switch self {
        case .lab: "testtube.2"
        case .cycle: "moonphase.waxing.crescent"
        }
    }
}

private struct PulsarWorkoutMiniPlayerState {
    enum Kind {
        case run(PulsarOutdoorWorkoutKind)
        case gym
        case watchGym
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    let metrics: String
    let detail: String
    let symbol: String
    let isPaused: Bool
}

private enum PulsarBottomChromeMode: Equatable {
    case expandedNoWorkout
    case compactNoWorkout
    case expandedWithWorkout
    case collapsedWithWorkout

    init(phase: PulsarBottomChromeState.Phase, hasWorkout: Bool) {
        switch (hasWorkout, phase) {
        case (true, .expanded):
            self = .expandedWithWorkout
        case (true, .compact):
            self = .collapsedWithWorkout
        case (false, .expanded):
            self = .expandedNoWorkout
        case (false, .compact):
            self = .compactNoWorkout
        }
    }
}

private struct PulsarBottomChrome: View {
    let selectedTab: PulsarTab?
    let selectedExtraModule: PulsarExtraModule?
    let isShowingMoreMenu: Bool
    let compactProgress: CGFloat
    let mode: PulsarBottomChromeMode
    let miniPlayer: PulsarWorkoutMiniPlayerState?
    let onMiniPlayerTapped: () -> Void
    let onMiniPlayerPrimaryAction: () -> Void
    let onMoreTapped: () -> Void
    let onTabSelected: (PulsarTab) -> Void
    let onHeightChanged: (CGFloat) -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                if showsExpandedChrome {
                    expandedChrome
                        .offset(y: workoutCollapseProgress * 28)
                        .scaleEffect(1 - workoutCollapseProgress * 0.015, anchor: .bottom)
                        .allowsHitTesting(expandedChromeAllowsHitTesting)
                        .zIndex(0)
                }

                if showsCollapsedWorkoutChrome {
                    collapsedWorkoutChrome
                        .offset(y: (1 - workoutCollapseProgress) * 20)
                        .scaleEffect(0.97 + workoutCollapseProgress * 0.03, anchor: .bottom)
                        .allowsHitTesting(mode == .collapsedWithWorkout)
                        .zIndex(1)
                }

                if let miniPlayer {
                    PulsarMorphingWorkoutMiniPlayer(
                        state: miniPlayer,
                        collapseProgress: workoutCollapseProgress,
                        height: morphingMiniPlayerHeight,
                        onOpen: onMiniPlayerTapped,
                        onPrimaryAction: onMiniPlayerPrimaryAction
                    )
                    .frame(
                        width: morphingMiniPlayerWidth(in: proxy.size.width),
                        height: morphingMiniPlayerHeight
                    )
                    .position(
                        x: morphingMiniPlayerCenterX(in: proxy.size.width),
                        y: morphingMiniPlayerCenterY(in: proxy.size.height)
                    )
                    .allowsHitTesting(workoutCollapseProgress >= 0)
                    .zIndex(2)
                }

                PulsarMoreOrbButton(
                    isActive: isShowingMoreMenu || selectedExtraModule != nil,
                    compactProgress: moreOrbCompactProgress,
                    size: moreOrbSize,
                    action: onMoreTapped
                )
                .position(
                    x: moreOrbCenterX(in: proxy.size.width),
                    y: moreOrbCenterY(in: proxy.size.height)
                )
                .zIndex(4)
            }
        }
        .frame(height: chromeOverlayHeight, alignment: .bottom)
        .padding(.top, miniPlayer == nil ? 0 : 4)
        .animation(.spring(response: 0.44, dampingFraction: 0.88, blendDuration: 0.08), value: mode)
        .animation(.spring(response: 0.38, dampingFraction: 0.84), value: miniPlayer?.id)
        .onAppear {
            onHeightChanged(targetChromeHeight)
        }
        .onChange(of: targetChromeHeight) { _, newHeight in
            onHeightChanged(newHeight)
        }
    }

    private var expandedChrome: some View {
        VStack(spacing: expandedChromeSpacing) {
            if miniPlayer != nil {
                Color.clear
                    .frame(height: fullMiniHeight)
                    .padding(.horizontal, horizontalPadding)
                    .allowsHitTesting(false)
            }

            HStack(spacing: moreGap) {
                PulsarBottomNavigationBar(
                    selectedTab: selectedTab,
                    compactProgress: standardNavCompactProgress,
                    onTabSelected: onTabSelected
                )
                .layoutPriority(1)
                .zIndex(0)

                Color.clear
                    .frame(width: moreOrbSize, height: moreOrbSize)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, bottomPadding)
        }
    }

    private var collapsedWorkoutChrome: some View {
        HStack(spacing: moreGap) {
            PulsarHomeOrbButton(
                isActive: selectedTab == .home && selectedExtraModule == nil,
                action: {
                    onTabSelected(.home)
                }
            )
            .zIndex(3)

            Color.clear
                .frame(height: collapsedRowHeight)
                .allowsHitTesting(false)
                .layoutPriority(1)

            Color.clear
                .frame(width: collapsedOrbSize, height: collapsedOrbSize)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, bottomPadding)
    }

    private var workoutCollapseProgress: CGFloat {
        mode == .collapsedWithWorkout ? 1 : 0
    }

    private var standardNavCompactProgress: CGFloat {
        mode == .compactNoWorkout ? 1 : 0
    }

    private var showsExpandedChrome: Bool {
        switch mode {
        case .expandedWithWorkout, .expandedNoWorkout, .compactNoWorkout:
            true
        case .collapsedWithWorkout:
            false
        }
    }

    private var showsCollapsedWorkoutChrome: Bool {
        mode == .collapsedWithWorkout
    }

    private var expandedChromeAllowsHitTesting: Bool {
        switch mode {
        case .expandedNoWorkout, .compactNoWorkout:
            true
        case .expandedWithWorkout:
            true
        case .collapsedWithWorkout:
            false
        }
    }

    private var morphingMiniPlayerHeight: CGFloat {
        fullMiniHeight + workoutCollapseProgress * (collapsedRowHeight - fullMiniHeight)
    }

    private var moreOrbCompactProgress: CGFloat {
        miniPlayer == nil ? standardNavCompactProgress : 0
    }

    private var moreOrbSize: CGFloat {
        collapsedOrbSize - moreOrbCompactProgress * 8
    }

    private func moreOrbCenterX(in availableWidth: CGFloat) -> CGFloat {
        availableWidth - horizontalPadding - moreOrbSize / 2
    }

    private func moreOrbCenterY(in availableHeight: CGFloat) -> CGFloat {
        availableHeight - bottomPadding - moreOrbSize / 2
    }

    private func morphingMiniPlayerWidth(in availableWidth: CGFloat) -> CGFloat {
        let expandedWidth = max(availableWidth - horizontalPadding * 2, 0)
        let collapsedWidth = max(
            availableWidth - horizontalPadding * 2 - orbSize * 2 - moreGap * 2,
            156
        )
        return expandedWidth + workoutCollapseProgress * (collapsedWidth - expandedWidth)
    }

    private func morphingMiniPlayerCenterX(in availableWidth: CGFloat) -> CGFloat {
        let expandedX = availableWidth / 2
        let collapsedWidth = morphingMiniPlayerWidth(in: availableWidth)
        let collapsedX = horizontalPadding + orbSize + moreGap + collapsedWidth / 2
        return expandedX + workoutCollapseProgress * (collapsedX - expandedX)
    }

    private func morphingMiniPlayerCenterY(in availableHeight: CGFloat) -> CGFloat {
        let expandedY = fullMiniHeight / 2
        let collapsedY = availableHeight - bottomPadding - collapsedRowHeight / 2
        return expandedY + workoutCollapseProgress * (collapsedY - expandedY)
    }

    private var chromeOverlayHeight: CGFloat {
        miniPlayer == nil ? navChromeHeight : expandedChromeHeight
    }

    private var targetChromeHeight: CGFloat {
        switch mode {
        case .expandedWithWorkout:
            expandedChromeHeight
        case .collapsedWithWorkout:
            collapsedChromeHeight
        case .expandedNoWorkout, .compactNoWorkout:
            navChromeHeight
        }
    }

    private var expandedChromeHeight: CGFloat {
        if miniPlayer == nil {
            return navChromeHeight
        }
        return fullMiniHeight + expandedChromeSpacing + navChromeHeight
    }

    private var collapsedChromeHeight: CGFloat {
        collapsedRowHeight + bottomPadding
    }

    private var expandedChromeSpacing: CGFloat {
        8
    }

    private var horizontalPadding: CGFloat {
        12
    }

    private var moreGap: CGFloat {
        10
    }

    private var bottomPadding: CGFloat { 8 }
    private var fullMiniHeight: CGFloat { 62 }
    private var navChromeHeight: CGFloat { 80 }
    private var collapsedRowHeight: CGFloat { 72 }
    private var orbSize: CGFloat { collapsedOrbSize }
    private var collapsedOrbSize: CGFloat { 72 }
}

private struct PulsarBottomNavigationBar: View {
    let selectedTab: PulsarTab?
    let compactProgress: CGFloat
    let onTabSelected: (PulsarTab) -> Void

    @State private var contentWidth: CGFloat = 0
    @State private var dragLocationX: CGFloat?
    @State private var dragPreviewTab: PulsarTab?
    @State private var dragVelocityX: CGFloat = 0
    @State private var lastDragSample: DragSample?

    private let itemSpacing: CGFloat = 4
    private let tabs = PulsarTab.allCases

    var body: some View {
        ZStack(alignment: .leading) {
            GeometryReader { proxy in
                let layout = navigationLayout(width: proxy.size.width)

                if bubbleTab != nil {
                    PulsarNavigationSelectionBubble(
                        isDragging: dragLocationX != nil,
                        stretch: bubbleStretch(layout: layout),
                        direction: dragDirection,
                        compactProgress: compactProgress
                    )
                    .frame(width: bubbleWidth(layout: layout), height: itemHeight)
                    .position(x: bubbleCenterX(layout: layout), y: itemHeight / 2)
                    .allowsHitTesting(false)
                    .onAppear {
                        contentWidth = proxy.size.width
                    }
                    .onChange(of: proxy.size.width) { _, newWidth in
                        contentWidth = newWidth
                    }
                } else {
                    Color.clear
                        .onAppear {
                            contentWidth = proxy.size.width
                        }
                        .onChange(of: proxy.size.width) { _, newWidth in
                            contentWidth = newWidth
                        }
                }
            }
            .frame(height: itemHeight)

            HStack(spacing: itemSpacing) {
                ForEach(tabs, id: \.self) { tab in
                    PulsarNavigationItemButton(
                        tab: tab,
                        isSelected: highlightedTab == tab,
                        compactProgress: compactProgress,
                        height: itemHeight,
                        action: {
                            onTabSelected(tab)
                        }
                    )
                }
            }
            .frame(height: itemHeight)
        }
        .coordinateSpace(name: "PulsarBottomNavigationBar")
        .simultaneousGesture(dragGesture)
        .padding(.horizontal, horizontalInset)
        .padding(.vertical, verticalInset)
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.clear)
                .pulsarLiquidGlass(cornerRadius: cornerRadius)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.38),
                            .white.opacity(0.09),
                            .accentColor.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.12), radius: 20 - compactProgress * 4, x: 0, y: 11 - compactProgress * 3)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("PulsarBottomNavigationBar"))
            .onChanged { value in
                let layout = navigationLayout(width: contentWidth)
                guard layout.itemWidth > 0 else { return }

                let clampedX = layout.clampedCenterX(value.location.x)
                updateDragVelocity(currentX: clampedX)
                dragLocationX = clampedX

                let previewTab = tab(at: clampedX, layout: layout)
                if previewTab != dragPreviewTab {
                    UISelectionFeedbackGenerator().selectionChanged()
                    dragPreviewTab = previewTab
                }
            }
            .onEnded { value in
                let layout = navigationLayout(width: contentWidth)
                let releaseX = layout.clampedCenterX(value.location.x)
                let projectedTravel = (value.predictedEndLocation.x - value.location.x) * 0.18
                let projectedX = layout.clampedCenterX(releaseX + projectedTravel)
                let tab = self.tab(at: projectedX, layout: layout)

                withAnimation(.spring(response: 0.42, dampingFraction: 0.74, blendDuration: 0.08)) {
                    dragLocationX = nil
                    dragPreviewTab = nil
                    dragVelocityX = 0
                    lastDragSample = nil
                }

                onTabSelected(tab)
            }
    }

    private func updateDragVelocity(currentX: CGFloat) {
        let now = Date()
        if let lastDragSample {
            let elapsed = max(now.timeIntervalSince(lastDragSample.date), 0.016)
            dragVelocityX = (currentX - lastDragSample.x) / CGFloat(elapsed)
        }
        lastDragSample = DragSample(x: currentX, date: now)
    }

    private func tab(at locationX: CGFloat, layout: PulsarNavigationLayout) -> PulsarTab {
        let nearestIndex = tabs.indices.min { first, second in
            abs(layout.centerX(for: first) - locationX) < abs(layout.centerX(for: second) - locationX)
        } ?? 0

        return tabs[nearestIndex]
    }

    private func bubbleCenterX(layout: PulsarNavigationLayout) -> CGFloat {
        if let dragLocationX {
            return layout.clampedCenterX(dragLocationX)
        }

        return layout.centerX(for: selectedIndex)
    }

    private func bubbleWidth(layout: PulsarNavigationLayout) -> CGFloat {
        guard dragLocationX != nil, layout.itemWidth > 0 else {
            return layout.itemWidth
        }

        let distanceFromNearest = abs(layout.centerX(for: highlightedIndex) - bubbleCenterX(layout: layout))
        let normalizedDistance = min(distanceFromNearest / max(layout.step / 2, 1), 1)
        let velocityStretch = min(abs(dragVelocityX) / 1_650, 1) * 0.20
        return layout.itemWidth * (1 + normalizedDistance * 0.12 + velocityStretch)
    }

    private func bubbleStretch(layout: PulsarNavigationLayout) -> CGFloat {
        guard dragLocationX != nil else { return 0 }
        let distanceFromNearest = abs(layout.centerX(for: highlightedIndex) - bubbleCenterX(layout: layout))
        let distanceStretch = min(distanceFromNearest / max(layout.step / 2, 1), 1) * 0.5
        let velocityStretch = min(abs(dragVelocityX) / 1_500, 1)
        return min(1, distanceStretch + velocityStretch)
    }

    private func navigationLayout(width: CGFloat) -> PulsarNavigationLayout {
        PulsarNavigationLayout(width: width, itemCount: tabs.count, itemSpacing: itemSpacing)
    }

    private var highlightedTab: PulsarTab? {
        dragPreviewTab ?? selectedTab
    }

    private var bubbleTab: PulsarTab? {
        highlightedTab
    }

    private var selectedIndex: Int {
        tabs.firstIndex(of: selectedTab ?? .home) ?? 0
    }

    private var highlightedIndex: Int {
        tabs.firstIndex(of: highlightedTab ?? selectedTab ?? .home) ?? selectedIndex
    }

    private var dragDirection: CGFloat {
        guard dragVelocityX != 0 else { return 0 }
        return min(max(dragVelocityX / 1_200, -1), 1)
    }

    private var itemHeight: CGFloat {
        56 - compactProgress * 8
    }

    private var horizontalInset: CGFloat {
        10 - compactProgress * 2
    }

    private var verticalInset: CGFloat {
        8 - compactProgress * 2
    }

    private var cornerRadius: CGFloat {
        (itemHeight + verticalInset * 2) / 2
    }

    private struct DragSample {
        var x: CGFloat
        var date: Date
    }
}

private struct PulsarNavigationLayout {
    let width: CGFloat
    let itemCount: Int
    let itemSpacing: CGFloat

    var itemWidth: CGFloat {
        guard itemCount > 0 else { return 0 }
        let spacingWidth = itemSpacing * CGFloat(max(itemCount - 1, 0))
        return max((width - spacingWidth) / CGFloat(itemCount), 0)
    }

    var step: CGFloat {
        itemWidth + itemSpacing
    }

    func centerX(for index: Int) -> CGFloat {
        itemWidth / 2 + CGFloat(index) * step
    }

    func clampedCenterX(_ x: CGFloat) -> CGFloat {
        guard itemCount > 0 else { return x }
        return min(max(x, centerX(for: 0)), centerX(for: itemCount - 1))
    }
}

private struct PulsarNavigationItemButton: View {
    let tab: PulsarTab
    let isSelected: Bool
    let compactProgress: CGFloat
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4 - compactProgress * 4) {
                Image(systemName: tab.symbol)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .medium))
                    .frame(width: 28, height: 26)

                Text(tab.title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.56)
                    .opacity(1 - Double(compactProgress))
                    .frame(height: max(0, 13 * (1 - compactProgress)))
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct PulsarNavigationSelectionBubble: View {
    let isDragging: Bool
    let stretch: CGFloat
    let direction: CGFloat
    let compactProgress: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color.accentColor.opacity(isDragging ? 0.12 : 0.08))
            .pulsarLiquidGlass(cornerRadius: 28)
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.34 + stretch * 0.10),
                                .white.opacity(0.04),
                                .accentColor.opacity(0.18 + stretch * 0.10)
                            ],
                            startPoint: UnitPoint(x: 0.18 + direction * 0.12, y: 0.05),
                            endPoint: UnitPoint(x: 0.92 + direction * 0.10, y: 0.96)
                        )
                    )
                    .blendMode(.screen)
                    .opacity(0.54)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.40),
                                .white.opacity(0.08),
                                .accentColor.opacity(0.20 + stretch * 0.08)
                            ],
                            startPoint: UnitPoint(x: 0.08 + direction * 0.12, y: 0.0),
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .overlay(alignment: .topLeading) {
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.30 + stretch * 0.08))
                    .frame(width: 36 + stretch * 16, height: 8)
                    .blur(radius: 5)
                    .offset(x: 16 + direction * 14, y: 6)
                    .allowsHitTesting(false)
            }
            .scaleEffect(x: 1 + stretch * 0.08, y: 1 - stretch * 0.045)
            .shadow(
                color: .accentColor.opacity(0.13 + stretch * 0.08),
                radius: 15 + stretch * 8 - compactProgress * 3,
                x: direction * 5,
                y: 8 - compactProgress * 2
            )
    }
}

private struct PulsarHomeOrbButton: View {
    let isActive: Bool
    let action: () -> Void

    private let size: CGFloat = 72

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(isActive ? 0.12 : 0.07))
                    .pulsarLiquidGlass(cornerRadius: size / 2)
                    .overlay {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(isActive ? 0.36 : 0.28),
                                        .white.opacity(0.04),
                                        .accentColor.opacity(isActive ? 0.22 : 0.10)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .blendMode(.screen)
                            .opacity(0.58)
                    }
                    .overlay {
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.42),
                                        .white.opacity(0.08),
                                        .accentColor.opacity(isActive ? 0.32 : 0.14)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }

                Image(systemName: PulsarTab.home.symbol)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(PulsarGlassPressButtonStyle())
        .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 10)
        .accessibilityLabel("Home")
        .accessibilityHint("Go to Home")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

private struct PulsarMoreOrbButton: View {
    let isActive: Bool
    let compactProgress: CGFloat
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(isActive ? 0.12 : 0.07))
                    .pulsarLiquidGlass(cornerRadius: size / 2)
                    .overlay {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(isActive ? 0.36 : 0.28),
                                        .white.opacity(0.04),
                                        .accentColor.opacity(isActive ? 0.22 : 0.10)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .blendMode(.screen)
                            .opacity(0.58)
                    }
                    .overlay {
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.42),
                                        .white.opacity(0.08),
                                        .accentColor.opacity(isActive ? 0.32 : 0.14)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }

                Image(systemName: "circle.grid.2x2.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(PulsarGlassPressButtonStyle())
        .shadow(color: .black.opacity(0.12), radius: 18 - compactProgress * 3, x: 0, y: 10 - compactProgress * 2)
        .accessibilityLabel("More")
        .accessibilityHint("Open more health modules")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var iconSize: CGFloat {
        18 - compactProgress * 1.5
    }
}

private struct PulsarMorphingWorkoutMiniPlayer: View {
    let state: PulsarWorkoutMiniPlayerState
    let collapseProgress: CGFloat
    let height: CGFloat
    let onOpen: () -> Void
    let onPrimaryAction: () -> Void

    var body: some View {
        HStack(spacing: contentSpacing) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.15 + collapseProgress * 0.01))

                Image(systemName: state.symbol)
                    .font(.system(size: iconFontSize, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
            }
            .frame(width: iconSize, height: iconSize)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(state.title)
                        .font(.system(size: titleFontSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(state.subtitle)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .opacity(1 - Double(collapseProgress))
                        .frame(maxWidth: 118 * (1 - collapseProgress), alignment: .leading)
                        .clipped()
                }

                Text(state.metrics)
                    .font(.system(size: metricsFontSize, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
            .layoutPriority(1)

            Spacer(minLength: 4)

            Text(state.detail)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: 92 * (1 - collapseProgress), alignment: .trailing)
                .opacity(1 - Double(collapseProgress))
                .clipped()

            Button(action: onPrimaryAction) {
                Image(systemName: primaryActionSymbol)
                    .font(.system(size: actionIconSize, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: actionSize, height: actionSize)
                    .background(.white.opacity(0.10), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.14), lineWidth: 1)
                    }
            }
            .buttonStyle(PulsarGlassPressButtonStyle(scale: 0.9))
            .accessibilityLabel(primaryActionLabel)
        }
        .padding(.leading, leadingPadding)
        .padding(.trailing, trailingPadding)
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .contentShape(Capsule(style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                .fill(tint.opacity(0.06 + collapseProgress * 0.01))
                .pulsarLiquidGlass(cornerRadius: height / 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.38 + collapseProgress * 0.02),
                            .white.opacity(0.08),
                            tint.opacity(0.18 + collapseProgress * 0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .overlay(alignment: .topLeading) {
            Capsule(style: .continuous)
                .fill(.white.opacity(0.24))
                .frame(width: 46 + collapseProgress * 12, height: 8)
                .blur(radius: 6)
                .offset(x: 18, y: 8)
                .allowsHitTesting(false)
        }
        .shadow(color: tint.opacity(0.10 + collapseProgress * 0.02), radius: 18, x: 0, y: 10)
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(state.title), \(state.metrics)")
        .accessibilityHint("Open live workout")
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

    private var contentSpacing: CGFloat { 12 - collapseProgress * 4 }
    private var iconSize: CGFloat { 42 - collapseProgress * 4 }
    private var iconFontSize: CGFloat { 18 - collapseProgress * 2 }
    private var titleFontSize: CGFloat { 15 - collapseProgress }
    private var metricsFontSize: CGFloat { 13 - collapseProgress }
    private var actionSize: CGFloat { 36 - collapseProgress * 4 }
    private var actionIconSize: CGFloat { 14 - collapseProgress }
    private var leadingPadding: CGFloat { 10 - collapseProgress }
    private var trailingPadding: CGFloat { 9 - collapseProgress }
}

private struct PulsarGlassPressButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

private struct PulsarMoreModulesMenu: View {
    let onLabTapped: () -> Void
    let onCycleTapped: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 30, height: 30)
                    .background(Color.accentColor.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("More")
                        .font(.headline.weight(.semibold))
                    Text("Health modules")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            PulsarMoreModuleButton(
                module: .lab,
                tint: .cyan,
                secondaryTint: .green,
                action: onLabTapped
            )

            PulsarMoreModuleButton(
                module: .cycle,
                tint: .pink,
                secondaryTint: .purple,
                action: onCycleTapped
            )
        }
        .padding(14)
        .frame(maxWidth: 318, alignment: .leading)
        .pulsarLiquidGlass(cornerRadius: 30)
        .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 14)
    }
}

private struct PulsarMoreModuleButton: View {
    let module: PulsarExtraModule
    let tint: Color
    let secondaryTint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                moduleIcon
                    .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text(module.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(module.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(module.title)
        .accessibilityHint("Open \(module.title)")
    }

    @ViewBuilder
    private var moduleIcon: some View {
        if module == .lab {
            LabGenomeIconView(size: 42)
        } else {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.22),
                                secondaryTint.opacity(0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: module.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
            }
        }
    }
}

#Preview("Bottom Navigation") {
    VStack {
        Spacer()
        PulsarBottomChrome(
            selectedTab: .home,
            selectedExtraModule: nil,
            isShowingMoreMenu: true,
            compactProgress: 0,
            mode: .expandedNoWorkout,
            miniPlayer: nil,
            onMiniPlayerTapped: {},
            onMiniPlayerPrimaryAction: {},
            onMoreTapped: {},
            onTabSelected: { _ in },
            onHeightChanged: { _ in }
        )
    }
    .background(PulsarSectionBackground())
}

#Preview("More Menu") {
    VStack {
        Spacer()
        HStack {
            PulsarMoreModulesMenu(onLabTapped: {}, onCycleTapped: {}, onDismiss: {})
            Spacer()
        }
    }
    .padding()
    .background(PulsarSectionBackground())
}

#Preview {
    PulsarRootView()
}
