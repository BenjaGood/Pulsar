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
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: viewModel.restContext)
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
                foregroundStyle: PulsarFitnessMonochromeDesign.secondaryText
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                openNowPlaying()
            }

            PulsarWorkoutToolbarIconButton(
                systemImage: onMinimize == nil ? "xmark" : "chevron.down",
                accessibilityLabel: onMinimize == nil ? "Close workout" : "Minimize workout",
                size: 36,
                font: .caption.weight(.semibold),
                foregroundStyle: PulsarFitnessMonochromeDesign.secondaryText
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
                        .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                }

                Text(viewModel.session.routineName)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 8) {
                GymWorkoutElapsedClockView(clock: viewModel.clock)

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
                        ForEach(viewModel.orderedExercises) { exercise in
                            if let groupID = exercise.supersetGroupId,
                               let group = viewModel.supersetGroup(id: groupID) {
                                if viewModel.isFirstSupersetMember(exercise) {
                                    let exercises = viewModel.supersetMembers(for: group)
                                    GymSupersetSessionPairView(
                                        group: group,
                                        exercises: exercises,
                                        label: viewModel.supersetLabel(for: group.id),
                                        badges: Dictionary(
                                            uniqueKeysWithValues: exercises.compactMap { exercise in
                                                viewModel.supersetBadge(for: exercise).map { (exercise.id, $0) }
                                            }
                                        ),
                                        previousPerformances: Dictionary(
                                            uniqueKeysWithValues: exercises.compactMap { exercise in
                                                viewModel.previousPerformance(for: exercise).map { (exercise.id, $0) }
                                            }
                                        ),
                                        highlightedSetID: viewModel.highlightedSetID,
                                        actions: exerciseActions,
                                        onShowDetails: { selectedDetailExercise = $0 },
                                        onShowProgress: { selectedPreviousWeightsExercise = $0 }
                                    )
                                    .equatable()
                                }
                            } else {
                                GymSessionExerciseCard(
                                    exercise: exercise,
                                    supersetBadge: nil,
                                    allowsSetEditing: true,
                                    previousPerformance: viewModel.previousPerformance(for: exercise),
                                    highlightedSetID: viewModel.highlightedSetID,
                                    actions: exerciseActions,
                                    onShowDetails: { selectedDetailExercise = $0 },
                                    onShowProgress: { selectedPreviousWeightsExercise = $0 }
                                )
                                .equatable()
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
            GymWorkoutRestTimerHost(
                clock: viewModel.clock,
                title: viewModel.restContext?.title ?? "Rest"
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.skipRest()
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
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.98),
                            viewModel.isWorkoutComplete
                                ? PulsarFitnessMonochromeDesign.primaryText
                                : PulsarFitnessMonochromeDesign.primaryText
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
                .shadow(color: PulsarFitnessMonochromeDesign.primaryText.opacity(0.28), radius: 20, y: 9)
            }
            .buttonStyle(PulsarGymPressButtonStyle())
            .disabled(viewModel.isFinishing)
        }
    }

    private var exerciseActions: GymSessionExerciseActions {
        GymSessionExerciseActions(
            addSet: { viewModel.addSet(to: $0) },
            removeLastSet: { viewModel.removeLastSet(from: $0) },
            updateSetValues: { exerciseID, setID, reps, weight in
                viewModel.updateSetValues(
                    exerciseID: exerciseID,
                    setID: setID,
                    reps: reps,
                    weight: weight
                )
            },
            toggleSet: { exerciseID, setID in
                _ = viewModel.toggleSet(exerciseID: exerciseID, setID: setID)
            }
        )
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
            .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
            .lineLimit(2)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pulsarLiquidGlass(cornerRadius: 18)
    }
}

private struct GymWorkoutElapsedClockView: View {
    @ObservedObject var clock: GymWorkoutSessionClock

