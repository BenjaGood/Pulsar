//
//  GymWorkoutSessionViews.swift
//  Pulsar
//

import SwiftUI
import UIKit

struct GymWorkoutSessionView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: GymWorkoutSessionViewModel
    @State private var selectedExerciseProgressTarget: ExerciseProgressLookup?
    @State private var selectedPreviousWeightsExercise: PulsarGymWorkoutExerciseSession?
    @State private var selectedDetailExercise: PulsarGymWorkoutExerciseSession?
    var onMinimize: (() -> Void)?
    var onFinish: () -> Void

    @MainActor
    init(
        routine: PulsarRoutine,
        workoutWeightUnit: PulsarWeightUnit? = nil,
        historyStore: PulsarGymWorkoutHistoryStore? = nil,
        onMinimize: (() -> Void)? = nil,
        onFinish: @escaping () -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: GymWorkoutSessionViewModel(
                routine: routine,
                workoutWeightUnit: workoutWeightUnit,
                historyStore: historyStore
            )
        )
        self.onMinimize = onMinimize
        self.onFinish = onFinish
    }

    @MainActor
    init(
        viewModel: GymWorkoutSessionViewModel,
        onMinimize: (() -> Void)? = nil,
        onFinish: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onMinimize = onMinimize
        self.onFinish = onFinish
    }

    var body: some View {
        ZStack {
            GymGlassBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                header
                if let message = viewModel.heartRateSourceBanner {
                    GymHeartRateSourceBanner(message: message)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let coaching = viewModel.adaptiveWorkoutCoaching {
                    AdaptiveGymCoachingBanner(coaching: coaching)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                GymWorkoutProgressCard(
                    completedSets: viewModel.completedSetsCount,
                    totalSets: viewModel.totalSetsCount,
                    completedExercises: viewModel.completedExercisesCount,
                    totalExercises: viewModel.totalExercisesCount,
                    progress: viewModel.progressFraction
                )

                exerciseList
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 10)
        }
        .safeAreaInset(edge: .bottom) {
            bottomControls
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
        }
        .overlay {
            if let summary = viewModel.summary {
                GymWorkoutSummaryOverlay(summary: summary) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onFinish()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .sheet(item: $selectedExerciseProgressTarget) { target in
            ExerciseProgressHistorySheet(target: target, displayUnit: target.displayUnit)
        }
        .sheet(item: $selectedPreviousWeightsExercise) { exercise in
            ExercisePreviousWeightsSheet(
                exercise: exercise,
                history: viewModel.progressHistory(for: exercise),
                recentSessions: viewModel.recentHistorySessions(for: exercise)
            ) {
                selectedExerciseProgressTarget = ExerciseProgressLookup(exercise: exercise)
            }
        }
        .sheet(item: $selectedDetailExercise) { exercise in
            GymSessionExerciseDetailSheet(exercise: exercise)
        }
        .task {
            await viewModel.startWorkoutIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                viewModel.refreshRestCountdown()
            }
        }
        .onChange(of: viewModel.supersetRoundCompletionPulse) { _, _ in
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: viewModel.completedSetsCount)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: viewModel.restCountdownSeconds)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: viewModel.summary)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: viewModel.heartRateSourceBanner)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: viewModel.adaptiveWorkoutCoaching?.id)
    }

    private var header: some View {
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
                systemImage: onMinimize == nil ? "xmark" : "chevron.down",
                accessibilityLabel: onMinimize == nil ? "Close workout" : "Minimize workout",
                size: 36,
                font: .caption.weight(.semibold),
                foregroundStyle: .white.opacity(0.78)
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if let onMinimize {
                    onMinimize()
                } else {
                    Task {
                        await viewModel.finishWorkout()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Text(viewModel.session.routineEmoji)
                    Text("Workout in progress")
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(.white.opacity(0.56))
                }

                Text(viewModel.session.routineName)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 8) {
                Text(viewModel.elapsedSeconds.formattedGymDuration)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.white.opacity(0.10), in: Capsule(style: .continuous))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    }

                GymHeartRatePill(
                    heartRate: viewModel.currentHeartRate,
                    isHealthKitEnabled: viewModel.isHealthKitEnabled,
                    statusMessage: viewModel.healthKitStatusMessage
                )

                GymCaloriesPill(
                    activeEnergyKilocalories: viewModel.activeEnergyKilocalories,
                    isHealthKitEnabled: viewModel.isHealthKitEnabled
                )
            }
        }
    }

    private var exerciseList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    if viewModel.session.exercises.isEmpty {
                        GymEmptySessionExerciseView()
                            .padding(.top, 12)
                    } else {
                        ForEach(viewModel.session.exercises.sorted { $0.orderIndex < $1.orderIndex }) { exercise in
                            if let groupID = exercise.supersetGroupId,
                               let group = viewModel.supersetGroup(id: groupID) {
                                if viewModel.isFirstSupersetMember(exercise) {
                                    GymSupersetSessionPairView(
                                        group: group,
                                        exercises: viewModel.supersetMembers(for: group),
                                        viewModel: viewModel,
                                        onShowDetails: { selectedDetailExercise = $0 },
                                        onShowProgress: { selectedPreviousWeightsExercise = $0 }
                                    )
                                }
                            } else {
                                GymSessionExerciseCard(
                                    exercise: exercise,
                                    viewModel: viewModel,
                                    supersetBadge: nil,
                                    allowsSetEditing: true,
                                    onShowDetails: { selectedDetailExercise = $0 },
                                    onShowProgress: { selectedPreviousWeightsExercise = $0 }
                                )
                            }
                        }
                    }
                }
                .padding(.bottom, 118)
            }
            .onChange(of: viewModel.focusTarget?.id) { _, _ in
                guard let target = viewModel.focusTarget else { return }
                withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) {
                    proxy.scrollTo(target.setID, anchor: .center)
                }
            }
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 10) {
            if let restCountdown = viewModel.restCountdownSeconds {
                GymRestTimerCard(
                    title: viewModel.restContext?.title ?? "Rest",
                    remainingSeconds: restCountdown,
                    progress: viewModel.restProgressFraction
                ) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.skipRest()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task {
                    await viewModel.finishWorkout()
                }
            } label: {
                HStack(spacing: 9) {
                    Text(viewModel.isWorkoutComplete ? "Finish Workout" : "Finish Early")
                    Image(systemName: viewModel.isWorkoutComplete ? "checkmark" : "flag.checkered")
                }
                .pulsarTextStyle(.cardTitle)
                .foregroundStyle(Color(red: 0.14, green: 0.09, blue: 0.22))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.98),
                            viewModel.isWorkoutComplete
                                ? Color(red: 0.74, green: 1.0, blue: 0.78)
                                : Color(red: 0.84, green: 0.78, blue: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Capsule(style: .continuous)
                )
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.54), lineWidth: 1)
                }
                .shadow(color: Color(red: 0.72, green: 0.66, blue: 1.0).opacity(0.28), radius: 20, y: 9)
            }
            .buttonStyle(PulsarGymPressButtonStyle())
            .disabled(viewModel.isFinishing)
        }
    }

    private func showProgress(for exercise: PulsarGymWorkoutExerciseSession) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        selectedExerciseProgressTarget = ExerciseProgressLookup(exercise: exercise, displayUnit: exercise.weightUnit)
    }

    private func openNowPlaying() {
        let urls = ["music://nowplaying", "music://"].compactMap(URL.init(string:))
        guard let url = urls.first else { return }
        UIApplication.shared.open(url)
    }
}

