//
//  FitnessView.swift
//  Pulsar
//

import SwiftUI

struct FitnessView: View {
    @EnvironmentObject private var runCoordinator: PulsarRunCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var weekViewModel = FitnessWeekViewModel()
    @State private var isShowingWorkoutPicker = false
    @State private var isShowingWeekHistory = false
    @State private var isActivityLogExpanded = false
    @State private var selectedPersonalizedWorkout: PersonalizedWorkoutKind?
    @State private var isShowingRunExperience = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomLeading) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
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

                        FitnessBodyMapSection(analysis: weekViewModel.bodyMapAnalysis)

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
                    .padding(.bottom, 108)
                }
                .background(FitnessWeeklyBackground())
                .refreshable {
                    await weekViewModel.refresh()
                }

                FitnessFloatingAddButton {
                    withAnimation(.spring(response: 0.44, dampingFraction: 0.82)) {
                        isShowingWorkoutPicker = true
                    }
                }
                .padding(.leading, 18)
                .padding(.bottom, 18)
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                weekViewModel.startWeekRolloverMonitoring()
                await weekViewModel.load()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                Task { await weekViewModel.refreshCurrentWeekIfNeeded() }
            }
            .onChange(of: weekViewModel.selectedWeek.id) { _, _ in
                isActivityLogExpanded = false
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
                        if workout.personalizedKind == .running {
                            isShowingRunExperience = true
                        } else {
                            selectedPersonalizedWorkout = workout.personalizedKind
                        }
                    }
                    .transition(.opacity)
                }
            }
            .fullScreenCover(item: $selectedPersonalizedWorkout, onDismiss: {
                Task { await weekViewModel.refresh() }
            }) { workout in
                PersonalizedWorkoutStartView(workout: workout)
            }
            .fullScreenCover(isPresented: $isShowingRunExperience, onDismiss: {
                Task { await weekViewModel.refresh() }
            }) {
                PulsarRunIntroExperienceView(coordinator: runCoordinator)
            }
        }
    }
}

#Preview {
    FitnessView()
        .environmentObject(PulsarRunCoordinator())
}
