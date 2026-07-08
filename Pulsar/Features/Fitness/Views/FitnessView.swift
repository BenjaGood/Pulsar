//
//  FitnessView.swift
//  Pulsar
//

import SwiftUI

struct FitnessView: View {
    @EnvironmentObject private var runCoordinator: PulsarRunCoordinator
    @EnvironmentObject private var activeWorkoutManager: PulsarActiveWorkoutManager
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var profileStore: ProfileStore
    @StateObject private var weekViewModel = FitnessWeekViewModel()
    @StateObject private var progressViewModel = ExerciseProgressViewModel()
    @StateObject private var gymSettingsStore = GymSettingsStore()
    private let watchSyncStore = PulsarWatchConnectivitySyncStore.shared
    @State private var isShowingWorkoutPicker = false
    @State private var pendingWorkoutSelection: WorkoutOption?
    @State private var isActivityLogExpanded = false
    @State private var selectedPersonalizedWorkout: PersonalizedWorkoutKind?
    @State private var selectedOutdoorWorkoutKind: PulsarOutdoorWorkoutKind?
    @State private var selectedHistoricalActivity: WeeklyActivity?
    @ObservedObject private var bottomChromeLayoutStore: PulsarBottomChromeLayoutStore

    @MainActor
    init(
        profileStore: ProfileStore,
        bottomChromeLayoutStore: PulsarBottomChromeLayoutStore
    ) {
        self.profileStore = profileStore
        self._bottomChromeLayoutStore = ObservedObject(wrappedValue: bottomChromeLayoutStore)
    }

    var body: some View {
        NavigationStack {
            PulsarScreenScaffold(
                layoutStore: bottomChromeLayoutStore,
                horizontalPadding: 22,
                spacing: 14,
                onRefresh: {
                    await weekViewModel.refresh()
                    await progressViewModel.refresh(
                        displayUnit: resolvedGymWeightUnit,
                        selectedWeek: weekViewModel.selectedWeek,
                        force: true
                    )
                },
                background: {
                    FitnessWeeklyBackground()
                },
                content: {
                    FitnessPageTitleHeader {
                        presentWorkoutPicker()
                    }

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
                        },
                        onSelectActivity: { activity in
                            selectedHistoricalActivity = activity
                        }
                    )
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
                } else if workout == .indoorRunning {
                    PersonalizedLiveWorkoutExperienceView(workout: workout, profile: profileStore.profile)
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
            selectedOutdoorWorkoutKind = outdoorWorkoutKind
        } else {
            selectedPersonalizedWorkout = workout.personalizedKind
        }
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
        bottomChromeLayoutStore: PulsarBottomChromeLayoutStore()
    )
        .environmentObject(PulsarRunCoordinator())
        .environmentObject(PulsarActiveWorkoutManager())
        .environmentObject(WorkoutCompletionPresentationStore())
}