    var body: some View {
        Text(clock.elapsedSeconds.formattedGymDuration)
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.white.opacity(0.10), in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
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
        case .informational: PulsarFitnessMonochromeDesign.primaryText
        case .caution, .protective: PulsarFitnessMonochromeDesign.primaryText
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
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                .symbolEffect(.pulse, options: .repeating, value: heartRate != nil)

            VStack(alignment: .trailing, spacing: 1) {
                Text(heartRateText)
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                    .monospacedDigit()

                Text(statusText)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
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
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)

            VStack(alignment: .trailing, spacing: 1) {
                Text(caloriesText)
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                    .monospacedDigit()

                Text(statusText)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
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
                                colors: [PulsarFitnessMonochromeDesign.primaryText, PulsarFitnessMonochromeDesign.primaryText],
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

private struct GymSessionExerciseActions {
    var addSet: (UUID) -> Void
    var removeLastSet: (UUID) -> Void
    var updateSetValues: (UUID, UUID, Int, Double) -> Void
    var toggleSet: (UUID, UUID) -> Void
}

private struct GymSupersetSessionPairView: View, Equatable {
    var group: PulsarSupersetGroup
    var exercises: [PulsarGymWorkoutExerciseSession]
    var label: String
    var badges: [UUID: String]
    var previousPerformances: [UUID: RoutinePerformanceSnapshot]
    var highlightedSetID: UUID?
    var actions: GymSessionExerciseActions
    var onShowDetails: (PulsarGymWorkoutExerciseSession) -> Void
    var onShowProgress: (PulsarGymWorkoutExerciseSession) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.group == rhs.group &&
            lhs.exercises == rhs.exercises &&
            lhs.label == rhs.label &&
            lhs.badges == rhs.badges &&
            lhs.previousPerformances == rhs.previousPerformances &&
            lhs.highlightedSetID == rhs.highlightedSetID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                HStack(spacing: 7) {
                    Image(systemName: "link")
                        .pulsarTextStyle(.captionEmphasis)
                    Text(label)
                        .pulsarTextStyle(.captionEmphasis)
                }
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(
                    LinearGradient(
                        colors: [.white.opacity(0.98), PulsarFitnessMonochromeDesign.primaryText],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Capsule(style: .continuous)
                )

                Text("\(group.sharedSetCount) shared sets / \(group.restTimeSeconds.formattedRestLabel) rest")
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Spacer(minLength: 0)

                HStack(spacing: 7) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if let firstExerciseID = group.exerciseIds.first {
                            actions.removeLastSet(firstExerciseID)
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
                            actions.addSet(firstExerciseID)
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
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
            }
            .padding(.horizontal, 4)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                PulsarFitnessMonochromeDesign.primaryText.opacity(0.72),
                                PulsarFitnessMonochromeDesign.primaryText.opacity(0.44)
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
                            supersetBadge: badges[exercise.id],
                            allowsSetEditing: false,
                            previousPerformance: previousPerformances[exercise.id],
                            highlightedSetID: highlightedSetID,
                            actions: actions,
                            onShowDetails: onShowDetails,
                            onShowProgress: onShowProgress
                        )
                        .equatable()
                        .padding(.leading, 12)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct GymSessionExerciseCard: View, Equatable {
    var exercise: PulsarGymWorkoutExerciseSession
    var supersetBadge: String?
    var allowsSetEditing: Bool
    var previousPerformance: RoutinePerformanceSnapshot?
    var highlightedSetID: UUID?
    var actions: GymSessionExerciseActions
    var onShowDetails: (PulsarGymWorkoutExerciseSession) -> Void
    var onShowProgress: (PulsarGymWorkoutExerciseSession) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.exercise == rhs.exercise &&
            lhs.supersetBadge == rhs.supersetBadge &&
            lhs.allowsSetEditing == rhs.allowsSetEditing &&
            lhs.previousPerformance == rhs.previousPerformance &&
            lhs.highlightedSetID == rhs.highlightedSetID
    }

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
                            .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(PulsarFitnessMonochromeDesign.primaryText.opacity(0.13), in: Capsule(style: .continuous))
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(PulsarFitnessMonochromeDesign.primaryText.opacity(0.20), lineWidth: 1)
                            }
                    }

                    Button {
                        onShowDetails(exercise)
                    } label: {
                        HStack(spacing: 5) {
                            Text(exercise.exerciseName)
                                .pulsarTextStyle(.cardTitle)
                                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                                .lineLimit(2)

                            Image(systemName: "info.circle")
                                .pulsarTextStyle(.captionEmphasis)
                                .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(exercise.exerciseName) details")

                    Text("\(exercise.primaryMuscleGroup.displayName) / \(exercise.equipment)")
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                        .lineLimit(1)

                    Text(planCaption)
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
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
                                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
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
                            .foregroundStyle(exercise.isCompleted ? PulsarFitnessMonochromeDesign.primaryText  : PulsarFitnessMonochromeDesign.secondaryText)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.08), in: Capsule(style: .continuous))
                    }

