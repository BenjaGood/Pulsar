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
    @State private var isShowingWeekHistory = false
    @State private var isActivityLogExpanded = false
    @State private var selectedPersonalizedWorkout: PersonalizedWorkoutKind?
    @State private var selectedOutdoorWorkoutKind: PulsarOutdoorWorkoutKind?
    @State private var selectedHistoricalActivity: WeeklyActivity?

    @MainActor
    init(profileStore: ProfileStore) {
        self.profileStore = profileStore
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        FitnessPageTitleHeader()

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
                            },
                            onSelectActivity: { activity in
                                selectedHistoricalActivity = activity
                            }
                        )
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 34)
                    .padding(.bottom, 34)
                }
                .safeAreaPadding(.bottom, 16)
                .scrollContentBackground(.hidden)
                .refreshable {
                    await weekViewModel.refresh()
                    await progressViewModel.refresh(
                        displayUnit: resolvedGymWeightUnit,
                        selectedWeek: weekViewModel.selectedWeek,
                        force: true
                    )
                }

            }
            .background(FitnessWeeklyBackground())
            .navigationTitle("")
            .toolbarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedHistoricalActivity) { activity in
                FitnessWorkoutDetailView(activity: activity)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        withAnimation(.spring(response: 0.44, dampingFraction: 0.82)) {
                            isShowingWorkoutPicker = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add workout")
                }
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
        .background(FitnessWeeklyBackground())
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var resolvedGymWeightUnit: PulsarWeightUnit {
        gymSettingsStore.resolvedWeightUnit(appUnits: profileStore.profile.preferredUnits)
    }
}

private struct FitnessPageTitleHeader: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            RunningGlyphView()
                .frame(width: 32, height: 28)
                .alignmentGuide(.firstTextBaseline) { dimensions in
                    dimensions[VerticalAlignment.center] + 7
                }
                .accessibilityHidden(true)

            Text("Fitness")
                .pulsarTextStyle(.screenTitle)
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fitness")
        .accessibilityAddTraits(.isHeader)
    }
}

struct RunningGlyphView: View {
    var tint: Color = .primary

    var body: some View {
        Image(systemName: "figure.run")
            .font(.system(size: 27, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: 32, height: 28)
    }
}

#Preview {
    FitnessView(profileStore: ProfileStore(sideEffectsEnabled: false))
        .environmentObject(PulsarRunCoordinator())
        .environmentObject(PulsarActiveWorkoutManager())
}