private struct GymHeartRateSourceBanner: View {
    var message: String

    var body: some View {
        Label(message, systemImage: "heart.text.square.fill")
            .pulsarTextStyle(.captionEmphasis)
            .foregroundStyle(.white.opacity(0.92))
            .lineLimit(2)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pulsarLiquidGlass(cornerRadius: 18)
    }
}

private struct AdaptiveGymCoachingBanner: View {
    var coaching: AdaptiveWorkoutCoaching

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(coaching.title)
                    .pulsarTextStyle(.captionEmphasis)
                Text(coaching.message)
                    .pulsarTextStyle(.captionEmphasis)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: symbol)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        }
    }

    private var tint: Color {
        switch coaching.severity {
        case .informational: .cyan
        case .caution, .protective: .orange
        }
    }

    private var symbol: String {
        switch coaching.severity {
        case .informational: "sparkles"
        case .caution: "heart.text.square.fill"
        case .protective: "shield.lefthalf.filled"
        }
    }
}

private struct GymHeartRatePill: View {
    var heartRate: Double?
    var isHealthKitEnabled: Bool
    var statusMessage: String?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.fill")
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.56))
                .symbolEffect(.pulse, options: .repeating, value: heartRate != nil)

            VStack(alignment: .trailing, spacing: 1) {
                Text(heartRateText)
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(.white)
                    .monospacedDigit()

                Text(statusText)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.085), in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(.white.opacity(0.11), lineWidth: 1)
        }
        .accessibilityLabel("Heart rate \(heartRateText)")
    }

    private var heartRateText: String {
        guard let heartRate, heartRate > 0 else { return "-- bpm" }
        return "\(Int(heartRate.rounded())) bpm"
    }

    private var statusText: String {
        if heartRate != nil { return "Live" }
        if isHealthKitEnabled { return "Reading..." }
        if statusMessage != nil { return "Health off" }
        return "Reading..."
    }
}

