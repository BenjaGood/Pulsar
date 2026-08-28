//
//  PulsarRunExperienceView.swift
//  Pulsar
//

import SwiftUI

struct PulsarRunExperienceView: View {
    @ObservedObject var coordinator: PulsarRunCoordinator
    var workoutKind: PulsarOutdoorWorkoutKind = .running
    var profile: UserProfile = .empty
    var onMinimize: (() -> Void)?
    var onSummaryDone: ((PulsarRunSummary) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var displayedSummary: PulsarRunSummary?
    @State private var pendingSummaryRevealTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            if let summary = displayedSummary {
                PulsarRunSummaryView(summary: summary) {
                    onSummaryDone?(summary)
                    coordinator.resetAfterSummary()
                    dismiss()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if shouldShowLiveRun {
                PulsarLiveRunView(
                    coordinator: coordinator,
                    workoutKind: workoutKind,
                    profile: profile,
                    isPreparingForRemoval: isSummaryRevealPending
                ) {
                    onMinimize?()
                    dismiss()
                }
            } else {
                PulsarRunSetupView(coordinator: coordinator, workoutKind: workoutKind) {
                    dismiss()
                }
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.28), value: coordinator.snapshot.phase)
        .animation(.smooth(duration: 0.28), value: displayedSummary?.id)
        .onAppear {
            scheduleSummaryRevealIfNeeded()
            if shouldShowLiveRun {
                PulsarWorkoutStartupTrace.phone("live UI presented run type=\(workoutKind.rawValue)")
            }
        }
        .onChange(of: coordinator.summary?.id) { _, _ in
            scheduleSummaryRevealIfNeeded()
        }
        .onDisappear {
            pendingSummaryRevealTask?.cancel()
        }
        .alert(item: $coordinator.liveWatchFallbackPrompt) { prompt in
            Alert(
                title: Text(prompt.title),
                message: Text(prompt.message),
                primaryButton: .default(Text("Try Again")) {
                    Task { await coordinator.retryLiveWatchStart() }
                },
                secondaryButton: .default(Text("Use iPhone")) {
                    Task { await coordinator.startIPhoneFallbackFromLiveWatchPrompt() }
                }
            )
        }
    }

    private var isSummaryRevealPending: Bool {
        coordinator.summary != nil && displayedSummary == nil
    }

    private var shouldShowLiveRun: Bool {
        if isSummaryRevealPending { return true }

        switch coordinator.snapshot.phase {
        case .running, .paused, .finishing, .connectingToWatch:
            return true
        default:
            return false
        }
    }

    private func scheduleSummaryRevealIfNeeded() {
        pendingSummaryRevealTask?.cancel()

        guard let summary = coordinator.summary else {
            if displayedSummary != nil {
                displayedSummary = nil
            }
            return
        }

        if displayedSummary?.id == summary.id { return }

        pendingSummaryRevealTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, coordinator.summary?.id == summary.id else { return }
            withTransaction(Transaction(animation: .smooth(duration: 0.22))) {
                displayedSummary = summary
            }
        }
    }
}

#Preview {
    PulsarRunExperienceView(coordinator: PulsarRunCoordinator())
}
