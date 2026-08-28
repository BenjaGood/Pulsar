//
//  FitnessView.swift
//  Pulsar
//

import SwiftUI

struct FitnessView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let runCoordinator: PulsarRunCoordinator
    private let activeWorkoutManager: PulsarActiveWorkoutManager
    @ObservedObject private var profileStore: ProfileStore
    @StateObject private var weekViewModel = FitnessWeekViewModel()
    @StateObject private var progressViewModel = ExerciseProgressViewModel()
    @StateObject private var gymSettingsStore = GymSettingsStore()
    @State private var refreshCoordinator = FitnessRefreshCoordinator()
    private let watchSyncStore = PulsarWatchConnectivitySyncStore.shared
    @State private var isShowingWorkoutPicker = false
    @State private var pendingWorkoutSelection: WorkoutOption?
    @State private var isActivityLogExpanded = false
    @State private var selectedPersonalizedWorkout: PersonalizedWorkoutKind?
    @State private var selectedOutdoorWorkoutKind: PulsarOutdoorWorkoutKind?
    @State private var selectedHistoricalActivity: WeeklyActivity?
    @State private var destinationLifecycle = FitnessDestinationLifecycle.offscreen
    @State private var destinationAppearanceID = 0
    @State private var hasStartedInitialLoad = false
    @State private var didCompleteInitialLoad = false
    @State private var initialLoadTask: Task<Bool, Never>?
    @State private var needsDeferredDataRefresh = false
    @State private var destinationCacheState = PulsarPerformanceCacheState.cold
    @State private var destinationSelectionToken: PulsarTabSelectionToken?
    @ObservedObject private var bottomChromeLayoutStore: PulsarBottomChromeLayoutStore

    @MainActor
    init(
        profileStore: ProfileStore,
        bottomChromeLayoutStore: PulsarBottomChromeLayoutStore,
        runCoordinator: PulsarRunCoordinator,
        activeWorkoutManager: PulsarActiveWorkoutManager
    ) {
        self.profileStore = profileStore
        self.runCoordinator = runCoordinator
        self.activeWorkoutManager = activeWorkoutManager
        self._bottomChromeLayoutStore = ObservedObject(wrappedValue: bottomChromeLayoutStore)
    }

    var body: some View {
        PulsarPerformanceSignposts.measureTabDestinationBody(.fitness) {
            NavigationStack {
            PulsarScreenScaffold(
                layoutStore: bottomChromeLayoutStore,
                header: PulsarScreenHeaderConfiguration(
                    title: "Fitness",
                    trailing: [
                        .systemImage(
                            "plus",
                            accessibilityLabel: "Add workout",
                            action: presentWorkoutPicker
                        )
                    ]
                ),
                horizontalPadding: PulsarTabLayout.horizontalPadding,
                spacing: PulsarTabLayout.sectionSpacing,
                onRefresh: {
                    await performRefresh(.full)
                },
                background: {
                    PulsarTabWallpaper(style: .fitness)
                },
                expandedHeader: {
                    FitnessPageTitleHeader {
                        presentWorkoutPicker()
                    }
                },
                content: {
                    FitnessWeekNavigationSection(
                        week: weekViewModel.selectedWeek,
                        canMoveToNextWeek: weekViewModel.canMoveToNextWeek,
                        isRefreshing: weekViewModel.isRefreshingWeeks,
                        onPrevious: {
                            Task { await performRefresh(.previousWeek) }
                        },
                        onNext: {
                            Task { await performRefresh(.nextWeek) }
                        },
                        onCurrent: {
                            Task { await performRefresh(.currentWeek) }
                        }
                    )
                    .equatable()

                    FitnessMuscleFocusSection(
                        viewModel: weekViewModel.muscleMatrixViewModel,
                        isDestinationUseful: destinationLifecycle == .useful
                    )
                        .equatable()

                    FitnessProgressDashboardSection(
                        viewModel: progressViewModel,
                        selectedWeek: weekViewModel.selectedWeek,
                        displayUnit: resolvedGymWeightUnit
                    ) {
                        withAnimation(.spring(response: 0.44, dampingFraction: 0.82)) {
                            isShowingWorkoutPicker = true
                        }
                    }
                    .padding(.top, 2)

                    FitnessActivityDashboardSection(
                        week: weekViewModel.selectedWeek,
                        activities: weekViewModel.activities,
                        isLoading: weekViewModel.isLoadingActivities,
                        isExpanded: isActivityLogExpanded,
                        onToggleExpanded: {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                                isActivityLogExpanded.toggle()
                            }
                        },
                        onSelectActivity: { activity in
                            selectedHistoricalActivity = activity
                        }
                    )
                    .equatable()
                }
            )
            .navigationTitle("")
            .toolbarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedHistoricalActivity) { activity in
                FitnessWorkoutDetailView(
                    activity: activity,
                    bottomChromeLayoutStore: bottomChromeLayoutStore
                )
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active, destinationLifecycle != .offscreen {
                    Task {
                        if PulsarWorkoutStartCoordinator.shared.shouldDeferForegroundHealthRefresh {
                            PulsarOuraLogger.log("Fitness sceneBecameActive refresh deferred; Watch start in progress")
                            PulsarWorkoutStartupTrace.diag(
                                "[ForegroundRefresh] fitnessSceneActive deferred=true lifecycle=\(PulsarWorkoutStartCoordinator.shared.phase.name)"
                            )
                            return
                        }
                        PulsarWorkoutStartupTrace.diag(
                            "[ForegroundRefresh] fitnessSceneActive deferred=false lifecycle=\(PulsarWorkoutStartCoordinator.shared.phase.name)"
                        )
                        weekViewModel.startWeekRolloverMonitoring()
                        if didCompleteInitialLoad {
                            await performRefresh(.sceneBecameActive)
                        } else {
                            await refreshCoordinator.waitUntilIdle()
                            guard !didCompleteInitialLoad else { return }
                            startInitialLoad()
                            destinationAppearanceID += 1
                        }
                    }
                } else if newPhase != .active {
                    weekViewModel.stopWeekRolloverMonitoring()
                    refreshCoordinator.cancel()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: PulsarGymWorkoutHistoryStore.didChangeNotification)) { _ in
                guard destinationLifecycle != .offscreen else {
                    needsDeferredDataRefresh = true
                    return
                }
                Task {
                    await performRefresh(.gymHistoryChanged)
                }
            }
            .onChange(of: profileStore.profile.preferredUnits) { _, _ in
                guard destinationLifecycle != .offscreen else {
                    needsDeferredDataRefresh = true
                    return
                }
                Task {
                    await performRefresh(.preferredUnitsChanged)
                }
            }
            .onChange(of: weekViewModel.selectedWeek.id) { _, _ in
                isActivityLogExpanded = false
                guard !refreshCoordinator.isRunning,
                      progressViewModel.needsRefresh(
                          displayUnit: resolvedGymWeightUnit,
                          selectedWeek: weekViewModel.selectedWeek
                      ) else { return }
                Task {
                    await performRefresh(.selectedWeekChanged)
                }
            }
            .sheet(isPresented: $isShowingWorkoutPicker, onDismiss: completePendingWorkoutSelection) {
                WorkoutPickerSheet { workout in
                    pendingWorkoutSelection = workout
                }
                .presentationDetents([.fraction(0.82)])
                .presentationDragIndicator(.visible)
                .presentationBackground(.clear)
                .presentationCornerRadius(36)
                .presentationContentInteraction(.scrolls)
            }
            .fullScreenCover(
                item: $selectedPersonalizedWorkout,
                onDismiss: handlePersonalizedWorkoutDismissed
            ) { workout in
                if workout == .gym {
                    GymWorkoutLaunchFlowView(
                        appUnitPreference: profileStore.profile.preferredUnits,
                        profile: profileStore.profile
                    )
                } else if workout == .indoorRunning {
                    PersonalizedLiveWorkoutExperienceView(workout: workout, profile: profileStore.profile)
                } else {
                    PersonalizedWorkoutStartView(workout: workout)
                }
            }
            .fullScreenCover(
                item: $selectedOutdoorWorkoutKind,
                onDismiss: handleOutdoorWorkoutDismissed
            ) { workoutKind in
                PulsarRunIntroExperienceView(
                    coordinator: runCoordinator,
                    workoutKind: workoutKind,
                    profile: profileStore.profile,
                    onMinimize: {
                        activeWorkoutManager.minimizeRunWorkout(
                            runCoordinator.snapshot.workoutKind,
                            sessionID: runCoordinator.ensureActiveWorkoutSessionID(reason: "fitnessIntroMinimize")
                        )
                    }
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear(perform: destinationDidAppear)
        .onDisappear {
            destinationLifecycle = .offscreen
            weekViewModel.stopWeekRolloverMonitoring()
        }
            .task(id: destinationAppearanceID) {
                let appearanceID = destinationAppearanceID
                let selectionToken = destinationSelectionToken
                await markDestinationUsefulAfterInitialRender(
                    appearanceID: appearanceID,
                    selectionToken: selectionToken
                )
            }
        }
        .pulsarFitnessMonochromeAppearance()
    }

    @MainActor
    @discardableResult
    private func performRefresh(_ request: FitnessRefreshRequest) async -> Bool {
        if request != .initial,
           !didCompleteInitialLoad,
           let initialLoadTask {
            guard await initialLoadTask.value else { return false }
        }

        let displayUnit = resolvedGymWeightUnit
        return await refreshCoordinator.run(
            priority: request.priority,
            skipIfBusy: request.priority == .maintenance
        ) {
            let token = PulsarPerformanceSignposts.beginFitnessTabRefresh(
                selectionToken: selectionToken(for: request),
                stale: refreshIsStale(request, displayUnit: displayUnit)
            )
            var outcome = PulsarPerformanceOutcome.cancelled
            defer {
                PulsarPerformanceSignposts.endFitnessTabRefresh(token, outcome: outcome)
            }

            switch request {
            case .initial:
                watchSyncStore.pruneStaleActiveWorkoutState(reason: "fitnessTask")
                await weekViewModel.load()
                guard !Task.isCancelled else { return }
                await progressViewModel.load(
                    displayUnit: displayUnit,
                    selectedWeek: weekViewModel.selectedWeek
                )
            case .warmReappear:
                watchSyncStore.pruneStaleActiveWorkoutState(reason: "fitnessWarmReappear")
                await performStaleAwareRefresh(displayUnit: displayUnit)
            case .deferredDataChanged:
                await weekViewModel.refreshCurrentWeekIfNeeded(force: true)
                guard !Task.isCancelled else { return }
                await progressViewModel.refresh(
                    displayUnit: displayUnit,
                    selectedWeek: weekViewModel.selectedWeek,
                    force: true
                )
            case .sceneBecameActive:
                watchSyncStore.pruneStaleActiveWorkoutState(reason: "fitnessSceneBecameActive")
                await performStaleAwareRefresh(displayUnit: displayUnit)
            case .gymHistoryChanged:
                await weekViewModel.refreshCurrentWeekIfNeeded(force: true)
                guard !Task.isCancelled else { return }
                await progressViewModel.refresh(
                    displayUnit: displayUnit,
                    selectedWeek: weekViewModel.selectedWeek,
                    force: true
                )
            case .preferredUnitsChanged:
                await progressViewModel.refresh(
                    displayUnit: displayUnit,
                    selectedWeek: weekViewModel.selectedWeek,
                    force: true
                )
            case .selectedWeekChanged:
                await progressViewModel.selectWeek(
                    weekViewModel.selectedWeek,
                    displayUnit: displayUnit
                )
            case .previousWeek:
                await weekViewModel.selectPreviousWeek()
                guard !Task.isCancelled else { return }
                await progressViewModel.selectWeek(
                    weekViewModel.selectedWeek,
                    displayUnit: displayUnit
                )
            case .nextWeek:
                await weekViewModel.selectNextWeek()
                guard !Task.isCancelled else { return }
                await progressViewModel.selectWeek(
                    weekViewModel.selectedWeek,
                    displayUnit: displayUnit
                )
            case .currentWeek:
                await weekViewModel.selectCurrentWeek()
                guard !Task.isCancelled else { return }
                await progressViewModel.selectWeek(
                    weekViewModel.selectedWeek,
                    displayUnit: displayUnit
                )
            case .full:
                await weekViewModel.refresh()
                guard !Task.isCancelled else { return }
                await progressViewModel.refresh(
                    displayUnit: displayUnit,
                    selectedWeek: weekViewModel.selectedWeek,
                    force: true
                )
            }
            if !Task.isCancelled {
                outcome = .completed
            }
        }
    }

    @MainActor
    private func destinationDidAppear() {
        destinationCacheState = didCompleteInitialLoad ? .warm : .cold
        destinationLifecycle = .entering
        destinationAppearanceID += 1
        weekViewModel.startWeekRolloverMonitoring()
        destinationSelectionToken = PulsarPerformanceSignposts.markTabDestinationAppeared(.fitness)

        if !hasStartedInitialLoad {
            hasStartedInitialLoad = true
            startInitialLoad()
        } else if !didCompleteInitialLoad, !refreshCoordinator.isRunning {
            // Scene deactivation is allowed to cancel the load. Resume it when
            // this retained destination becomes active again.
            startInitialLoad()
        }
    }

    @MainActor
    private func startInitialLoad() {
        initialLoadTask = Task {
            let didComplete = await performRefresh(.initial)
            didCompleteInitialLoad = didComplete
            return didComplete
        }
    }

    @MainActor
    private func markDestinationUsefulAfterInitialRender(
        appearanceID: Int,
        selectionToken: PulsarTabSelectionToken?
    ) async {
        guard destinationLifecycle == .entering else { return }

        // Yield through the first retained-host render transaction. This is tied
        // to destination lifecycle instead of a guessed wall-clock delay, so the
        // lightweight scaffold can commit before the map enables GPU raster work.
        await Task.yield()
        if destinationCacheState == .cold {
            guard let initialLoadTask, await initialLoadTask.value else { return }
        }
        guard !Task.isCancelled,
              destinationAppearanceID == appearanceID,
              destinationLifecycle == .entering else { return }
        if let selectionToken {
            PulsarPerformanceSignposts.markTabDestinationUseful(
                selectionToken,
                cacheState: destinationCacheState
            )
        }
        destinationLifecycle = .useful

        guard didCompleteInitialLoad else { return }
        let request: FitnessRefreshRequest = needsDeferredDataRefresh
            ? .deferredDataChanged
            : .warmReappear
        needsDeferredDataRefresh = false
        Task {
            await performRefresh(request)
        }
    }

    @MainActor
    private func refreshIsStale(
        _ request: FitnessRefreshRequest,
        displayUnit: PulsarWeightUnit
    ) -> Bool {
        switch request {
        case .warmReappear, .sceneBecameActive:
            weekViewModel.currentWeekRefreshIsStale || progressViewModel.needsRefresh(
                displayUnit: displayUnit,
                selectedWeek: weekViewModel.selectedWeek
            )
        case .initial,
             .deferredDataChanged,
             .gymHistoryChanged,
             .preferredUnitsChanged,
             .selectedWeekChanged,
             .previousWeek,
             .nextWeek,
             .currentWeek,
             .full:
            true
        }
    }

    @MainActor
    private func selectionToken(
        for request: FitnessRefreshRequest
    ) -> PulsarTabSelectionToken? {
        switch request {
        case .initial, .warmReappear, .deferredDataChanged:
            destinationSelectionToken
        case .sceneBecameActive,
             .gymHistoryChanged,
             .preferredUnitsChanged,
             .selectedWeekChanged,
             .previousWeek,
             .nextWeek,
             .currentWeek,
             .full:
            nil
        }
    }

    @MainActor
    private func performStaleAwareRefresh(displayUnit: PulsarWeightUnit) async {
        if weekViewModel.currentWeekRefreshIsStale {
            await weekViewModel.refreshCurrentWeekIfNeeded()
        }
        guard !Task.isCancelled else { return }
        await progressViewModel.refreshIfNeeded(
            displayUnit: displayUnit,
            selectedWeek: weekViewModel.selectedWeek
        )
    }

    private var resolvedGymWeightUnit: PulsarWeightUnit {
        gymSettingsStore.resolvedWeightUnit(appUnits: profileStore.profile.preferredUnits)
    }

    private func presentWorkoutPicker() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        isShowingWorkoutPicker = true
    }

    private func completePendingWorkoutSelection() {
        guard let workout = pendingWorkoutSelection else { return }
        pendingWorkoutSelection = nil

        if let outdoorWorkoutKind = workout.outdoorWorkoutKind {
            activeWorkoutManager.beginRootPresentationHandoff(
                reason: "fitnessRunLaunchCover"
            )
            selectedOutdoorWorkoutKind = outdoorWorkoutKind
        } else {
            selectedPersonalizedWorkout = workout.personalizedKind
        }
    }

    private func handlePersonalizedWorkoutDismissed() {
        PulsarWorkoutStartupTrace.diag(
            "[WorkoutUI] launchCoverOnDismiss begin presentationState=\(activeWorkoutManager.presentationState.diagnosticName) session=\(activeWorkoutManager.activeWorkout?.sessionID.uuidString ?? "none") \(PulsarWorkoutStartupTrace.threadTag())"
        )
        if activeWorkoutManager.completeRootPresentationHandoff(
            reason: "fitnessLaunchCoverDismissed"
        ) {
            // The root sheet is beginning its first transaction. Refresh the
            // historical Fitness dashboards on the next useful Fitness pass,
            // not in the same scene update as modal handoff.
            needsDeferredDataRefresh = true
            PulsarPerformanceDiagnostics.checkpoint("workout.handoff.fitnessRefreshDeferred")
            return
        }

        if activeWorkoutManager.reconcileLaunchOwnerDismissal(
            reason: "fitnessLaunchCoverDismissedWithoutHandoff"
        ) {
            // A local Gym cover vanished without its explicit minimize/finish
            // callback. Preserve the live session through the mini player and
            // avoid competing dashboard work during that reconciliation.
            needsDeferredDataRefresh = true
            PulsarPerformanceDiagnostics.checkpoint("workout.launchOwner.dismissedToMini")
            return
        }

        Task {
            await performRefresh(.full)
        }
    }

    private func handleOutdoorWorkoutDismissed() {
        if activeWorkoutManager.completeRootPresentationHandoff(
            reason: "fitnessRunLaunchCoverDismissed"
        ) {
            needsDeferredDataRefresh = true
            PulsarPerformanceDiagnostics.checkpoint("workout.runHandoff.presented")
            return
        }

        if activeWorkoutManager.reconcileLaunchOwnerDismissal(
            reason: "fitnessRunCoverDismissed"
        ) {
            needsDeferredDataRefresh = true
            PulsarPerformanceDiagnostics.checkpoint("workout.runLaunchOwner.dismissedToMini")
            return
        }

        Task {
            await performRefresh(.full)
        }
    }

}