private struct GymCaloriesPill: View {
    var activeEnergyKilocalories: Double?
    var isHealthKitEnabled: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.34))

            VStack(alignment: .trailing, spacing: 1) {
                Text(caloriesText)
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(.white)
                    .monospacedDigit()

                Text(statusText)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.085), in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(.white.opacity(0.11), lineWidth: 1)
        }
        .accessibilityLabel("Active calories \(caloriesText)")
    }

    private var caloriesText: String {
        guard let activeEnergyKilocalories, activeEnergyKilocalories > 0 else { return "-- kcal" }
        return "\(Int(activeEnergyKilocalories.rounded())) kcal"
    }

    private var statusText: String {
        if activeEnergyKilocalories != nil { return "Active" }
        return isHealthKitEnabled ? "Calculating..." : "Health off"
    }
}

private struct GymWorkoutProgressCard: View {
    var completedSets: Int
    var totalSets: Int
    var completedExercises: Int
    var totalExercises: Int
    var progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                GymSessionStat(title: "Sets", value: "\(completedSets)/\(max(totalSets, 0))", symbolName: "checklist")
                GymSessionStat(title: "Exercises", value: "\(completedExercises)/\(max(totalExercises, 0))", symbolName: "dumbbell.fill")
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.08))

                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.72, green: 0.66, blue: 1.0), Color(red: 0.66, green: 1.0, blue: 0.78)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(10, proxy.size.width * min(max(progress, 0), 1)))
                }
            }
            .frame(height: 8)
        }
        .padding(14)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }
}

