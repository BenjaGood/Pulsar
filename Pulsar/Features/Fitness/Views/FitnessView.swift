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
            GeometryReader { proxy in
                let topChromeClearance = Self.topChromeClearance(for: proxy.safeAreaInsets.top)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
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

                        PulsarBottomChromeSpacer(layoutStore: bottomChromeLayoutStore)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, topChromeClearance)
                    .padding(.bottom, 8)
                }
                .pulsarBottomChromeScrollContainer(layoutStore: bottomChromeLayoutStore)
                .background(FitnessWeeklyBackground())
                .scrollContentBackground(.hidden)
                .ignoresSafeArea(edges: .bottom)
                .refreshable {
                    await weekViewModel.refresh()
                    await progressViewModel.refresh(
                        displayUnit: resolvedGymWeightUnit,
                        selectedWeek: weekViewModel.selectedWeek,
                        force: true
                    )
                }
            }
            .navigationTitle("")
            .toolbarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedHistoricalActivity) { activity in
                FitnessWorkoutDetailView(activity: activity)
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
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        }

    private var resolvedGymWeightUnit: PulsarWeightUnit {
        gymSettingsStore.resolvedWeightUnit(appUnits: profileStore.profile.preferredUnits)
    }

    private func presentWorkoutPicker() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.spring(response: 0.44, dampingFraction: 0.82)) {
            isShowingWorkoutPicker = true
        }
    }

    private static func topChromeClearance(for safeAreaTop: CGFloat) -> CGFloat {
        safeAreaTop > 0 ? 16 : 64
    }

}

private struct FitnessPageTitleHeader: View {
    var onAddWorkout: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            RunningGlyphView(tint: primaryText)
                .frame(width: 52, height: 52)
                .background(FitnessCircularGlassSurface(cornerRadius: 26))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Fitness")
                    .pulsarTextStyle(.displayLarge)
                    .foregroundStyle(primaryText)

                Text("Train smarter. Every day.")
                    .pulsarTextStyle(.label)
                    .foregroundStyle(secondaryText)
            }

            Spacer(minLength: 12)

            Button(action: onAddWorkout) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(primaryText)
                    .frame(width: 52, height: 52)
                    .background(FitnessCircularGlassSurface(cornerRadius: 26))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add workout")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fitness")
        .accessibilityAddTraits(.isHeader)
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.96) : Color(red: 0.07, green: 0.10, blue: 0.14)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.62) : Color(red: 0.36, green: 0.40, blue: 0.48)
    }
}

struct RunningGlyphView: View {
    var tint: Color = .primary

    var body: some View {
        Image(systemName: "figure.run")
            .font(.system(size: 28, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: 32, height: 32)
    }
}

#Preview {
    FitnessView(
        profileStore: ProfileStore(sideEffectsEnabled: false),
        bottomChromeLayoutStore: PulsarBottomChromeLayoutStore()
    )
        .environmentObject(PulsarRunCoordinator())
        .environmentObject(PulsarActiveWorkoutManager())
}