private enum FitnessRefreshRequest: Equatable {
    case initial
    case warmReappear
    case deferredDataChanged
    case sceneBecameActive
    case gymHistoryChanged
    case preferredUnitsChanged
    case selectedWeekChanged
    case previousWeek
    case nextWeek
    case currentWeek
    case full

    var priority: FitnessRefreshPriority {
        switch self {
        case .warmReappear, .sceneBecameActive:
            .maintenance
        case .selectedWeekChanged, .previousWeek, .nextWeek, .currentWeek, .preferredUnitsChanged:
            .userInitiated
        case .initial, .deferredDataChanged, .gymHistoryChanged, .full:
            .authoritative
        }
    }
}

private struct FitnessWeekNavigationSection: View, Equatable {
    let week: WeekPeriod
    let canMoveToNextWeek: Bool
    let isRefreshing: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onCurrent: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.week == rhs.week &&
            lhs.canMoveToNextWeek == rhs.canMoveToNextWeek &&
            lhs.isRefreshing == rhs.isRefreshing
    }

    var body: some View {
        FitnessWeekHeaderView(
            week: week,
            canMoveToNextWeek: canMoveToNextWeek,
            isRefreshing: isRefreshing,
            onPrevious: onPrevious,
            onNext: onNext,
            onCurrent: onCurrent
        )
    }
}

