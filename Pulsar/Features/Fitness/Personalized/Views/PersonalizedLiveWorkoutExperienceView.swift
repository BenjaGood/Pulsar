//
//  PersonalizedLiveWorkoutExperienceView.swift
//  Pulsar
//

import SwiftUI
import UIKit

struct PersonalizedLiveWorkoutExperienceView: View {
    let workout: PersonalizedWorkoutKind
    let profile: UserProfile

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PersonalizedWorkoutSessionViewModel
    @State private var isShowingLiveWorkout = false
    @State private var completionSummary: PulsarRunSummary?
    @State private var isStartingWorkout = false

    init(workout: PersonalizedWorkoutKind, profile: UserProfile) {
        self.workout = workout
        self.profile = profile
        _viewModel = StateObject(
            wrappedValue: PersonalizedWorkoutSessionViewModel(
                workout: workout,
                profile: profile
            )
        )
    }

    var body: some View {
        ZStack {
            if let completionSummary {
                WorkoutCompleteView(runSummary: completionSummary) {
                    dismiss()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if isShowingLiveWorkout {
                PersonalizedLiveWorkoutScreen(viewModel: viewModel) {
                    dismiss()
                } onCompletion: { summary in
                    self.completionSummary = summary
                }
                .transition(.opacity.combined(with: .scale(scale: 1.012)))
            } else {
                PersonalizedWorkoutStartView(
                    workout: workout,
                    completionBehavior: .showStartButton,
                    onStart: startWorkout,
                    onCancel: {
                        viewModel.cancel()
                        dismiss()
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.988)))
            }
        }
        .background(PulsarFitnessMonochromeBackground())
        .pulsarFitnessMonochromeAppearance()
        .animation(.smooth(duration: 0.36), value: isShowingLiveWorkout)
        .animation(.smooth(duration: 0.28), value: completionSummary?.id)
        .onDisappear {
            viewModel.cancel()
        }
    }

    private func startWorkout() {
        guard !isStartingWorkout else { return }
        isStartingWorkout = true
        withAnimation(.smooth(duration: 0.36)) {
            isShowingLiveWorkout = true
        }
        Task {
            await viewModel.start()
            isStartingWorkout = false
        }
    }
}

private struct PersonalizedLiveWorkoutScreen: View {
    @ObservedObject var viewModel: PersonalizedWorkoutSessionViewModel
    var onDismiss: () -> Void
    var onCompletion: (PulsarRunSummary) -> Void

    @StateObject private var musicManager = PulsarNowPlayingMusicManager()

    var body: some View {
        PulsarLiveWorkoutDashboardView(
            state: viewModel.dashboardState,
            closeSymbolName: "xmark",
            closeAccessibilityLabel: "Close workout",
            onClose: closeWorkout,
            onTogglePause: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.togglePause()
            },
            onEnd: endWorkout,
            onOpenNowPlaying: openNowPlaying,
            onToggleMusicPlayback: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                musicManager.playPause()
            },
            onNextTrack: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                musicManager.nextTrack()
            },
            onPreviousTrack: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                musicManager.previousTrack()
            }
        ) {
            PulsarLiveWorkoutAmbientBackground(
                tint: viewModel.dashboardState.tint,
                glowColor: viewModel.dashboardState.glowColor
            )
        }
        .task {
            await musicManager.start()
            viewModel.updateNowPlaying(musicManager.track)
        }
        .onReceive(musicManager.$track) { track in
            viewModel.updateNowPlaying(track)
        }
    }

    private func closeWorkout() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        viewModel.cancel()
        onDismiss()
    }

    private func endWorkout() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            await viewModel.end()
            onCompletion(viewModel.completionSummary())
        }
    }

    private func openNowPlaying() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let urls = ["music://nowplaying", "music://"].compactMap(URL.init(string:))
        guard let url = urls.first else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    PersonalizedLiveWorkoutExperienceView(workout: .indoorRunning, profile: .empty)
}
