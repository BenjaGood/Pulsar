//
//  GymWorkoutSessionViews.swift
//  Pulsar
//

import SwiftUI
import UIKit

struct GymWorkoutSessionView: View {
    @StateObject private var viewModel: GymWorkoutSessionViewModel
    var onFinish: () -> Void

    @MainActor
    init(routine: PulsarRoutine, onFinish: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: GymWorkoutSessionViewModel(routine: routine))
        self.onFinish = onFinish
    }

    var body: some View {
        ZStack {
            GymGlassBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                header

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
        .task {
            await viewModel.startWorkoutIfNeeded()
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: viewModel.completedSetsCount)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: viewModel.restCountdownSeconds)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: viewModel.summary)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Task {
                    await viewModel.finishWorkout()
                }
            } label: {
                Image(systemName: "xmark")
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
            .accessibilityLabel("Close workout")

            VStack(alignment: .leading, spacing: 7) {
                Text("Workout in progress")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white.opacity(0.56))

                Text(viewModel.session.routineName)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 8) {
                Text(viewModel.elapsedSeconds.formattedGymDuration)
                    .font(.system(size: 20, weight: .black, design: .rounded))
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
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                if viewModel.session.exercises.isEmpty {
                    GymEmptySessionExerciseView()
                        .padding(.top, 12)
                } else {
                    ForEach(viewModel.session.exercises.sorted { $0.orderIndex < $1.orderIndex }) { exercise in
                        GymSessionExerciseCard(exercise: exercise, viewModel: viewModel)
                    }
                }
            }
            .padding(.bottom, 118)
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 10) {
            if let restCountdown = viewModel.restCountdownSeconds {
                GymRestTimerCard(
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
                .font(.headline.weight(.bold))
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
}

private struct GymHeartRatePill: View {
    var heartRate: Double?
    var isHealthKitEnabled: Bool
    var statusMessage: String?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.fill")
                .font(.caption.weight(.black))
                .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.56))
                .symbolEffect(.pulse, options: .repeating, value: heartRate != nil)

            VStack(alignment: .trailing, spacing: 1) {
                Text(heartRateText)
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                    .monospacedDigit()

                Text(statusText)
                    .font(.system(size: 9, weight: .black, design: .rounded))
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
                .font(.caption.weight(.black))
                .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.34))

            VStack(alignment: .trailing, spacing: 1) {
                Text(caloriesText)
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                    .monospacedDigit()

                Text(statusText)
                    .font(.system(size: 9, weight: .black, design: .rounded))
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

private struct GymSessionExerciseCard: View {
    var exercise: PulsarGymWorkoutExerciseSession
    @ObservedObject var viewModel: GymWorkoutSessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(exercise.isCompleted ? Color(red: 0.66, green: 1.0, blue: 0.78).opacity(0.20) : .white.opacity(0.09))
                        .frame(width: 38, height: 38)

                    Image(systemName: exercise.isCompleted ? "checkmark" : "figure.strengthtraining.traditional")
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(exercise.isCompleted ? Color(red: 0.72, green: 1.0, blue: 0.78) : .white.opacity(0.76))
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(exercise.exerciseName)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text("\(exercise.primaryMuscleGroup.displayName) / \(exercise.equipment)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)

                    Text("\(exercise.planSummary) / \(exercise.plannedRestSeconds)s rest")
                        .font(.caption.weight(.black))
                        .foregroundStyle(Color(red: 0.75, green: 0.70, blue: 1.0))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Text("\(exercise.completedSetCount)/\(exercise.sets.count)")
                    .font(.caption.weight(.black))
                    .foregroundStyle(exercise.isCompleted ? Color(red: 0.70, green: 1.0, blue: 0.76) : .white.opacity(0.58))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.08), in: Capsule(style: .continuous))
            }

            if let notes = exercise.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(notes)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.64))
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            VStack(spacing: 8) {
                ForEach(exercise.sets) { set in
                    GymWorkoutSetRow(
                        set: set,
                        weightUnit: exercise.weightUnit,
                        exerciseID: exercise.id,
                        viewModel: viewModel
                    )
                }
            }
        }
        .padding(14)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(exercise.isCompleted ? Color(red: 0.72, green: 1.0, blue: 0.78).opacity(0.32) : .white.opacity(0.10), lineWidth: 1)
        }
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
}

