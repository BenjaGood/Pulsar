//
//  GymWatchMirroredWorkoutView.swift
//  Pulsar
//

import SwiftUI
import UIKit

struct GymWatchMirroredWorkoutView: View {
    @EnvironmentObject private var completionPresentationStore: WorkoutCompletionPresentationStore
    @ObservedObject var syncStore: PulsarWatchConnectivitySyncStore
    var onMinimize: () -> Void
    var onSummaryDone: () -> Void
    @State private var finishedSummary: PulsarGymWorkoutSummary?
    @State private var lastMirroredState: ActiveGymWorkoutState?
    @State private var isRequestingFinish = false

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
            } else if let finishedSummary {
                GymWorkoutSummaryOverlay(summary: finishedSummary) {
                    onSummaryDone()
                }
            } else {
                completedState
            }
        }
        .onAppear {
            if let activeGymState = syncStore.activeGymState, activeGymState.isFinished {
                presentFinishedSummary(from: activeGymState)
                return
            }
            if syncStore.activeGymState == nil,
               let finishedState = syncStore.lastFinishedGymState {
                presentFinishedSummary(from: finishedState)
                return
            }
            guard let state else {
                onMinimize()
                return
            }
            lastMirroredState = state
            syncStore.sendGymAction(.requestState(sessionId: state.sessionId))
        }
        .onChange(of: syncStore.activeGymState) { _, newState in
            if let newState {
                if newState.isFinished {
                    presentFinishedSummary(from: newState)
                } else if syncStore.isRoutableActiveGymState(newState) {
                    lastMirroredState = newState
                }
            } else if finishedSummary == nil,
                      let finishedState = syncStore.lastFinishedGymState {
                presentFinishedSummary(from: finishedState)
            } else if finishedSummary == nil,
                      let lastMirroredState,
                      lastMirroredState.isFinished {
                presentFinishedSummary(from: lastMirroredState)
            }
        }
    }

    private func header(_ state: ActiveGymWorkoutState) -> some View {
        HStack(alignment: .top, spacing: 14) {
            PulsarWorkoutToolbarIconButton(
                systemImage: "music.note",
                accessibilityLabel: "Now Playing",
                size: 36,
                font: .caption.weight(.semibold),
                foregroundStyle: .white.opacity(0.84)
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                openNowPlaying()
            }

            PulsarWorkoutToolbarIconButton(
                systemImage: "chevron.down",
                accessibilityLabel: "Dismiss workout mirror",
                size: 36,
                font: .caption.weight(.semibold),
                foregroundStyle: .white.opacity(0.78)
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onMinimize()
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Text(state.routineEmoji ?? "🏋️")
                    Text("Apple Watch Gym")
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(.white.opacity(0.56))
                }

                Text(state.routineName)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 4)

            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Text(PulsarGymFormatters.duration(displayElapsedSeconds(for: state, at: timeline.date)))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
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
    }

    private func progressCard(_ state: ActiveGymWorkoutState) -> some View {
        GymWatchMirrorCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.progressText)
                            .pulsarTextStyle(.cardTitle)
                            .foregroundStyle(.white)
                        Text(state.exerciseProgressText)
                            .pulsarTextStyle(.captionEmphasis)
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
                        .pulsarTextStyle(.sectionHeader)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                    Text(subtitle(for: state))
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(.white.opacity(0.58))
                }

                if let exercise = state.currentExercise, let set = state.currentSet {
                    HStack(spacing: 10) {
                        GymWatchMirrorSetMetric(title: "Set", value: "\(set.setNumber)")
                        GymWatchMirrorSetEditor(
                            set: set,
                            weightUnit: exercise.weightUnit,
                            onUpdate: { reps, weight in
                                updateCurrentSetValues(state: state, exercise: exercise, set: set, reps: reps, weight: weight)
                            }
                        )
                    }
                } else {
                    HStack(spacing: 10) {
                        GymWatchMirrorSetMetric(title: "Set", value: "--")
                        GymWatchMirrorSetMetric(title: "Reps", value: "--")
                        GymWatchMirrorSetMetric(title: "Load", value: "--")
                    }
                }

                Button {
                    guard let exercise = state.currentExercise, let set = state.currentSet else { return }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    syncStore.sendGymAction(
                        .completeSet(
                            sessionId: state.sessionId,
                            exerciseId: exercise.id,
                            setId: set.id,
                            reps: set.completedReps ?? set.targetReps,
                            weight: set.completedWeight ?? set.targetWeight
                        )
                    )
                } label: {
                    Label("Complete Set", systemImage: "checkmark.circle.fill")
                        .pulsarTextStyle(.cardTitle)
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
        if let remaining = displayRestRemainingSeconds(for: state), remaining > 0 {
            GymWatchMirrorCard {
                HStack(spacing: 12) {
                    Image(systemName: "timer")
                        .pulsarTextStyle(.sectionHeader)
                        .foregroundStyle(Color(red: 0.78, green: 0.72, blue: 1.0))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rest")
                            .pulsarTextStyle(.captionEmphasis)
                            .foregroundStyle(.white.opacity(0.56))
                        TimelineView(.periodic(from: .now, by: 1)) { timeline in
                            Text(PulsarGymFormatters.duration(displayRestRemainingSeconds(for: state, at: timeline.date) ?? remaining))
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                        }
                    }
                    Spacer()
                    Button("Skip") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        syncStore.sendGymAction(.skipRestTimer(sessionId: state.sessionId))
                    }
                    .pulsarTextStyle(.cardTitle)
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.12))
                }
            }
        }
    }

    private func bottomControls(_ state: ActiveGymWorkoutState) -> some View {
        Button {
            guard !isRequestingFinish else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            isRequestingFinish = true
            syncStore.sendGymAction(.finishWorkout(sessionId: state.sessionId))
        } label: {
            HStack(spacing: 10) {
                if isRequestingFinish {
                    ProgressView()
                        .tint(.white)
                }
                Text(isRequestingFinish ? "Finishing workout..." : "Finish Workout")
                    .pulsarTextStyle(.cardTitle)
            }
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
        .disabled(isRequestingFinish)
    }

    private var completedState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(Color(red: 0.66, green: 1.0, blue: 0.78))
            Text("Workout finished")
                .pulsarTextStyle(.sectionHeader)
                .foregroundStyle(.white)
            Button("Done") {
                onSummaryDone()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func progressFraction(for state: ActiveGymWorkoutState) -> Double {
        guard state.totalSets > 0 else { return 1 }
        return min(max(Double(state.completedSets) / Double(state.totalSets), 0), 1)
    }

    private func displayElapsedSeconds(for state: ActiveGymWorkoutState, at date: Date) -> Int {
        guard !state.isFinished else { return state.elapsedSeconds }
        return max(state.elapsedSeconds, Int(date.timeIntervalSince(state.startedAt)))
    }

    private func displayRestRemainingSeconds(for state: ActiveGymWorkoutState, at date: Date = Date()) -> Int? {
        guard let remaining = state.restRemainingSeconds, remaining > 0 else { return nil }
        let elapsedSinceSync = max(0, Int(date.timeIntervalSince(state.updatedAt)))
        return max(0, remaining - elapsedSinceSync)
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

    private func presentFinishedSummary(from state: ActiveGymWorkoutState) {
        guard completionPresentationStore.shouldAutoPresent(sessionID: state.sessionId) else {
            finishedSummary = nil
            isRequestingFinish = false
            return
        }
        var finishedState = state
        let endedAt = state.isFinished ? state.updatedAt : Date()
        finishedState.isFinished = true
        finishedState.updatedAt = endedAt
        finishedState.elapsedSeconds = max(state.elapsedSeconds, Int(endedAt.timeIntervalSince(state.startedAt)))
        lastMirroredState = finishedState
        isRequestingFinish = false
        finishedSummary = PulsarGymWorkoutSummary(activeGymState: finishedState)
    }

    private func updateCurrentSetValues(
        state: ActiveGymWorkoutState,
        exercise: ActiveGymWorkoutExerciseState,
        set: ActiveGymWorkoutSetState,
        reps: Int? = nil,
        weight: Double? = nil
    ) {
        var nextState = state
        if let exerciseIndex = nextState.exercises.firstIndex(where: { $0.id == exercise.id }),
           let setIndex = nextState.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == set.id }) {
            if let reps {
                let nextReps = max(1, reps)
                nextState.exercises[exerciseIndex].sets[setIndex].targetReps = nextReps
                if nextState.exercises[exerciseIndex].sets[setIndex].isCompleted {
                    nextState.exercises[exerciseIndex].sets[setIndex].completedReps = nextReps
                }
            }
            if let weight {
                let nextWeight = max(0, weight)
                nextState.exercises[exerciseIndex].sets[setIndex].targetWeight = nextWeight
                if nextState.exercises[exerciseIndex].sets[setIndex].isCompleted {
                    nextState.exercises[exerciseIndex].sets[setIndex].completedWeight = nextWeight
                }
            }
            nextState.updatedAt = Date()
            syncStore.storeActiveGymState(nextState, broadcast: false, reason: "gymMirrorSetAdjusted")
        }

        syncStore.sendGymAction(
            .updateSetValues(
                sessionId: state.sessionId,
                exerciseId: exercise.id,
                setId: set.id,
                reps: reps,
                weight: weight
            )
        )
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
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(tint)
            VStack(alignment: .trailing, spacing: 1) {
                Text(value)
                    .pulsarTextStyle(.label)
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(subtitle)
                    .pulsarTextStyle(.overline)
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
                .pulsarTextStyle(.cardTitle)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(.white.opacity(0.50))
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct GymWatchMirrorSetEditor: View {
    var set: ActiveGymWorkoutSetState
    var weightUnit: String
    var onUpdate: (Int?, Double?) -> Void

    var body: some View {
        VStack(spacing: 8) {
            GymWatchMirrorSetStepper(
                title: "Reps",
                value: "\(displayReps)",
                onMinus: { onUpdate(max(1, displayReps - 1), nil) },
                onPlus: { onUpdate(min(200, displayReps + 1), nil) }
            )

            GymWatchMirrorSetStepper(
                title: "Load",
                value: PulsarGymFormatters.weight(displayWeight, unit: weightUnit),
                onMinus: { onUpdate(nil, max(0, displayWeight - weightStep)) },
                onPlus: { onUpdate(nil, displayWeight + weightStep) }
            )
        }
        .disabled(set.isCompleted)
    }

    private var displayReps: Int {
        self.set.completedReps ?? self.set.targetReps
    }

    private var displayWeight: Double {
        self.set.completedWeight ?? self.set.targetWeight
    }

    private var weightStep: Double {
        weightUnit.lowercased().contains("lb") ? 5 : 2.5
    }
}

private struct GymWatchMirrorSetStepper: View {
    var title: String
    var value: String
    var onMinus: () -> Void
    var onPlus: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .pulsarTextStyle(.label)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(title)
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(.white.opacity(0.50))
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Button(action: onMinus) {
                    Image(systemName: "minus")
                        .pulsarTextStyle(.captionEmphasis)
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.08), in: Circle())
                }

                Button(action: onPlus) {
                    Image(systemName: "plus")
                        .pulsarTextStyle(.captionEmphasis)
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.11), in: Circle())
                }
            }
            .buttonStyle(.plain)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    GymWatchMirroredWorkoutView(syncStore: .shared, onMinimize: {}, onSummaryDone: {})
}