private struct GymSupersetSessionPairView: View {
    var group: PulsarSupersetGroup
    var exercises: [PulsarGymWorkoutExerciseSession]
    @ObservedObject var viewModel: GymWorkoutSessionViewModel
    var onShowDetails: (PulsarGymWorkoutExerciseSession) -> Void
    var onShowProgress: (PulsarGymWorkoutExerciseSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                HStack(spacing: 7) {
                    Image(systemName: "link")
                        .pulsarTextStyle(.captionEmphasis)
                    Text(viewModel.supersetLabel(for: group.id))
                        .pulsarTextStyle(.captionEmphasis)
                }
                .foregroundStyle(Color(red: 0.14, green: 0.09, blue: 0.22))
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(
                    LinearGradient(
                        colors: [.white.opacity(0.98), Color(red: 0.84, green: 0.78, blue: 1.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Capsule(style: .continuous)
                )

                Text("\(group.sharedSetCount) shared sets / \(group.restTimeSeconds.formattedRestLabel) rest")
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Spacer(minLength: 0)

                HStack(spacing: 7) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if let firstExerciseID = group.exerciseIds.first {
                            viewModel.removeLastSet(from: firstExerciseID)
                        }
                    } label: {
                        Image(systemName: "minus")
                            .pulsarTextStyle(.captionEmphasis)
                            .frame(width: 28, height: 28)
                            .background(.white.opacity(0.075), in: Circle())
                    }
                    .disabled(group.sharedSetCount <= 1)
                    .accessibilityLabel("Remove superset set")

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if let firstExerciseID = group.exerciseIds.first {
                            viewModel.addSet(to: firstExerciseID)
                        }
                    } label: {
                        Image(systemName: "plus")
                            .pulsarTextStyle(.captionEmphasis)
                            .frame(width: 28, height: 28)
                            .background(.white.opacity(0.095), in: Circle())
                    }
                    .accessibilityLabel("Add superset set")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.78))
            }
            .padding(.horizontal, 4)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.84, green: 0.78, blue: 1.0).opacity(0.72),
                                Color(red: 0.70, green: 1.0, blue: 0.76).opacity(0.44)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3)
                    .padding(.leading, 19)
                    .padding(.vertical, 20)

                VStack(spacing: 10) {
                    ForEach(exercises) { exercise in
                        GymSessionExerciseCard(
                            exercise: exercise,
                            viewModel: viewModel,
                            supersetBadge: viewModel.supersetBadge(for: exercise),
                            allowsSetEditing: false,
                            onShowDetails: onShowDetails,
                            onShowProgress: onShowProgress
                        )
                        .padding(.leading, 12)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct GymSessionExerciseCard: View {
    var exercise: PulsarGymWorkoutExerciseSession
    @ObservedObject var viewModel: GymWorkoutSessionViewModel
    var supersetBadge: String?
    var allowsSetEditing: Bool
    var onShowDetails: (PulsarGymWorkoutExerciseSession) -> Void
    var onShowProgress: (PulsarGymWorkoutExerciseSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    onShowDetails(exercise)
                } label: {
                    GymExerciseThumbnailView(
                        thumbnailURL: exercise.thumbnailURL,
                        muscleGroup: exercise.primaryMuscleGroup,
                        size: 44,
                        isCompleted: exercise.isCompleted
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(exercise.exerciseName) details")

                VStack(alignment: .leading, spacing: 5) {
                    if let supersetBadge {
                        Text(supersetBadge)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 0.78, green: 0.72, blue: 1.0))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(red: 0.72, green: 0.66, blue: 1.0).opacity(0.13), in: Capsule(style: .continuous))
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(Color(red: 0.78, green: 0.72, blue: 1.0).opacity(0.20), lineWidth: 1)
                            }
                    }

                    Button {
                        onShowDetails(exercise)
                    } label: {
                        HStack(spacing: 5) {
                            Text(exercise.exerciseName)
                                .pulsarTextStyle(.cardTitle)
                                .foregroundStyle(.white)
                                .lineLimit(2)

                            Image(systemName: "info.circle")
                                .pulsarTextStyle(.captionEmphasis)
                                .foregroundStyle(.white.opacity(0.44))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(exercise.exerciseName) details")

                    Text("\(exercise.primaryMuscleGroup.displayName) / \(exercise.equipment)")
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)

                    Text(planCaption)
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(Color(red: 0.75, green: 0.70, blue: 1.0))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 7) {
                    HStack(spacing: 7) {
                        Button {
                            onShowProgress(exercise)
                        } label: {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .pulsarTextStyle(.captionEmphasis)
                                .foregroundStyle(Color(red: 0.78, green: 0.72, blue: 1.0))
                                .frame(width: 28, height: 28)
                                .background(.white.opacity(0.075), in: Circle())
                                .overlay {
                                    Circle().stroke(.white.opacity(0.10), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Previous weights for \(exercise.exerciseName)")

                        Text("\(exercise.completedSetCount)/\(exercise.sets.count)")
                            .pulsarTextStyle(.captionEmphasis)
                            .foregroundStyle(exercise.isCompleted ? Color(red: 0.70, green: 1.0, blue: 0.76) : .white.opacity(0.58))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.08), in: Capsule(style: .continuous))
                    }

                    if allowsSetEditing {
                        HStack(spacing: 7) {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                viewModel.removeLastSet(from: exercise.id)
                            } label: {
                                Image(systemName: "minus")
                                    .pulsarTextStyle(.captionEmphasis)
                                    .foregroundStyle(.white.opacity(0.76))
                                    .frame(width: 28, height: 28)
                                    .background(.white.opacity(0.065), in: Circle())
                                    .overlay {
                                        Circle().stroke(.white.opacity(0.10), lineWidth: 1)
                                    }
                            }
                            .disabled(exercise.sets.count <= 1)
                            .accessibilityLabel("Remove set from \(exercise.exerciseName)")

                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                viewModel.addSet(to: exercise.id)
                            } label: {
                                Image(systemName: "plus")
                                    .pulsarTextStyle(.captionEmphasis)
                                    .foregroundStyle(.white.opacity(0.76))
                                    .frame(width: 28, height: 28)
                                    .background(.white.opacity(0.075), in: Circle())
                                    .overlay {
                                        Circle().stroke(.white.opacity(0.10), lineWidth: 1)
                                    }
                            }
                            .accessibilityLabel("Add set to \(exercise.exerciseName)")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let notes = exercise.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(notes)
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(.white.opacity(0.64))
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            if let snapshot = viewModel.previousPerformance(for: exercise) {
                GymPerformanceMemoryStrip(snapshot: snapshot)
            }

            VStack(spacing: 8) {
                ForEach(exercise.sets) { set in
                    GymWorkoutSetRow(
                        set: set,
                        weightUnit: exercise.weightUnit,
                        exerciseID: exercise.id,
                        viewModel: viewModel,
                        isHighlighted: viewModel.highlightedSetID == set.id
                    )
                }
            }
        }
        .padding(14)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        }
    }

    private var planCaption: String {
        if supersetBadge != nil {
            return "\(exercise.planSummary) / Shared superset sets"
        }
        return "\(exercise.planSummary) / Rest: \(exercise.plannedRestSeconds.formattedRestLabel)"
    }

    private var cardBackground: LinearGradient {
        LinearGradient(
            colors: exercise.isCompleted
                ? [Color(red: 0.66, green: 1.0, blue: 0.78).opacity(0.13), Color.white.opacity(0.070)]
                : [Color.white.opacity(0.080), Color.white.opacity(0.044)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBorder: Color {
        if exercise.isCompleted {
            return Color(red: 0.72, green: 1.0, blue: 0.78).opacity(0.32)
        }
        if supersetBadge != nil {
            return Color(red: 0.78, green: 0.72, blue: 1.0).opacity(0.26)
        }
        return .white.opacity(0.10)
    }
}

private struct GymPerformanceMemoryStrip: View {
    var snapshot: RoutinePerformanceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                GymPerformanceMemoryChip(symbol: "clock.arrow.circlepath", text: "Last: \(snapshot.lastPerformanceText)")
                GymPerformanceMemoryChip(symbol: "crown.fill", text: "Best: \(snapshot.bestPerformanceText)")
            }

            if let suggestion = snapshot.suggestion {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: suggestionIcon(for: suggestion.kind))
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(Color(red: 0.73, green: 1.0, blue: 0.78))
                    Text(suggestion.detail)
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(.white.opacity(0.76))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(Color(red: 0.62, green: 1.0, blue: 0.76).opacity(0.105), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(Color(red: 0.70, green: 1.0, blue: 0.78).opacity(0.16), lineWidth: 1)
                }
            }
        }
    }

    private func suggestionIcon(for kind: RoutineProgressionSuggestionKind) -> String {
        switch kind {
        case .addLoad:
            "plus.forwardslash.minus"
        case .repeatLoad:
            "repeat"
        case .easeBackIn:
            "leaf.fill"
        case .holdForm:
            "checkmark.seal.fill"
        }
    }
}

