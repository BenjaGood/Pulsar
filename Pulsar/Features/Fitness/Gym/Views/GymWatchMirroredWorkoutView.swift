//
//  GymWatchMirroredWorkoutView.swift
//  Pulsar
//

import SwiftUI
import UIKit

struct GymWatchMirroredWorkoutView: View {
    @ObservedObject var syncStore: PulsarWatchConnectivitySyncStore
    var onDismiss: () -> Void

    private var state: ActiveGymWorkoutState? {
        guard let state = syncStore.activeGymState,
              syncStore.isRoutableActiveGymState(state) else { return nil }
        return state
    }

    var body: some View {
        ZStack {
            GymGlassBackground()
                .ignoresSafeArea()

            if let state {
                VStack(alignment: .leading, spacing: 16) {
                    header(state)
                    progressCard(state)
                    currentSetCard(state)
                    restCard(state)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 10)
                .safeAreaInset(edge: .bottom) {
                    bottomControls(state)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 12)
                }
            } else {
                completedState
            }
        }
        .onAppear {
            guard let state else {
                onDismiss()
                return
            }
            syncStore.sendGymAction(.requestState(sessionId: state.sessionId))
        }
        .onChange(of: syncStore.activeGymState?.isFinished) { _, isFinished in
            if isFinished == true {
                onDismiss()
            }
        }
    }

    private func header(_ state: ActiveGymWorkoutState) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                openNowPlaying()
            } label: {
                Image(systemName: "music.note")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white.opacity(0.84))
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.08), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.11), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Now Playing")

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onDismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.08), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.11), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss workout mirror")

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Text(state.routineEmoji ?? "🏋️")
                    Text("Apple Watch Gym")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white.opacity(0.56))
                }

                Text(state.routineName)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 4)

            Text(PulsarGymFormatters.duration(state.elapsedSeconds))
                .font(.system(size: 20, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.white.opacity(0.10), in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.11), lineWidth: 1)
                }
        }
    }

    private func progressCard(_ state: ActiveGymWorkoutState) -> some View {
        GymWatchMirrorCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.progressText)
                            .font(.headline.weight(.black))
                            .foregroundStyle(.white)
                        Text(state.exerciseProgressText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.58))
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        GymWatchMirrorMetric(
                            symbolName: "heart.fill",
                            value: PulsarGymFormatters.heartRate(state.currentHeartRate),
                            subtitle: state.currentHeartRate == nil ? "reading" : "bpm",
                            tint: Color(red: 1.0, green: 0.42, blue: 0.56)
                        )
                        GymWatchMirrorMetric(
                            symbolName: "flame.fill",
                            value: state.activeEnergyKilocalories.map { "\(Int($0.rounded()))" } ?? "--",
                            subtitle: "kcal",
                            tint: Color(red: 1.0, green: 0.72, blue: 0.34)
                        )
                    }
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(.white.opacity(0.10))
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.72, green: 0.66, blue: 1.0), Color(red: 0.66, green: 1.0, blue: 0.78)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(10, proxy.size.width * progressFraction(for: state)))
                    }
                }
                .frame(height: 8)
            }
        }
    }

    private func currentSetCard(_ state: ActiveGymWorkoutState) -> some View {
        GymWatchMirrorCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(state.currentExercise?.exerciseName ?? "Open Gym")
                        .font(.title3.weight(.black))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                    Text(subtitle(for: state))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.58))
                }

                HStack(spacing: 10) {
                    GymWatchMirrorSetMetric(title: "Set", value: state.currentSet.map { "\($0.setNumber)" } ?? "--")
                    GymWatchMirrorSetMetric(title: "Reps", value: state.currentSet.map { "\($0.targetReps)" } ?? "--")
                    GymWatchMirrorSetMetric(
                        title: "Load",
                        value: state.currentSet.map { PulsarGymFormatters.weight($0.targetWeight, unit: state.currentExercise?.weightUnit ?? "kg") } ?? "--"
                    )
                }

                Button {
                    guard let exercise = state.currentExercise, let set = state.currentSet else { return }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    syncStore.sendGymAction(.completeSet(sessionId: state.sessionId, exerciseId: exercise.id, setId: set.id))
                } label: {
                    Label("Complete Set", systemImage: "checkmark.circle.fill")
                        .font(.headline.weight(.black))
                        .foregroundStyle(Color(red: 0.10, green: 0.08, blue: 0.16))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [.white.opacity(0.98), Color(red: 0.72, green: 1.0, blue: 0.78)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Capsule(style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .disabled(state.currentSet == nil)
            }
        }
    }

    @ViewBuilder
    private func restCard(_ state: ActiveGymWorkoutState) -> some View {
        if let remaining = state.restRemainingSeconds, remaining > 0 {
            GymWatchMirrorCard {
                HStack(spacing: 12) {
                    Image(systemName: "timer")
                        .font(.title3.weight(.black))
                        .foregroundStyle(Color(red: 0.78, green: 0.72, blue: 1.0))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rest")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.white.opacity(0.56))
                        Text(PulsarGymFormatters.duration(remaining))
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Button("Skip") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        syncStore.sendGymAction(.skipRestTimer(sessionId: state.sessionId))
                    }
                    .font(.headline.weight(.black))
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.12))
                }
            }
        }
    }

    private func bottomControls(_ state: ActiveGymWorkoutState) -> some View {
        Button {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            syncStore.sendGymAction(.finishWorkout(sessionId: state.sessionId))
        } label: {
            Text("Finish Workout")
                .font(.headline.weight(.black))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(.white.opacity(0.11), in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private var completedState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 46, weight: .black))
                .foregroundStyle(Color(red: 0.66, green: 1.0, blue: 0.78))
            Text("Workout finished")
                .font(.title3.weight(.black))
                .foregroundStyle(.white)
            Button("Done") {
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func progressFraction(for state: ActiveGymWorkoutState) -> Double {
        guard state.totalSets > 0 else { return 1 }
        return min(max(Double(state.completedSets) / Double(state.totalSets), 0), 1)
    }

    private func subtitle(for state: ActiveGymWorkoutState) -> String {
        guard let exercise = state.currentExercise else {
            return "Tracking from Apple Watch"
        }
        return "\(exercise.muscleGroup) / \(exercise.equipment)"
    }

    private func openNowPlaying() {
        let urls = ["music://nowplaying", "music://"].compactMap(URL.init(string:))
        guard let url = urls.first else { return }
        UIApplication.shared.open(url)
    }
}

private struct GymWatchMirrorCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.11),
                                Color(red: 0.72, green: 0.66, blue: 1.0).opacity(0.13),
                                Color.black.opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(.white.opacity(0.13), lineWidth: 1)
            }
    }
}

private struct GymWatchMirrorMetric: View {
    let symbolName: String
    let value: String
    let subtitle: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
                .font(.caption.weight(.black))
                .foregroundStyle(tint)
            VStack(alignment: .trailing, spacing: 1) {
                Text(value)
                    .font(.subheadline.weight(.black))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.white.opacity(0.54))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.08), in: Capsule(style: .continuous))
    }
}

private struct GymWatchMirrorSetMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.headline.weight(.black))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(.white.opacity(0.50))
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    GymWatchMirroredWorkoutView(syncStore: .shared) {}
}
