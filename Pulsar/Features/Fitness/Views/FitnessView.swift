//
//  FitnessView.swift
//  Pulsar
//

import SwiftUI

struct FitnessView: View {
    @EnvironmentObject private var runCoordinator: PulsarRunCoordinator
    @EnvironmentObject private var activeWorkoutManager: PulsarActiveWorkoutManager
    @EnvironmentObject private var bottomChromeState: PulsarBottomChromeState
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var profileStore: ProfileStore
    @StateObject private var weekViewModel = FitnessWeekViewModel()
    @StateObject private var progressViewModel = ExerciseProgressViewModel()
    @StateObject private var gymSettingsStore = GymSettingsStore()
    @StateObject private var watchSyncStore = PulsarWatchConnectivitySyncStore.shared
    @State private var isShowingWorkoutPicker = false
    @State private var isShowingWeekHistory = false
    @State private var isActivityLogExpanded = false
    @State private var selectedPersonalizedWorkout: PersonalizedWorkoutKind?
    @State private var selectedOutdoorWorkoutKind: PulsarOutdoorWorkoutKind?
    @State private var isShowingWatchGymMirror = false

    @MainActor
    init(profileStore: ProfileStore) {
        self.profileStore = profileStore
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        FitnessWeekHeaderView(
                            week: weekViewModel.selectedWeek,
                            canMoveToNextWeek: weekViewModel.canMoveToNextWeek,
                            isRefreshing: weekViewModel.isRefreshingWeeks,
                            onPrevious: {
                                Task { await weekViewModel.selectPreviousWeek() }
                            },
                            onNext: {
                                Task { await weekViewModel.selectNextWeek() }
                            },
                            onCurrent: {
                                Task { await weekViewModel.selectCurrentWeek() }
                            }
                        )

                        FitnessWeekSelectorView(
                            weeks: weekViewModel.focusedWeeks,
                            selectedWeek: weekViewModel.selectedWeek,
                            onShowHistory: {
                                isShowingWeekHistory = true
                            }
                        ) { week in
                            Task { await weekViewModel.selectWeek(week) }
                        }

                        WeeklyMuscleMatrixCard(viewModel: weekViewModel.muscleMatrixViewModel)

                        DailyExerciseProgressSection(
                            viewModel: progressViewModel,
                            selectedWeek: weekViewModel.selectedWeek,
                            displayUnit: resolvedGymWeightUnit
                        ) {
                            withAnimation(.spring(response: 0.44, dampingFraction: 0.82)) {
                                isShowingWorkoutPicker = true
                            }
                        }
                        .padding(.top, 2)

                        FitnessActivityLogSection(
                            week: weekViewModel.selectedWeek,
                            activities: weekViewModel.activities,
                            isLoading: weekViewModel.isLoadingActivities,
                            isExpanded: isActivityLogExpanded,
                            onToggleExpanded: {
                                withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                                    isActivityLogExpanded.toggle()
                                }
                            }
                        )
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 34)
                }
                .pulsarBottomChromeScrollTracking()
                .background(FitnessWeeklyBackground())
                .premiumScrollHeaderBlur(height: 56)
                .refreshable {
                    await weekViewModel.refresh()
                    await progressViewModel.refresh(
                        displayUnit: resolvedGymWeightUnit,
                        selectedWeek: weekViewModel.selectedWeek,
                        force: true
                    )
                }

                FitnessFloatingAddButton {
                    withAnimation(.spring(response: 0.44, dampingFraction: 0.82)) {
                        isShowingWorkoutPicker = true
                    }
                }
                .padding(.trailing, 18)
                .padding(.bottom, bottomChromeState.floatingControlBottomPadding)
                .zIndex(10)
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                weekViewModel.startWeekRolloverMonitoring()
                watchSyncStore.pruneStaleActiveWorkoutState(reason: "fitnessTask")
                await weekViewModel.load()
                await progressViewModel.load(displayUnit: resolvedGymWeightUnit, selectedWeek: weekViewModel.selectedWeek)
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                Task {
                    watchSyncStore.pruneStaleActiveWorkoutState(reason: "fitnessSceneBecameActive")
                    await weekViewModel.refreshCurrentWeekIfNeeded()
                    await progressViewModel.refresh(
                        displayUnit: resolvedGymWeightUnit,
                        selectedWeek: weekViewModel.selectedWeek
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: PulsarGymWorkoutHistoryStore.didChangeNotification)) { _ in
                Task {
                    await weekViewModel.refreshCurrentWeekIfNeeded(force: true)
                    await progressViewModel.refresh(
                        displayUnit: resolvedGymWeightUnit,
                        selectedWeek: weekViewModel.selectedWeek,
                        force: true
                    )
                }
            }
            .onChange(of: profileStore.profile.preferredUnits) { _, _ in
                Task {
                    await progressViewModel.refresh(
                        displayUnit: resolvedGymWeightUnit,
                        selectedWeek: weekViewModel.selectedWeek,
                        force: true
                    )
                }
            }
            .onChange(of: weekViewModel.selectedWeek.id) { _, _ in
                isActivityLogExpanded = false
                Task {
                    await progressViewModel.selectWeek(weekViewModel.selectedWeek, displayUnit: resolvedGymWeightUnit)
                }
            }
            .onReceive(watchSyncStore.$activeGymState) { state in
                guard selectedPersonalizedWorkout == nil, selectedOutdoorWorkoutKind == nil else { return }
                guard activeWorkoutManager.gymSessionViewModel == nil else { return }
                if let state, watchSyncStore.isRoutableActiveGymState(state) {
                    isShowingWatchGymMirror = true
                } else if state == nil || state?.isFinished == true || state?.staleRouteReason() != nil {
                    isShowingWatchGymMirror = false
                }
            }
            .sheet(isPresented: $isShowingWeekHistory) {
                FitnessWeekHistorySheet(
                    weeks: weekViewModel.historyWeeks,
                    selectedWeek: weekViewModel.selectedWeek,
                    isLoading: weekViewModel.isLoadingWeekHistory
                ) { week in
                    isShowingWeekHistory = false
                    Task { await weekViewModel.selectWeek(week) }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .task {
                    await weekViewModel.prepareWeekHistory()
                }
            }
            .overlay {
                if isShowingWorkoutPicker {
                    WorkoutPickerSheet(isPresented: $isShowingWorkoutPicker) { workout in
                        if let outdoorWorkoutKind = workout.outdoorWorkoutKind {
                            selectedOutdoorWorkoutKind = outdoorWorkoutKind
                        } else {
                            selectedPersonalizedWorkout = workout.personalizedKind
                        }
                    }
                    .transition(.opacity)
                }
            }
            .fullScreenCover(item: $selectedPersonalizedWorkout, onDismiss: {
                Task {
                    await weekViewModel.refresh()
                    await progressViewModel.refresh(
                        displayUnit: resolvedGymWeightUnit,
                        selectedWeek: weekViewModel.selectedWeek,
                        force: true
                    )
                }
            }) { workout in
                if workout == .gym {
                    GymWorkoutLaunchFlowView(appUnitPreference: profileStore.profile.preferredUnits)
                } else {
                    PersonalizedWorkoutStartView(workout: workout)
                }
            }
            .fullScreenCover(item: $selectedOutdoorWorkoutKind, onDismiss: {
                Task {
                    await weekViewModel.refresh()
                    await progressViewModel.refresh(
                        displayUnit: resolvedGymWeightUnit,
                        selectedWeek: weekViewModel.selectedWeek,
                        force: true
                    )
                }
            }) { workoutKind in
                PulsarRunIntroExperienceView(
                    coordinator: runCoordinator,
                    workoutKind: workoutKind,
                    onMinimize: {
                        activeWorkoutManager.minimizeRunWorkout(runCoordinator.snapshot.workoutKind)
                    }
                )
            }
            .fullScreenCover(isPresented: $isShowingWatchGymMirror, onDismiss: {
                Task {
                    await weekViewModel.refresh()
                    await progressViewModel.refresh(
                        displayUnit: resolvedGymWeightUnit,
                        selectedWeek: weekViewModel.selectedWeek,
                        force: true
                    )
                }
            }) {
                GymWatchMirroredWorkoutView(syncStore: watchSyncStore) {
                    isShowingWatchGymMirror = false
                }
            }
        }
    }

    private var resolvedGymWeightUnit: PulsarWeightUnit {
        gymSettingsStore.resolvedWeightUnit(appUnits: profileStore.profile.preferredUnits)
    }
}

#Preview {
    FitnessView(profileStore: ProfileStore(sideEffectsEnabled: false))
        .environmentObject(PulsarRunCoordinator())
        .environmentObject(PulsarActiveWorkoutManager())
        .environmentObject(PulsarBottomChromeState())
}