private struct FitnessMuscleFocusSection: View, Equatable {
    let viewModel: MuscleMatrixViewModel
    let isDestinationUseful: Bool
    @State private var presentation: MuscleFocusMapPresentation?
    @State private var preparedViewModel: MuscleMatrixViewModel?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.viewModel == rhs.viewModel &&
            lhs.isDestinationUseful == rhs.isDestinationUseful
    }

    var body: some View {
        MuscleFocusMapCard(
            isCurrentWeek: viewModel.week.isCurrentWeek,
            presentation: presentation,
            isDestinationUseful: isDestinationUseful
        )
        .task(id: PreparationID(viewModel: viewModel, isDestinationUseful: isDestinationUseful)) {
            guard isDestinationUseful, preparedViewModel != viewModel else { return }
            presentation = MuscleFocusMapPresentation(viewModel: viewModel)
            preparedViewModel = viewModel
        }
    }

    private struct PreparationID: Hashable {
        var viewModel: MuscleMatrixViewModel
        var isDestinationUseful: Bool
    }
}

private enum FitnessDestinationLifecycle: Equatable {
    case offscreen
    case entering
    case useful
}

private struct FitnessProgressDashboardSection: View {
    @ObservedObject var viewModel: ExerciseProgressViewModel
    let selectedWeek: WeekPeriod
    let displayUnit: PulsarWeightUnit
    let onAddWorkout: () -> Void

