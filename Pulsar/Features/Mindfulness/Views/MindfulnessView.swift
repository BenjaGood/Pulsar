//
//  MindfulnessView.swift
//  Pulsar
//

import Combine
import SwiftUI
import UIKit

struct MindfulnessView: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @ObservedObject private var homeViewModel: HomeViewModel
    @ObservedObject private var store: PulsarMindfulnessStore
    @ObservedObject private var router: PulsarMindfulnessRouter
    @ObservedObject private var bottomChromeLayoutStore: PulsarBottomChromeLayoutStore
    @State private var activeSheet: MindfulnessSheet?
    @State private var activeRewind: PulsarDailyRewind?
    @State private var selectedMeditationTemplate: PulsarMeditationTemplate?
    @State private var dailyDraft = PulsarDailyJournalDraft()
    @State private var displayedMonth = Date()
    @State private var selectedHistoryDate = Date()
    @State private var streakCelebration: MindfulnessStreakCelebration?

    private let rewindBuilder: DailyRewindBuilder

    init(
        homeViewModel: HomeViewModel,
        store: PulsarMindfulnessStore,
        router: PulsarMindfulnessRouter,
        bottomChromeLayoutStore: PulsarBottomChromeLayoutStore = PulsarBottomChromeLayoutStore(),
        rewindBuilder: DailyRewindBuilder = DailyRewindBuilder()
    ) {
        self.homeViewModel = homeViewModel
        self.store = store
        self.router = router
        self._bottomChromeLayoutStore = ObservedObject(wrappedValue: bottomChromeLayoutStore)
        self.rewindBuilder = rewindBuilder
    }

    var body: some View {
        NavigationStack {
            let weekSnapshot = PulsarMindfulnessWeekSnapshot(
                entries: store.state.entries,
                referenceDate: Date(),
                calendar: calendar
            )
            let meditationSnapshot = PulsarMindfulnessMeditationWeekSnapshot(
                sessions: store.state.sessions,
                referenceDate: Date(),
                calendar: calendar
            )

            PulsarScreenScaffold(
                layoutStore: bottomChromeLayoutStore,
                horizontalPadding: 22,
                spacing: 14,
                headerBlur: PulsarScreenHeaderBlur(height: 48, fadeStart: 12, fadeEnd: 48),
                background: {
                    MindfulnessScenicBackground()
                },
                content: {
                    MindfulnessPageTitleHeader()

                    MindfulnessMoodLoggingCard(
                        draft: $dailyDraft,
                        loggedEntry: store.dashboard.todayEntry,
                        loggedStreakDays: store.dashboard.streak.currentStreak,
                        isCelebratingStreak: streakCelebration != nil,
                        onLog: saveDailyMood
                    )

                    MindfulnessWeeklySummaryCard(
                        snapshot: weekSnapshot,
                        onViewMore: openMoodHistory
                    )

                    MindfulnessCompactInsightsCard(
                        average: weekSnapshot.wellnessAverage
                    )

                    MindfulnessGuidedMeditationSection(
                        snapshot: meditationSnapshot,
                        templates: PulsarMindfulnessContentLibrary.meditationTemplates,
                        onStart: startMeditation
                    )
                }
            )
            .navigationTitle("")
            .toolbarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .moodHistory:
                    MindfulnessHistorySheet(
                        entries: store.state.entries,
                        displayedMonth: $displayedMonth,
                        selectedDate: $selectedHistoryDate
                    )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.clear)
                    .presentationCornerRadius(38)
                }
            }
            .fullScreenCover(item: $activeRewind, onDismiss: {
                activeRewind = nil
            }) { rewind in
                DailyRewindView(
                    rewind: rewind,
                    mindfulnessStore: store,
                    onDismiss: {
                        activeRewind = nil
                    },
                    onJournalSaved: {
                        syncDailyRewindReminder()
                    }
                )
            }
            .fullScreenCover(item: $selectedMeditationTemplate, onDismiss: {
                selectedMeditationTemplate = nil
            }) { template in
                MindfulnessSessionView(template: template) { summary in
                    saveMeditationSession(summary)
                }
            }
            .task {
                refreshDailyDraft()
                syncDailyRewindReminder()
                consumePendingMindfulnessPresentationIfNeeded()
            }
            .task(id: streakCelebration?.id) {
                guard let celebrationID = streakCelebration?.id else { return }
                await dismissStreakCelebration(id: celebrationID)
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                store.reload()
                refreshDailyDraft()
                syncDailyRewindReminder()
            }
            .onChange(of: store.state.entries) { _, _ in
                refreshDailyDraft()
            }
            .onReceive(router.$pendingPresentation.compactMap { $0 }) { presentation in
                presentDailyRewind(presentation: presentation)
            }
        }
        .preferredColorScheme(.dark)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sensoryFeedback(.success, trigger: streakCelebration?.id) { _, newValue in
            newValue != nil
        }
    }

    private func openMoodHistory() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        activeSheet = .moodHistory
    }

    private func startMeditation(_ template: PulsarMeditationTemplate) {
        guard activeRewind == nil else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        selectedMeditationTemplate = template
    }

    private func saveMeditationSession(_ summary: PulsarMindfulnessSessionSummary) {
        store.saveSession(summary)
        if voiceOverEnabled {
            AccessibilityNotification.Announcement(
                "\(summary.title) saved. \(summary.durationText) of meditation logged."
            )
            .post()
        }
    }

    private func saveDailyMood() -> Bool {
        let now = Date()
        dailyDraft.date = now
        dailyDraft.kind = .dailyMood
        let savedEntry = store.saveCheckIn(
            dailyDraft,
            now: now,
            playsHaptic: false
        )
        dailyDraft = PulsarDailyJournalDraft(entry: savedEntry)

        guard store.lastPersistenceError == nil else { return false }
        syncDailyRewindReminder()
        let celebration = MindfulnessStreakCelebration(
            dayCount: max(1, store.dashboard.streak.currentStreak)
        )
        withAnimation(streakAnimation) {
            streakCelebration = celebration
        }
        if voiceOverEnabled {
            AccessibilityNotification.Announcement(
                "\(celebration.title). \(celebration.message)"
            )
            .post()
        }
        return true
    }

    private func refreshDailyDraft() {
        dailyDraft = store.draftForToday()
    }

    private func presentDailyRewind(presentation: PulsarMindfulnessPresentation) {
        let date = DailyRewindDateKey.date(from: presentation.dateKey) ?? Date()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        activeRewind = rewindBuilder.build(
            date: date,
            dashboard: homeViewModel.dashboard,
            mindfulness: store.state
        )
        router.consume(presentation)
    }

    private func consumePendingMindfulnessPresentationIfNeeded() {
        guard let pending = router.pendingPresentation else { return }
        presentDailyRewind(presentation: pending)
    }

    private func syncDailyRewindReminder() {
        Task {
            await DailyRewindNotificationScheduler.shared.syncReminder(
                journalCompletedToday: store.hasEntry(on: Date())
            )
        }
    }

    private func dismissStreakCelebration(id: UUID) async {
        let delay: Duration = .milliseconds(voiceOverEnabled ? 5_000 : 2_800)
        do {
            try await Task.sleep(for: delay)
        } catch {
            return
        }

        guard streakCelebration?.id == id else { return }
        withAnimation(streakAnimation) {
            streakCelebration = nil
        }
    }

    private var streakAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.14)
            : .spring(response: 0.36, dampingFraction: 0.82)
    }

    private static func topChromeClearance(for safeAreaTop: CGFloat) -> CGFloat {
        safeAreaTop > 0 ? 16 : 64
    }
}

private enum MindfulnessSheet: String, Identifiable {
    case moodHistory

    var id: String { rawValue }
}

#Preview {
    MindfulnessView(
        homeViewModel: HomeViewModel(),
        store: PulsarMindfulnessStore(),
        router: PulsarMindfulnessRouter()
    )
}
