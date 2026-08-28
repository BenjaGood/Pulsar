//
//  GymMirroredCurrentExerciseCard.swift
//  Pulsar
//

import SwiftUI

struct GymMirroredCurrentExerciseCard: View {
    let state: ActiveGymWorkoutState
    let onCompleteSet: () -> Void
    let onUpdateSet: (Int?, Double?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(GymWatchMirroredWorkoutView.currentExerciseTitle(for: state))
                        .font(.title2.bold())
                        .fontDesign(.default)
                        .foregroundStyle(Color.black)
                        .lineLimit(2)
                        .minimumScaleFactor(0.76)

                    Text(exerciseSubtitle)
                        .font(.body)
                        .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                        .lineLimit(2)

                    if let categoryLabel {
                        Label(categoryLabel, systemImage: "sparkle")
                            .font(.subheadline)
                            .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 38)
                            .pulsarLiquidGlass(cornerRadius: 19, isClear: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let exercise = state.currentExercise {
                    GymExerciseThumbnailView(
                        thumbnailURL: exercise.thumbnailURL,
                        muscleGroup: .liveWorkoutValue(for: exercise.muscleGroup),
                        size: 96,
                        isCompleted: exercise.isCompleted
                    )
                    .accessibilityLabel("Exercise illustration for \(exercise.exerciseName)")
                    .accessibilityHidden(false)
                }
            }

            if let exercise = state.currentExercise, let set = state.currentSet {
                HStack(spacing: 12) {
                    GymMirroredSetNumber(setNumber: set.setNumber)
                    GymMirroredSetEditor(
                        set: set,
                        weightUnit: exercise.weightUnit,
                        onUpdate: onUpdateSet
                    )
                }
            } else {
                GymMirroredUnavailableSet()
            }

            Button("Complete Set", systemImage: "checkmark.circle", action: onCompleteSet)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 58)
                .background(Color.black, in: .capsule)
                .buttonStyle(.plain)
                .disabled(state.currentSet == nil || state.currentSet?.isCompleted == true)
                .opacity(state.currentSet == nil || state.currentSet?.isCompleted == true ? 0.45 : 1)
                .accessibilityHint("Completes the current set and syncs it with Apple Watch.")
        }
        .padding(20)
        .gymWorkoutWhiteGlassSurface(cornerRadius: 30)
    }

    private var exerciseSubtitle: String {
        guard let exercise = state.currentExercise else { return "Tracking from Apple Watch" }
        return "\(exercise.muscleGroup) / \(exercise.equipment)"
    }

    private var categoryLabel: String? {
        guard let rawValue = state.currentExercise?.supersetType,
              let type = PulsarSupersetType(rawValue: rawValue) else { return nil }
        return type.displayName
    }
}

private struct GymMirroredSetNumber: View {
    let setNumber: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("\(setNumber)")
                .font(.largeTitle.bold().monospacedDigit())
            Text("Set")
                .font(.body)
                .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
        }
        .foregroundStyle(Color.black)
        .padding(16)
        .frame(width: 118, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.62), in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(PulsarFitnessMonochromeDesign.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct GymMirroredSetEditor: View {
    let set: ActiveGymWorkoutSetState
    let weightUnit: String
    let onUpdate: (Int?, Double?) -> Void

    var body: some View {
        VStack(spacing: 10) {
            GymMirroredSetStepper(
                title: "Reps",
                value: "\(displayReps)",
                decreaseLabel: "Decrease reps",
                increaseLabel: "Increase reps",
                onDecrease: decreaseReps,
                onIncrease: increaseReps
            )

            GymMirroredSetStepper(
                title: "Load",
                value: PulsarGymFormatters.weight(displayWeight, unit: weightUnit),
                decreaseLabel: "Decrease weight",
                increaseLabel: "Increase weight",
                onDecrease: decreaseWeight,
                onIncrease: increaseWeight
            )
        }
        .frame(maxWidth: .infinity)
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

    private func decreaseReps() {
        onUpdate(max(1, displayReps - 1), nil)
    }

    private func increaseReps() {
        onUpdate(min(200, displayReps + 1), nil)
    }

    private func decreaseWeight() {
        onUpdate(nil, max(0, displayWeight - weightStep))
    }

    private func increaseWeight() {
        onUpdate(nil, displayWeight + weightStep)
    }
}

private struct GymMirroredSetStepper: View {
    let title: String
    let value: String
    let decreaseLabel: String
    let increaseLabel: String
    let onDecrease: () -> Void
    let onIncrease: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(Color.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
            }

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                Button(decreaseLabel, systemImage: "minus", action: onDecrease)
                    .labelStyle(.iconOnly)
                    .frame(width: 40, height: 44)
                    .pulsarLiquidGlass(cornerRadius: 20, interactive: true, isClear: true)

                Button(increaseLabel, systemImage: "plus", action: onIncrease)
                    .labelStyle(.iconOnly)
                    .frame(width: 40, height: 44)
                    .pulsarLiquidGlass(cornerRadius: 20, interactive: true, isClear: true)
            }
            .font(.title3)
            .foregroundStyle(Color.black)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 66)
        .background(Color.white.opacity(0.62), in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(PulsarFitnessMonochromeDesign.hairline, lineWidth: 1)
        }
    }
}

private struct GymMirroredUnavailableSet: View {
    var body: some View {
        ContentUnavailableView(
            "Routine Loading",
            systemImage: "applewatch.radiowaves.left.and.right",
            description: Text("Set details will appear when Apple Watch sends the routine.")
        )
        .frame(maxWidth: .infinity, minHeight: 132)
    }
}

extension PulsarMuscleGroup {
    static func liveWorkoutValue(for value: String) -> PulsarMuscleGroup {
        let normalized = value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }

        return allCases.first { group in
            let raw = group.rawValue.lowercased().filter { $0.isLetter || $0.isNumber }
            let display = group.displayName.lowercased().filter { $0.isLetter || $0.isNumber }
            return normalized == raw || normalized == display
        } ?? .other
    }
}
