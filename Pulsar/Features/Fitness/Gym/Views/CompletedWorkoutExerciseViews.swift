//
//  CompletedWorkoutExerciseViews.swift
//  Pulsar
//

import SwiftUI
import UIKit

struct CompletedWorkoutSetEditContext: Identifiable, Hashable {
    var exerciseId: UUID
    var setId: UUID
    var setNumber: Int
    var reps: Int
    var weight: Double
    var weightUnit: PulsarWeightUnit

    var id: String { "\(exerciseId.uuidString)-\(setId.uuidString)" }
}

struct CompletedWorkoutExercisesSection: View {
    var exercises: [CompletedWorkoutExercisePresentation]
    var expandedExerciseIds: Set<UUID>
    var isEditable: Bool
    var onToggleExercise: (UUID) -> Void
    var onExpandAll: () -> Void
    var onCollapseAll: () -> Void
    var onShowHistory: (CompletedWorkoutExercisePresentation) -> Void
    var onShowInstructions: (CompletedWorkoutExercisePresentation) -> Void
    var onEditSet: (CompletedWorkoutSetEditContext) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            LazyVStack(spacing: 12) {
                ForEach(exercises) { exercise in
                    CompletedWorkoutExerciseCard(
                        exercise: exercise,
                        isExpanded: expandedExerciseIds.contains(exercise.id),
                        isEditable: isEditable,
                        onToggle: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onToggleExercise(exercise.id)
                        },
                        onShowHistory: { onShowHistory(exercise) },
                        onShowInstructions: { onShowInstructions(exercise) },
                        onEditSet: onEditSet
                    )
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Completed Exercises")
                .pulsarTextStyle(.sectionHeader)
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)

            Spacer(minLength: 0)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if allExpanded {
                    onCollapseAll()
                } else {
                    onExpandAll()
                }
            } label: {
                Label(allExpanded ? "Collapse All" : "Expand All", systemImage: allExpanded ? "chevron.up" : "chevron.down")
                    .pulsarTextStyle(.captionEmphasis)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.white.opacity(0.075), in: Capsule(style: .continuous))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(allExpanded ? "Collapse all completed exercises" : "Expand all completed exercises")
        }
        .padding(.horizontal, 2)
    }

    private var allExpanded: Bool {
        !exercises.isEmpty && exercises.allSatisfy { expandedExerciseIds.contains($0.id) }
    }
}

private struct CompletedWorkoutExerciseCard: View {
    var exercise: CompletedWorkoutExercisePresentation
    var isExpanded: Bool
    var isEditable: Bool
    var onToggle: () -> Void
    var onShowHistory: () -> Void
    var onShowInstructions: () -> Void
    var onEditSet: (CompletedWorkoutSetEditContext) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    indexBadge

                    Text(exercise.exerciseName)
                        .pulsarTextStyle(.cardTitle)
                        .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !isExpanded {
                        Text(exercise.setCountText)
                            .pulsarTextStyle(.captionEmphasis)
                            .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                            .lineLimit(1)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .pulsarTextStyle(.label)
                        .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                        .frame(width: 28, height: 28)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(exercise.exerciseName), \(exercise.setCountText)")
            .accessibilityHint(isExpanded ? "Collapses exercise details" : "Expands exercise details")

            if isExpanded {
                expandedContent
                    .padding(.top, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(cardBorder, lineWidth: isExpanded ? 1.2 : 1)
        }
        .shadow(color: .black.opacity(isExpanded ? 0.28 : 0.16), radius: isExpanded ? 18 : 10, y: isExpanded ? 10 : 6)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: isExpanded)
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                GymExerciseThumbnailView(
                    thumbnailURL: exercise.thumbnailURL,
                    muscleGroup: exercise.primaryMuscleGroup,
                    size: 118
                )

                CompletedWorkoutInstructionPreview(
                    exercise: exercise,
                    onShowInstructions: onShowInstructions
                )
            }

            HStack(alignment: .center, spacing: 10) {
                GymExerciseMetadataRow(
                    muscleGroup: exercise.primaryMuscleGroup,
                    equipment: exercise.equipment
                )

                Spacer(minLength: 0)

                Button(action: onShowHistory) {
                    Label("History & PR", systemImage: "chevron.right")
                        .pulsarTextStyle(.captionEmphasis)
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.055), in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open history and personal records for \(exercise.exerciseName)")
            }

