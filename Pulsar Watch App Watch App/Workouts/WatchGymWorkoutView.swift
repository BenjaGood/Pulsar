//
//  WatchGymWorkoutView.swift
//  Pulsar Watch App Watch App
//

import SwiftUI
import WatchKit

struct WatchActiveGymWorkoutView: View {
    var syncStore: PulsarWatchConnectivitySyncStore
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
                    .pulsarTextStyle(.watchLabel)
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
                    .pulsarTextStyle(.watchLabel)
                    .foregroundStyle(Color(red: 0.78, green: 0.72, blue: 1.0))
                Text(state.routineName)
                    .pulsarTextStyle(.watchTitle)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Text(PulsarGymFormatters.duration(displayElapsedSeconds(at: timeline.date)))
                        .pulsarMonospacedMetric(.watchValue)
                        .foregroundStyle(.white)
                }
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
                        .pulsarTextStyle(.watchMetric)
                        .foregroundStyle(.white)
                    Spacer()
                    Text(state.exerciseProgressText)
                        .pulsarTextStyle(.watchLabel)
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
                    .pulsarTextStyle(.watchTitle)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)

                Text(subtitleText)
                    .pulsarTextStyle(.watchSubtitle)
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)

                if let exercise = currentExercise, let set = currentSet {
                    VStack(spacing: 9) {
                        HStack {
                            Text("Set \(set.setNumber)")
                                .pulsarTextStyle(.watchLabel)
                                .foregroundStyle(Color(red: 0.72, green: 1.0, blue: 0.78))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(.white.opacity(0.10), in: Capsule(style: .continuous))

                            Spacer(minLength: 0)

                            Text(state.progressText)
                                .pulsarTextStyle(.watchLabel)
                                .foregroundStyle(.white.opacity(0.56))
                        }

                        WatchGymSetEditor(
                            sessionId: state.sessionId,
                            exercise: exercise,
                            set: set
                        )
                    }
                } else {
                    HStack(spacing: 8) {
                        WatchGymMetric(title: "Set", value: "--")
                        WatchGymMetric(title: "Reps", value: "--")
                        WatchGymMetric(title: "Load", value: "--")
                    }
                }

                Button {
                    guard let exercise = currentExercise, let set = currentSet else { return }
                    WatchGymSessionManager.shared.completeSet(
                        sessionId: state.sessionId,
                        exerciseId: exercise.id,
                        setId: set.id,
                        reps: set.completedReps ?? set.targetReps,
                        weight: set.completedWeight ?? set.targetWeight
                    )
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark.circle.fill")
                        Text(currentSet?.isCompleted == true ? "Completed" : "Complete Set")
                    }
                    .pulsarTextStyle(.watchButton)
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
        if let remaining = displayRestRemainingSeconds(), remaining > 0 {
            WatchGymGlassCard {
                HStack(spacing: 8) {
                    Image(systemName: "timer")
                        .pulsarTextStyle(.watchMetric)
                        .foregroundStyle(Color(red: 0.78, green: 0.72, blue: 1.0))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Rest")
                            .pulsarTextStyle(.watchLabel)
                            .foregroundStyle(.white.opacity(0.58))
                        TimelineView(.periodic(from: .now, by: 1)) { timeline in
                            Text(PulsarGymFormatters.duration(displayRestRemainingSeconds(at: timeline.date) ?? remaining))
                                .pulsarMonospacedMetric(.watchMetric)
                                .foregroundStyle(.white)
                        }
                    }
                    Spacer()
                    Button("Skip") {
                        WKInterfaceDevice.current().play(.click)
                        WatchGymSessionManager.shared.skipRest(sessionId: state.sessionId)
                    }
                    .pulsarTextStyle(.watchButton)
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
                .pulsarTextStyle(.watchButton)
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

    private func displayElapsedSeconds(at date: Date) -> Int {
        guard !state.isFinished else { return state.elapsedSeconds }
        return max(state.elapsedSeconds, Int(date.timeIntervalSince(state.startedAt)))
    }

    private func displayRestRemainingSeconds(at date: Date = Date()) -> Int? {
        guard let remaining = state.restRemainingSeconds, remaining > 0 else { return nil }
        let elapsedSinceSync = max(0, Int(date.timeIntervalSince(state.updatedAt)))
        return max(0, remaining - elapsedSinceSync)
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
                .pulsarTextStyle(.watchLabel)
                .foregroundStyle(tint)
            VStack(alignment: .trailing, spacing: 0) {
                Text(value)
                    .pulsarMonospacedMetric(.watchMetric)
                    .foregroundStyle(.white)
                Text(unit)
                    .pulsarTextStyle(.watchLabel)
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
                .pulsarMonospacedMetric(.watchMetric)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(title)
                .pulsarTextStyle(.watchLabel)
                .foregroundStyle(.white.opacity(0.52))
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

private enum WatchGymEditableSetField: String, Identifiable {
    case weight
    case reps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weight: "Load"
        case .reps: "Reps"
        }
    }

    var systemImage: String {
        switch self {
        case .weight: "scalemass.fill"
        case .reps: "number"
        }
    }

    var accent: Color {
        switch self {
        case .weight: Color(red: 0.72, green: 1.0, blue: 0.78)
        case .reps: Color(red: 0.78, green: 0.72, blue: 1.0)
        }
    }

    func initialValue(for set: ActiveGymWorkoutSetState) -> Double {
        switch self {
        case .weight:
            set.completedWeight ?? set.targetWeight
        case .reps:
            Double(set.completedReps ?? set.targetReps)
        }
    }

    func step(weightUnit: String) -> Double {
        switch self {
        case .weight:
            weightUnit.lowercased().contains("lb") ? 1 : 2.5
        case .reps:
            1
        }
    }

    func maximum(weightUnit: String) -> Double {
        switch self {
        case .weight:
            2_000
        case .reps:
            200
        }
    }

    func significantHapticInterval(weightUnit: String) -> Double {
        switch self {
        case .weight:
            weightUnit.lowercased().contains("lb") ? 10 : 5
        case .reps:
            5
        }
    }
}

private struct WatchGymSetEditor: View {
    var sessionId: UUID
    var exercise: ActiveGymWorkoutExerciseState
    var set: ActiveGymWorkoutSetState
    @State private var editingField: WatchGymEditableSetField?

    var body: some View {
        VStack(spacing: 8) {
            Button {
                beginEditing(.weight)
            } label: {
                WatchGymSetValueTile(
                    field: .weight,
                    value: weightValueText,
                    unit: exercise.weightUnit,
                    isCompleted: set.isCompleted
                )
            }
            .buttonStyle(.plain)
            .disabled(set.isCompleted)

            Button {
                beginEditing(.reps)
            } label: {
                WatchGymSetValueTile(
                    field: .reps,
                    value: "\(displayReps)",
                    unit: "reps",
                    isCompleted: set.isCompleted
                )
            }
            .buttonStyle(.plain)
            .disabled(set.isCompleted)
        }
        .sheet(item: $editingField) { field in
            WatchGymCrownSetValueEditor(
                sessionId: sessionId,
                exercise: exercise,
                set: set,
                field: field
            )
        }
    }

    private var displayReps: Int {
        self.set.completedReps ?? self.set.targetReps
    }

    private var displayWeight: Double {
        self.set.completedWeight ?? self.set.targetWeight
    }

    private var weightValueText: String {
        displayWeight.watchGymValueText
    }

    private func beginEditing(_ field: WatchGymEditableSetField) {
        WKInterfaceDevice.current().play(.click)
        editingField = field
    }
}

private struct WatchGymSetValueTile: View {
    var field: WatchGymEditableSetField
    var value: String
    var unit: String
    var isCompleted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: field.systemImage)
                .pulsarTextStyle(.watchMetric)
                .foregroundStyle(field.accent)
                .frame(width: 28, height: 28)
                .background(field.accent.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(field.title)
                    .pulsarTextStyle(.watchLabel)
                    .foregroundStyle(.white.opacity(0.56))
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .pulsarMonospacedMetric(.watchHeroValue)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                    Text(unit)
                        .pulsarTextStyle(.watchLabel)
                        .foregroundStyle(.white.opacity(0.62))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .background(.white.opacity(isCompleted ? 0.05 : 0.09), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(field.accent.opacity(isCompleted ? 0.12 : 0.28), lineWidth: 1)
        }
    }
}

private struct WatchGymCrownSetValueEditor: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isCrownFocused: Bool

    var sessionId: UUID
    var exercise: ActiveGymWorkoutExerciseState
    var set: ActiveGymWorkoutSetState
    var field: WatchGymEditableSetField

    @State private var draftValue: Double
    @State private var savedValue: Double
    @State private var hasSaved = false

    init(
        sessionId: UUID,
        exercise: ActiveGymWorkoutExerciseState,
        set: ActiveGymWorkoutSetState,
        field: WatchGymEditableSetField
    ) {
        self.sessionId = sessionId
        self.exercise = exercise
        self.set = set
        self.field = field
        let initialValue = field.initialValue(for: set)
        _draftValue = State(initialValue: initialValue)
        _savedValue = State(initialValue: initialValue)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.04, blue: 0.08),
                    Color(red: 0.10, green: 0.07, blue: 0.17),
                    field.accent.opacity(0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 10) {
                VStack(spacing: 3) {
                    Text(field.title)
                        .pulsarTextStyle(.watchLabel)
                        .foregroundStyle(field.accent)
                    Text("Set \(set.setNumber)")
                        .pulsarTextStyle(.watchSubtitle)
                        .foregroundStyle(.white.opacity(0.52))
                        .lineLimit(1)
                }

                VStack(spacing: 0) {
                    Text(primaryValueText)
                        .font(.system(size: field == .weight ? 42 : 52, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.54)

                    Text(secondaryValueText)
                        .pulsarTextStyle(.watchMetric)
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(field.accent.opacity(0.26), lineWidth: 1)
                }

                HStack(spacing: 10) {
                    adjustmentButton(systemName: "minus", delta: -step)
                    adjustmentButton(systemName: "plus", delta: step)
                }

                Button {
                    saveDraftIfNeeded()
                    WKInterfaceDevice.current().play(.success)
                    dismiss()
                } label: {
                    Text("Save")
                        .pulsarTextStyle(.watchButton)
                        .foregroundStyle(Color(red: 0.07, green: 0.06, blue: 0.11))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.white, in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
        }
        .focusable(true)
        .focused($isCrownFocused)
        .digitalCrownRotation(
            detent: crownBinding,
            from: minimumValue,
            through: maximumValue,
            by: step,
            sensitivity: crownSensitivity,
            isContinuous: false,
            isHapticFeedbackEnabled: false
        )
        .onAppear {
            isCrownFocused = true
        }
        .onDisappear {
            saveDraftIfNeeded()
        }
    }

    private var step: Double {
        field.step(weightUnit: exercise.weightUnit)
    }

    private var minimumValue: Double {
        field == .weight ? 0 : 1
    }

    private var maximumValue: Double {
        field.maximum(weightUnit: exercise.weightUnit)
    }

    private var crownSensitivity: DigitalCrownRotationalSensitivity {
        switch field {
        case .weight:
            .medium
        case .reps:
            .low
        }
    }

    private var primaryValueText: String {
        switch field {
        case .weight:
            draftValue.watchGymValueText
        case .reps:
            "\(Int(draftValue.rounded()))"
        }
    }

    private var secondaryValueText: String {
        switch field {
        case .weight:
            exercise.weightUnit
        case .reps:
            "reps"
        }
    }

    private var crownBinding: Binding<Double> {
        Binding(
            get: { draftValue },
            set: { updateDraft($0, playsStepHaptic: false) }
        )
    }

    private func adjustmentButton(systemName: String, delta: Double) -> some View {
        Button {
            updateDraft(draftValue + delta, playsStepHaptic: true)
        } label: {
            Image(systemName: systemName)
                .pulsarTextStyle(.watchMetric)
                .foregroundStyle(.white)
                .frame(width: 44, height: 34)
                .background(.white.opacity(0.10), in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func updateDraft(_ rawValue: Double, playsStepHaptic: Bool) {
        let sanitizedValue = sanitized(rawValue)
        guard abs(sanitizedValue - draftValue) > 0.0001 else {
            draftValue = sanitizedValue
            return
        }

        let previousValue = draftValue
        draftValue = sanitizedValue
        playHaptic(from: previousValue, to: sanitizedValue, playsStepHaptic: playsStepHaptic)
    }

    private func saveDraftIfNeeded() {
        guard !hasSaved else { return }
        hasSaved = true
        guard abs(draftValue - savedValue) > 0.0001 else { return }
        savedValue = draftValue
        switch field {
        case .weight:
            WatchGymSessionManager.shared.updateSetValues(
                sessionId: sessionId,
                exerciseId: exercise.id,
                setId: set.id,
                weight: draftValue,
                playsHaptic: false
            )
        case .reps:
            WatchGymSessionManager.shared.updateSetValues(
                sessionId: sessionId,
                exerciseId: exercise.id,
                setId: set.id,
                reps: Int(draftValue.rounded()),
                playsHaptic: false
            )
        }
    }

    private func sanitized(_ value: Double) -> Double {
        let clampedValue = min(max(value, minimumValue), maximumValue)
        switch field {
        case .weight:
            return (clampedValue / step).rounded() * step
        case .reps:
            return clampedValue.rounded()
        }
    }

    private func playHaptic(from previousValue: Double, to nextValue: Double, playsStepHaptic: Bool) {
        let interval = field.significantHapticInterval(weightUnit: exercise.weightUnit)
        let previousBucket = Int(floor(previousValue / interval))
        let nextBucket = Int(floor(nextValue / interval))
        if previousBucket != nextBucket {
            WKInterfaceDevice.current().play(nextValue > previousValue ? .directionUp : .directionDown)
        } else if playsStepHaptic {
            WKInterfaceDevice.current().play(.click)
        }
    }
}

private extension Double {
    var watchGymValueText: String {
        if rounded() == self {
            return String(Int(self))
        }
        return String(format: "%.1f", self)
    }
}
