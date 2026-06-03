//
//  MindfulnessView.swift
//  Pulsar
//

import Combine
import SwiftUI
import UIKit

struct MindfulnessView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var homeViewModel: HomeViewModel
    @ObservedObject private var store: PulsarMindfulnessStore
    @ObservedObject private var router: PulsarMindfulnessRouter
    @State private var activeSheet: MindfulnessSheet?
    @State private var activeTemplate: PulsarMeditationTemplate?
    @State private var activeRewind: PulsarDailyRewind?

    private let templates = PulsarMindfulnessContentLibrary.meditationTemplates
    private let rewindBuilder: DailyRewindBuilder

    init(
        homeViewModel: HomeViewModel,
        store: PulsarMindfulnessStore,
        router: PulsarMindfulnessRouter,
        rewindBuilder: DailyRewindBuilder = DailyRewindBuilder()
    ) {
        self.homeViewModel = homeViewModel
        self.store = store
        self.router = router
        self.rewindBuilder = rewindBuilder
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PulsarSectionBackground()
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        MindfulnessPageTitleHeader()

                        MindfulnessTodayCard(
                            dashboard: store.dashboard,
                            onCheckIn: openCheckIn,
                            onStartBreathing: startDefaultBreathing
                        )

                        MindfulnessTrendCard(points: store.dashboard.trend)

                        meditationLibrary

                        insightsSection

                        if let latestSession = store.dashboard.latestSession {
                            recentSessionCard(latestSession)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 34)
                    .padding(.bottom, 34)
                }
                .safeAreaPadding(.bottom, 16)
                .scrollContentBackground(.hidden)
                .premiumScrollHeaderBlur()
            }
            .navigationTitle("")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(action: openDailyRewind) {
                        Image(systemName: "arrow.counterclockwise.circle")
                    }
                    .accessibilityLabel("Daily Rewind")

                    Button(action: openCheckIn) {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("Daily check-in")
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .checkIn:
                    DailyJournalCheckInSheet(draft: store.draftForToday()) { draft in
                        store.saveCheckIn(draft)
                        syncDailyRewindReminder()
                    }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
            }
            .fullScreenCover(item: $activeTemplate, onDismiss: {
                activeTemplate = nil
            }) { template in
                MindfulnessSessionView(template: template) { summary in
                    store.saveSession(summary)
                    activeTemplate = nil
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
            .task {
                syncDailyRewindReminder()
                consumePendingMindfulnessPresentationIfNeeded()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                store.reload()
                syncDailyRewindReminder()
            }
            .onReceive(router.$pendingPresentation.compactMap { $0 }) { presentation in
                presentDailyRewind(presentation: presentation)
            }
        }
        .background(PulsarSectionBackground())
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var meditationLibrary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Guided sessions")
                        .pulsarTextStyle(.sectionTitle)
                    Text("Breath, recovery, focus, and rest")
                        .pulsarTextStyle(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(templates) { template in
                    MindfulnessTemplateCard(template: template) {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        activeTemplate = template
                    }
                }
            }
        }
    }

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Intelligence")
                .pulsarTextStyle(.sectionTitle)

            ForEach(store.dashboard.insights) { insight in
                PulsarMindfulnessInsightCard(insight: insight)
            }
        }
    }

    private func recentSessionCard(_ session: PulsarMindfulnessSessionSummary) -> some View {
        PulsarMindfulnessGlassCard(cornerRadius: 24) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: session.category.symbolName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(session.category.accent)
                    .frame(width: 40, height: 40)
                    .background(session.category.accent.opacity(0.13), in: Circle())

                VStack(alignment: .leading, spacing: 6) {
                    Text("Latest session")
                        .pulsarTextStyle(.overline)
                        .foregroundStyle(.secondary)
                    Text(session.title)
                        .pulsarTextStyle(.cardTitle)
                    Text("\(session.durationText) · \(session.category.title)")
                        .pulsarTextStyle(.screenSubtitle)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func openCheckIn() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        activeSheet = .checkIn
    }

    private func openDailyRewind() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        activeRewind = rewindBuilder.build(
            dashboard: homeViewModel.dashboard,
            mindfulness: store.state
        )
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

    private func startDefaultBreathing() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        activeTemplate = PulsarMindfulnessContentLibrary.template(id: "breathing-relaxation")
    }
}

private enum MindfulnessSheet: Identifiable {
    case checkIn

    var id: String {
        switch self {
        case .checkIn: "check-in"
        }
    }
}

#Preview {
    MindfulnessView(
        homeViewModel: HomeViewModel(),
        store: PulsarMindfulnessStore(),
        router: PulsarMindfulnessRouter()
    )
}