    var body: some View {
        DailyExerciseProgressSection(
            viewModel: viewModel,
            selectedWeek: selectedWeek,
            displayUnit: displayUnit,
            onStartWorkout: onAddWorkout
        )
    }
}

private struct FitnessActivityDashboardSection: View, Equatable {
    let week: WeekPeriod
    let activities: [WeeklyActivity]
    let isLoading: Bool
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    let onSelectActivity: (WeeklyActivity) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.week == rhs.week &&
            lhs.activities == rhs.activities &&
            lhs.isLoading == rhs.isLoading &&
            lhs.isExpanded == rhs.isExpanded
    }

    var body: some View {
        FitnessActivityLogSection(
            week: week,
            activities: activities,
            isLoading: isLoading,
            isExpanded: isExpanded,
            onToggleExpanded: onToggleExpanded,
            onSelectActivity: onSelectActivity
        )
    }
}

private struct FitnessPageTitleHeader: View {
    var onAddWorkout: () -> Void

    var body: some View {
        PulsarTabHeader(
            systemImage: "figure.run",
            title: "Fitness",
            subtitle: "Train smarter. Every day.",
            onAdd: onAddWorkout,
            addAccessibilityLabel: "Add workout"
        )
    }
}

#Preview {
    FitnessView(
        profileStore: ProfileStore(sideEffectsEnabled: false),
        bottomChromeLayoutStore: PulsarBottomChromeLayoutStore(),
        runCoordinator: PulsarRunCoordinator(),
        activeWorkoutManager: PulsarActiveWorkoutManager()
    )
        .environmentObject(WorkoutCompletionPresentationStore())
}