private struct GymWorkoutSetRow: View {
    var set: PulsarGymWorkoutSetSession
    var weightUnit: PulsarWeightUnit
    var exerciseID: UUID
    @ObservedObject var viewModel: GymWorkoutSessionViewModel

    var body: some View {
        HStack(spacing: 12) {
            Text("Set \(set.setNumber)")
                .font(.caption.weight(.black))
                .foregroundStyle(set.isCompleted ? Color(red: 0.70, green: 1.0, blue: 0.76) : .white.opacity(0.70))
                .frame(width: 54, alignment: .leading)

            Text("\(set.targetReps) reps")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(set.targetWeight.formattedGymDecimal) \(weightUnit.displayName)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white.opacity(0.84))
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                UIImpactFeedbackGenerator(style: set.isCompleted ? .light : .medium).impactOccurred()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                    viewModel.toggleSet(exerciseID: exerciseID, setID: set.id)
                }
            } label: {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(set.isCompleted ? Color(red: 0.70, green: 1.0, blue: 0.76) : .white.opacity(0.58))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(set.isCompleted ? "Mark set incomplete" : "Mark set complete")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(set.isCompleted ? Color(red: 0.66, green: 1.0, blue: 0.78).opacity(0.12) : .white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(set.isCompleted ? Color(red: 0.70, green: 1.0, blue: 0.76).opacity(0.28) : .white.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct GymRestTimerCard: View {
    var remainingSeconds: Int
    var progress: Double
    var onSkip: () -> Void

    var body: some View {
        VStack(spacing: 11) {
            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .font(.headline.weight(.black))
                    .foregroundStyle(Color(red: 0.84, green: 0.78, blue: 1.0))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Rest")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white.opacity(0.56))

                    Text(remainingSeconds.formattedGymDuration)
                        .font(.headline.weight(.black))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }

                Spacer(minLength: 0)

                Button("Skip Rest", action: onSkip)
                    .font(.caption.weight(.black))
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
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color(red: 0.78, green: 0.71, blue: 1.0))

            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text(title)
                .font(.caption.weight(.semibold))
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
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)

            Text("Finish when your freestyle lift is complete.")
                .font(.subheadline.weight(.medium))
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

private struct GymWorkoutSummaryOverlay: View {
    var summary: PulsarGymWorkoutSummary
    var onDone: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.52)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 44, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color(red: 0.70, green: 1.0, blue: 0.76))

                VStack(spacing: 7) {
                    Text("Workout Complete")
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(summary.routineName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        GymSummaryMetric(title: "Duration", value: summary.durationSeconds.formattedGymDuration)
                        GymSummaryMetric(title: "Exercises", value: "\(summary.exercisesCompleted)/\(summary.totalExercises)")
                    }

                    HStack(spacing: 10) {
                        GymSummaryMetric(title: "Sets", value: "\(summary.setsCompleted)/\(summary.totalSets)")
                        GymSummaryMetric(title: "Volume", value: "\(summary.totalVolume.formattedGymDecimal) \(summary.weightUnit.displayName)")
                    }

                    HStack(spacing: 10) {
                        GymSummaryMetric(title: "Avg HR", value: summary.averageHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "--")
                        GymSummaryMetric(title: "Max HR", value: summary.maxHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "--")
                    }

                    GymSummaryMetric(title: "Active Calories", value: summary.activeEnergyKilocalories.map { "\(Int($0.rounded())) kcal" } ?? "--")
                }

                Button(action: onDone) {
                    Text("Done")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color(red: 0.14, green: 0.09, blue: 0.22))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [.white.opacity(0.98), Color(red: 0.74, green: 1.0, blue: 0.78)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Capsule(style: .continuous)
                        )
                }
                .buttonStyle(PulsarGymPressButtonStyle())
            }
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.30), radius: 28, y: 18)
            .padding(.horizontal, 24)
        }
    }
}

private struct GymSummaryMetric: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.headline.weight(.black))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.74)

            Text(title)
                .font(.caption.weight(.black))
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