private struct GymPerformanceMemoryChip: View {
    var symbol: String
    var text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .pulsarTextStyle(.overline)
            Text(text)
                .pulsarTextStyle(.overline)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(.white.opacity(0.72))
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.white.opacity(0.070), in: Capsule(style: .continuous))
    }
}

private struct GymWorkoutSetRow: View {
    var set: PulsarGymWorkoutSetSession
    var weightUnit: PulsarWeightUnit
    var exerciseID: UUID
    @ObservedObject var viewModel: GymWorkoutSessionViewModel
    var isHighlighted: Bool
    @State private var isShowingEditor = false

    var body: some View {
        HStack(spacing: 12) {
            Text("Set \(set.setNumber)")
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(set.isCompleted ? Color(red: 0.70, green: 1.0, blue: 0.76) : .white.opacity(0.70))
                .frame(width: 54, alignment: .leading)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                isShowingEditor = true
            } label: {
                HStack(spacing: 10) {
                    Text("\(displayReps) reps")
                        .pulsarTextStyle(.label)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("\(displayWeight.formattedGymDecimal) \(weightUnit.displayName)")
                        .pulsarTextStyle(.label)
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.84))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "slider.horizontal.3")
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(.white.opacity(0.42))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit set \(set.setNumber)")
            .sheet(isPresented: $isShowingEditor) {
                GymSetEditorSheet(
                    setNumber: set.setNumber,
                    reps: displayReps,
                    weight: displayWeight,
                    weightUnit: weightUnit
                ) { reps, weight in
                    viewModel.updateSetValues(exerciseID: exerciseID, setID: set.id, reps: reps, weight: weight)
                }
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                let feedbackStyle: UIImpactFeedbackGenerator.FeedbackStyle = set.isCompleted ? .light : .medium
                UIImpactFeedbackGenerator(style: feedbackStyle).impactOccurred()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                    _ = viewModel.toggleSet(exerciseID: exerciseID, setID: set.id)
                }
            } label: {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .pulsarTextStyle(.sectionHeader)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(set.isCompleted ? Color(red: 0.70, green: 1.0, blue: 0.76) : .white.opacity(0.58))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(set.isCompleted ? "Mark set incomplete" : "Mark set complete")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .id(set.id)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(rowBorder, lineWidth: isHighlighted ? 1.5 : 1)
        }
    }

    private var displayReps: Int {
        self.set.completedReps ?? self.set.targetReps
    }

    private var displayWeight: Double {
        self.set.completedWeight ?? self.set.targetWeight
    }

    private var rowBackground: Color {
        if isHighlighted {
            return Color(red: 0.84, green: 0.78, blue: 1.0).opacity(0.20)
        }
        return set.isCompleted ? Color(red: 0.66, green: 1.0, blue: 0.78).opacity(0.12) : .white.opacity(0.055)
    }

    private var rowBorder: Color {
        if isHighlighted {
            return Color(red: 0.84, green: 0.78, blue: 1.0).opacity(0.60)
        }
        return set.isCompleted ? Color(red: 0.70, green: 1.0, blue: 0.76).opacity(0.28) : .white.opacity(0.08)
    }
}

