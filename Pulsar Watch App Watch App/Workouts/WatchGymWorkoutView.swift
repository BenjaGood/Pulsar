//
//  WatchGymWorkoutView.swift
//  Pulsar Watch App Watch App
//

import SwiftUI
import WatchKit

struct WatchActiveGymWorkoutView: View {
    @ObservedObject var syncStore: PulsarWatchConnectivitySyncStore
    var state: ActiveGymWorkoutState
    @State private var isShowingNowPlaying = false

    var body: some View {
        ZStack {
            background
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    progressCard
                    currentSetCard
                    restCard
                    finishButton
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 10)
            }
        }
        .onAppear {
            syncStore.sendGymAction(.requestState(sessionId: state.sessionId))
            Task {
                await WatchGymSessionManager.shared.startIfNeeded(for: state)
            }
        }
        .sheet(isPresented: $isShowingNowPlaying) {
            NowPlayingView()
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.04, blue: 0.10),
                    Color(red: 0.02, green: 0.02, blue: 0.05),
                    Color(red: 0.22, green: 0.12, blue: 0.38).opacity(0.55)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color(red: 0.72, green: 0.66, blue: 1.0).opacity(0.24), .clear],
                center: .topTrailing,
                startRadius: 4,
                endRadius: 120
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                WKInterfaceDevice.current().play(.click)
                isShowingNowPlaying = true
            } label: {
                Image(systemName: "music.note")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(.thinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.13), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Now Playing")

            VStack(alignment: .leading, spacing: 2) {
                Text("Gym")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(Color(red: 0.78, green: 0.72, blue: 1.0))
                Text(state.routineName)
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)
                Text(PulsarGymFormatters.duration(state.elapsedSeconds))
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 6) {
                WatchGymHeaderMetric(
                    symbolName: "heart.fill",
                    value: PulsarGymFormatters.heartRate(state.currentHeartRate),
                    unit: state.currentHeartRate == nil ? "reading" : "bpm",
                    tint: Color(red: 1.0, green: 0.42, blue: 0.56)
                )
                WatchGymHeaderMetric(
                    symbolName: "flame.fill",
                    value: energyText,
                    unit: "kcal",
                    tint: Color(red: 1.0, green: 0.72, blue: 0.34)
                )
            }
        }
    }

    private var progressCard: some View {
        WatchGymGlassCard {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(state.progressText)
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(state.exerciseProgressText)
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
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
                            .frame(width: max(8, proxy.size.width * progressFraction))
                    }
                }
                .frame(height: 7)
            }
        }
    }

    private var currentSetCard: some View {
        WatchGymGlassCard {
            VStack(alignment: .leading, spacing: 9) {
                Text(currentExercise?.exerciseName ?? "Open Gym")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)

                Text(subtitleText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)

                HStack(spacing: 8) {
                    WatchGymMetric(title: "Set", value: currentSet.map { "\($0.setNumber)" } ?? "--")
                    WatchGymMetric(title: "Reps", value: currentSet.map { "\($0.targetReps)" } ?? "--")
                    WatchGymMetric(
                        title: "Load",
                        value: currentSet.map { PulsarGymFormatters.weight($0.targetWeight, unit: currentExercise?.weightUnit ?? "kg") } ?? "--"
                    )
                }

                Button {
                    guard let exercise = currentExercise, let set = currentSet else { return }
                    WatchGymSessionManager.shared.completeSet(sessionId: state.sessionId, exerciseId: exercise.id, setId: set.id)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark.circle.fill")
                        Text(currentSet?.isCompleted == true ? "Completed" : "Complete Set")
                    }
                    .font(.headline.weight(.black))
                    .foregroundStyle(Color(red: 0.10, green: 0.08, blue: 0.16))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
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
                .disabled(currentSet == nil)
            }
        }
    }

    @ViewBuilder
    private var restCard: some View {
        if let remaining = state.restRemainingSeconds, remaining > 0 {
            WatchGymGlassCard {
                HStack(spacing: 8) {
                    Image(systemName: "timer")
                        .font(.headline.weight(.black))
                        .foregroundStyle(Color(red: 0.78, green: 0.72, blue: 1.0))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Rest")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(.white.opacity(0.58))
                        Text(PulsarGymFormatters.duration(remaining))
                            .font(.headline.weight(.black))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Button("Skip") {
                        WKInterfaceDevice.current().play(.click)
                        WatchGymSessionManager.shared.skipRest(sessionId: state.sessionId)
                    }
                    .font(.caption.weight(.black))
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.78))
                }
            }
        }
    }

    private var finishButton: some View {
        Button {
            Task {
                await WatchGymSessionManager.shared.finishWorkoutFromUser(sessionId: state.sessionId)
            }
        } label: {
            Text("Finish")
                .font(.headline.weight(.black))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.white.opacity(0.10), in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.13), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private var currentExercise: ActiveGymWorkoutExerciseState? {
        state.currentExercise
    }

    private var currentSet: ActiveGymWorkoutSetState? {
        state.currentSet
    }

    private var progressFraction: Double {
        guard state.totalSets > 0 else { return 1 }
        return min(max(Double(state.completedSets) / Double(state.totalSets), 0), 1)
    }

    private var subtitleText: String {
        guard let currentExercise else { return "Freestyle strength session" }
        return "\(currentExercise.muscleGroup) / \(currentExercise.equipment)"
    }

    private var energyText: String {
        guard let energy = state.activeEnergyKilocalories, energy > 0 else { return "--" }
        return "\(Int(energy.rounded()))"
    }
}

private struct WatchGymHeaderMetric: View {
    var symbolName: String
    var value: String
    var unit: String
    var tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbolName)
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundStyle(tint)
            VStack(alignment: .trailing, spacing: 0) {
                Text(value)
                    .font(.caption.weight(.black))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(unit)
                    .font(.system(size: 7, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.54))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }
}

private struct WatchGymGlassCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.09), Color(red: 0.72, green: 0.66, blue: 1.0).opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.13), lineWidth: 1)
            }
    }
}

private struct WatchGymMetric: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.caption.weight(.black))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(title)
                .font(.system(size: 8, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.52))
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}