            CompletedWorkoutSetTable(
                exercise: exercise,
                isEditable: isEditable,
                onEditSet: onEditSet
            )
        }
    }

    private var indexBadge: some View {
        Text("\(exercise.index)")
            .pulsarTextStyle(.label)
            .monospacedDigit()
            .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
            .frame(width: 36, height: 36)
            .background(PulsarFitnessMonochromeDesign.primaryText.opacity(0.14), in: Circle())
            .overlay {
                Circle()
                    .stroke(PulsarFitnessMonochromeDesign.primaryText.opacity(0.30), lineWidth: 1)
            }
    }

    private var cardBackground: LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(isExpanded ? 0.12 : 0.085),
                .white.opacity(isExpanded ? 0.055 : 0.038),
                PulsarFitnessMonochromeDesign.primaryText.opacity(isExpanded ? 0.055 : 0.028)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBorder: Color {
        isExpanded ? .white.opacity(0.22) : .white.opacity(0.12)
    }
}

private struct CompletedWorkoutInstructionPreview: View {
    var exercise: CompletedWorkoutExercisePresentation
    var onShowInstructions: () -> Void

    private var accent: Color {
        ExerciseProgressService.primaryMatrixGroup(for: exercise.primaryMuscleGroup)?.accent
            ?? PulsarFitnessMonochromeDesign.primaryText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let instructions = exercise.instructionsPreview {
                Text(instructions)
                    .pulsarTextStyle(.label)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if exercise.instructionsAreTruncated, exercise.instructionsFull != nil {
                    Button(action: onShowInstructions) {
                        Label("View instructions", systemImage: "text.alignleft")
                            .pulsarTextStyle(.captionEmphasis)
                            .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View full instructions for \(exercise.exerciseName)")
                }
            } else {
                Label("No form instructions saved for this exercise.", systemImage: "info.circle")
                    .pulsarTextStyle(.label)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(FitnessGlassSurfaceModifier(cornerRadius: 18, tint: accent, borderOpacity: 0.54))
    }
}

private struct CompletedWorkoutSetTable: View {
    var exercise: CompletedWorkoutExercisePresentation
    var isEditable: Bool
    var onEditSet: (CompletedWorkoutSetEditContext) -> Void

    var body: some View {
        VStack(spacing: 0) {
            tableHeader

            ForEach(exercise.sets) { set in
                CompletedWorkoutSetTableRow(
                    exerciseId: exercise.id,
                    set: set,
                    weightUnit: exercise.weightUnit,
                    isEditable: isEditable,
                    onEditSet: onEditSet
                )
            }
        }
        .background(.white.opacity(0.040), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 8) {
            tableHeaderText("Set", width: 42, alignment: .leading)
            tableHeaderText("Reps", width: 54, alignment: .center)
            tableHeaderText("Weight", alignment: .center)
            tableHeaderText("1RM Est.", width: 76, alignment: .center)
            Color.clear.frame(width: 30)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private func tableHeaderText(_ text: String, width: CGFloat? = nil, alignment: Alignment) -> some View {
        let label = Text(text)
            .pulsarTextStyle(.captionEmphasis)
            .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)

        if let width {
            label.frame(width: width, alignment: alignment)
        } else {
            label.frame(maxWidth: .infinity, alignment: alignment)
        }
    }
}

private struct CompletedWorkoutSetTableRow: View {
    var exerciseId: UUID
    var set: CompletedWorkoutSetPresentation
    var weightUnit: PulsarWeightUnit
    var isEditable: Bool
    var onEditSet: (CompletedWorkoutSetEditContext) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("\(set.setNumber)")
                .pulsarTextStyle(.label)
                .monospacedDigit()
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                .frame(width: 42, alignment: .leading)

            Text("\(set.reps)")
                .pulsarTextStyle(.label)
                .monospacedDigit()
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                .frame(width: 54, alignment: .center)

            weightCell
                .frame(maxWidth: .infinity)

            Text(oneRepMaxText)
                .pulsarTextStyle(.label)
                .monospacedDigit()
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: 76, alignment: .center)

            Image(systemName: "checkmark.circle")
                .pulsarTextStyle(.label)
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                .frame(width: 30)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var weightCell: some View {
        if isEditable {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onEditSet(
                    CompletedWorkoutSetEditContext(
                        exerciseId: exerciseId,
                        setId: set.id,
                        setNumber: set.setNumber,
                        reps: set.reps,
                        weight: set.weight,
                        weightUnit: weightUnit
                    )
                )
            } label: {
                HStack(spacing: 8) {
                    Text(weightText)
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                }
                .pulsarTextStyle(.captionEmphasis)
                .monospacedDigit()
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.white.opacity(0.095), in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit set \(set.setNumber), \(weightText)")
        } else {
            Text(weightText)
                .pulsarTextStyle(.captionEmphasis)
                .monospacedDigit()
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.white.opacity(0.060), in: Capsule(style: .continuous))
        }
    }

    private var weightText: String {
        "\(set.weight.formattedGymDecimal) \(weightUnit.displayName)"
    }

    private var oneRepMaxText: String {
        guard let estimatedOneRepMax = set.estimatedOneRepMax else { return "--" }
        return "\(estimatedOneRepMax.formattedGymDecimal) \(weightUnit.displayName)"
    }
}