private struct GymRestTimerCard: View {
    var title: String
    var remainingSeconds: Int
    var progress: Double
    var onSkip: () -> Void

    var body: some View {
        VStack(spacing: 11) {
            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .pulsarTextStyle(.cardTitle)
                    .foregroundStyle(Color(red: 0.84, green: 0.78, blue: 1.0))

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(title) \(remainingSeconds.formattedRestLabel)")
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(.white.opacity(0.56))

                    Text(remainingSeconds.formattedGymDuration)
                        .pulsarTextStyle(.cardTitle)
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }

                Spacer(minLength: 0)

                Button("Skip Rest", action: onSkip)
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(.white.opacity(0.78))
                    .buttonStyle(.plain)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.08))

                    Capsule(style: .continuous)
                        .fill(Color(red: 0.84, green: 0.78, blue: 1.0).opacity(0.92))
                        .frame(width: max(8, proxy.size.width * min(max(progress, 0), 1)))
                }
            }
            .frame(height: 7)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
    }
}

private struct GymSessionStat: View {
    var title: String
    var value: String
    var symbolName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbolName)
                .pulsarTextStyle(.label)
                .foregroundStyle(Color(red: 0.78, green: 0.71, blue: 1.0))

            Text(value)
                .pulsarTextStyle(.cardTitle)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text(title)
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(.white.opacity(0.58))
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.09), lineWidth: 1)
        }
    }
}

private struct GymEmptySessionExerciseView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 34, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.76))

            Text("Open session ready")
                .pulsarTextStyle(.cardTitle)
                .foregroundStyle(.white)

            Text("Finish when your freestyle lift is complete.")
                .pulsarTextStyle(.label)
                .foregroundStyle(.white.opacity(0.58))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }
}

struct GymWorkoutSummaryOverlay: View {
    var summary: PulsarGymWorkoutSummary
    var onDone: () -> Void
    @State private var selectedExerciseProgressTarget: ExerciseProgressLookup?

    var body: some View {
        WorkoutCompleteView(gymSummary: summary, onDone: onDone) {
            if !summary.completedExerciseSummaries.isEmpty {
                GymSummaryCompletedSetsView(exercises: summary.completedExerciseSummaries) { exercise in
                    selectedExerciseProgressTarget = ExerciseProgressLookup(
                        exerciseId: exercise.exerciseId,
                        exerciseName: exercise.exerciseName,
                        primaryMuscleGroup: exercise.primaryMuscleGroup,
                        equipment: exercise.equipment,
                        displayUnit: exercise.weightUnit
                    )
                }
            }
        }
        .sheet(item: $selectedExerciseProgressTarget) { target in
            ExerciseProgressHistorySheet(target: target, displayUnit: target.displayUnit)
        }
    }
}

private struct GymSummaryCompletedSetsView: View {
    var exercises: [PulsarGymCompletedExerciseSummary]
    var onSelectExercise: (PulsarGymCompletedExerciseSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Completed Sets", systemImage: "list.bullet.rectangle.fill")
                .pulsarTextStyle(.cardTitle)
                .foregroundStyle(.white)

            VStack(spacing: 10) {
                ForEach(exercises) { exercise in
                    GymCompletedExerciseCard(exercise: exercise) {
                        onSelectExercise(exercise)
                    }
                }
            }
        }
        .padding(16)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.13), lineWidth: 1)
        }
    }
}

private struct GymSummaryMetric: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .pulsarTextStyle(.cardTitle)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.74)

            Text(title)
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(.white.opacity(0.56))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }
}

#Preview {
    GymWorkoutSessionView(routine: .emptyGymWorkout()) {}
}
