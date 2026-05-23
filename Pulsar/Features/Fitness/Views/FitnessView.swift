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
    @StateObject private var watchSyncStore = PulsarWatchConnectivitySyncStore.shared
    @State private var isShowingWorkoutPicker = false
    @State private var isShowingWeekHistory = false
    @State private var isActivityLogExpanded = false
    @State private var selectedPersonalizedWorkout: PersonalizedWorkoutKind?
    @State private var selectedOutdoorWorkoutKind: PulsarOutdoorWorkoutKind?

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
            FitnessRunnerGlyph()
                .frame(width: 32, height: 28)
                .alignmentGuide(.firstTextBaseline) { dimensions in
                    dimensions[VerticalAlignment.center] + 7
                }
                .accessibilityHidden(true)

            Text("Fitness")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fitness")
        .accessibilityAddTraits(.isHeader)
    }
}

private struct FitnessRunnerGlyph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isStriding = false

    @ViewBuilder
    var body: some View {
        if reduceMotion {
            runnerSymbol
        } else {
            runnerSymbol
                .rotationEffect(.degrees(isStriding ? -4 : 3), anchor: .bottom)
                .offset(y: isStriding ? -1.6 : 0.9)
                .scaleEffect(
                    x: isStriding ? 1.015 : 0.985,
                    y: isStriding ? 0.985 : 1.015,
                    anchor: .bottom
                )
                .symbolEffect(.bounce.up.byLayer, options: .speed(1.28).repeating, isActive: true)
                .animation(
                    .easeInOut(duration: 0.38).repeatForever(autoreverses: true),
                    value: isStriding
                )
                .onAppear {
                    startRunningAnimation()
                }
                .onChange(of: reduceMotion) { _, isReduced in
                    if isReduced {
                        isStriding = false
                    } else {
                        startRunningAnimation()
                }
            }
        }
    }

    private func startRunningAnimation() {
        guard !reduceMotion else { return }
        isStriding = true
    }

    private var runnerSymbol: some View {
        Image(systemName: "figure.run")
            .font(.system(size: 27, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.primary)
            .frame(width: 32, height: 28)
    }
}

#Preview {
    FitnessView(profileStore: ProfileStore(sideEffectsEnabled: false))
        .environmentObject(PulsarRunCoordinator())
        .environmentObject(PulsarActiveWorkoutManager())
}