                    if allowsSetEditing {
                        HStack(spacing: 7) {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                actions.removeLastSet(exercise.id)
                            } label: {
                                Image(systemName: "minus")
                                    .pulsarTextStyle(.captionEmphasis)
                                    .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
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
                                actions.addSet(exercise.id)
                            } label: {
                                Image(systemName: "plus")
                                    .pulsarTextStyle(.captionEmphasis)
                                    .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
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
                    .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            if let snapshot = previousPerformance {
                GymPerformanceMemoryStrip(snapshot: snapshot)
            }

            VStack(spacing: 8) {
                ForEach(exercise.sets) { set in
                    GymWorkoutSetRow(
                        set: set,
                        weightUnit: exercise.weightUnit,
                        exerciseID: exercise.id,
                        isHighlighted: highlightedSetID == set.id,
                        onUpdate: { reps, weight in
                            actions.updateSetValues(exercise.id, set.id, reps, weight)
                        },
                        onToggle: {
                            actions.toggleSet(exercise.id, set.id)
                        }
                    )
                    .equatable()
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
                ? [PulsarFitnessMonochromeDesign.primaryText.opacity(0.13), Color.white.opacity(0.070)]
                : [Color.white.opacity(0.080), Color.white.opacity(0.044)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBorder: Color {
        if exercise.isCompleted {
            return PulsarFitnessMonochromeDesign.primaryText.opacity(0.32)
        }
        if supersetBadge != nil {
            return PulsarFitnessMonochromeDesign.primaryText.opacity(0.26)
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
                        .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                    Text(suggestion.detail)
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(PulsarFitnessMonochromeDesign.primaryText.opacity(0.105), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(PulsarFitnessMonochromeDesign.primaryText.opacity(0.16), lineWidth: 1)
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
        .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.white.opacity(0.070), in: Capsule(style: .continuous))
    }
}

private struct GymWorkoutSetRow: View, Equatable {
    var set: PulsarGymWorkoutSetSession
    var weightUnit: PulsarWeightUnit
    var exerciseID: UUID
    var isHighlighted: Bool
    var onUpdate: (Int, Double) -> Void
    var onToggle: () -> Void
    @State private var isShowingEditor = false

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.set == rhs.set &&
            lhs.weightUnit == rhs.weightUnit &&
            lhs.exerciseID == rhs.exerciseID &&
            lhs.isHighlighted == rhs.isHighlighted
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("Set \(set.setNumber)")
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(set.isCompleted ? PulsarFitnessMonochromeDesign.primaryText  : PulsarFitnessMonochromeDesign.secondaryText)
                .frame(width: 54, alignment: .leading)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                isShowingEditor = true
            } label: {
                HStack(spacing: 10) {
                    Text("\(displayReps) reps")
                        .pulsarTextStyle(.label)
                        .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("\(displayWeight.formattedGymDecimal) \(weightUnit.displayName)")
                        .pulsarTextStyle(.label)
                        .monospacedDigit()
                        .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "slider.horizontal.3")
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
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
                    onUpdate(reps, weight)
                }
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                let feedbackStyle: UIImpactFeedbackGenerator.FeedbackStyle = set.isCompleted ? .light : .medium
                UIImpactFeedbackGenerator(style: feedbackStyle).impactOccurred()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                    onToggle()
                }
            } label: {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .pulsarTextStyle(.sectionHeader)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(set.isCompleted ? PulsarFitnessMonochromeDesign.primaryText  : PulsarFitnessMonochromeDesign.secondaryText)
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
            return PulsarFitnessMonochromeDesign.primaryText.opacity(0.20)
        }
        return set.isCompleted ? PulsarFitnessMonochromeDesign.primaryText.opacity(0.12) : .white.opacity(0.055)
    }

    private var rowBorder: Color {
        if isHighlighted {
            return PulsarFitnessMonochromeDesign.primaryText.opacity(0.60)
        }
        return set.isCompleted ? PulsarFitnessMonochromeDesign.primaryText.opacity(0.28) : .white.opacity(0.08)
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
                    .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(title) \(remainingSeconds.formattedRestLabel)")
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)

                    Text(remainingSeconds.formattedGymDuration)
                        .pulsarTextStyle(.cardTitle)
                        .monospacedDigit()
                        .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                }

                Spacer(minLength: 0)

                Button("Skip Rest", action: onSkip)
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                    .buttonStyle(.plain)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.08))

                    Capsule(style: .continuous)
                        .fill(PulsarFitnessMonochromeDesign.primaryText.opacity(0.92))
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

private struct GymWorkoutRestTimerHost: View {
    @ObservedObject var clock: GymWorkoutSessionClock
    var title: String
    var onSkip: () -> Void

    var body: some View {
        if let remainingSeconds = clock.restCountdownSeconds {
            GymRestTimerCard(
                title: title,
                remainingSeconds: remainingSeconds,
                progress: clock.restProgressFraction,
                onSkip: onSkip
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(
                .spring(response: 0.34, dampingFraction: 0.84),
                value: remainingSeconds
            )
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
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)

            Text(value)
                .pulsarTextStyle(.cardTitle)
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text(title)
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
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
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)

            Text("Open session ready")
                .pulsarTextStyle(.cardTitle)
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)

            Text("Finish when your freestyle lift is complete.")
                .pulsarTextStyle(.label)
                .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
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
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)

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
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.74)

            Text(title)
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
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
