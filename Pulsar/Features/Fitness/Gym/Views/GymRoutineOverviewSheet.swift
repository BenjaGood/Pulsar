//
//  GymRoutineOverviewSheet.swift
//  Pulsar
//

import SwiftUI

struct GymRoutineOverviewSheet: View {
    @ObservedObject var syncStore: PulsarWatchConnectivitySyncStore
    let expectedSessionID: UUID
    let fallbackState: ActiveGymWorkoutState

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let state {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(orderedExercises) { exercise in
                                GymRoutineOverviewRow(
                                    exercise: exercise,
                                    isCurrent: exercise.id == state.currentExercise?.id
                                )
                            }
                        }
                        .padding(18)
                    }
                    .scrollIndicators(.hidden)
                    .background(Color.white)
                } else {
                    ContentUnavailableView(
                        "Routine Unavailable",
                        systemImage: "list.bullet.clipboard",
                        description: Text("The active routine is still syncing from Apple Watch.")
                    )
                }
            }
            .navigationTitle(state?.routineName ?? "Workout Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.light)
    }

    private var state: ActiveGymWorkoutState? {
        if let state = syncStore.activeGymState,
           state.sessionId == expectedSessionID,
           !state.exercises.isEmpty {
            return state
        }
        guard fallbackState.sessionId == expectedSessionID,
              !fallbackState.exercises.isEmpty else { return nil }
        return fallbackState
    }

    private var orderedExercises: [ActiveGymWorkoutExerciseState] {
        state?.exercises.sorted(using: KeyPathComparator(\.orderIndex)) ?? []
    }
}

private struct GymRoutineOverviewRow: View {
    let exercise: ActiveGymWorkoutExerciseState
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 14) {
            GymExerciseThumbnailView(
                thumbnailURL: exercise.thumbnailURL,
                muscleGroup: .liveWorkoutValue(for: exercise.muscleGroup),
                size: 64,
                isCompleted: exercise.isCompleted
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(exercise.exerciseName)
                    .font(.headline)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                    .lineLimit(2)

                Text("\(exercise.muscleGroup) / \(exercise.equipment)")
                    .font(.subheadline)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                    .lineLimit(1)

                Text(planSummary)
                    .font(.subheadline)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Label(statusText, systemImage: statusSymbol)
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(statusColor)
                .accessibilityLabel(statusText)
        }
        .padding(14)
        .background(rowBackground, in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(isCurrent ? Color.black.opacity(0.18) : PulsarFitnessMonochromeDesign.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var planSummary: String {
        var parts = ["\(exercise.sets.count) sets", "\(exercise.plannedReps) reps"]
        if exercise.plannedWeight > 0 {
            parts.append(PulsarGymFormatters.weight(exercise.plannedWeight, unit: exercise.weightUnit))
        }
        return parts.joined(separator: " • ")
    }

    private var statusText: String {
        if exercise.isCompleted { return "Completed" }
        if isCurrent { return "Current exercise" }
        return "Upcoming"
    }

    private var statusSymbol: String {
        if exercise.isCompleted { return "checkmark.circle.fill" }
        if isCurrent { return "circle.inset.filled" }
        return "circle"
    }

    private var statusColor: Color {
        exercise.isCompleted || isCurrent
            ? PulsarFitnessMonochromeDesign.primaryText
            : PulsarFitnessMonochromeDesign.tertiaryText
    }

    private var rowBackground: Color {
        isCurrent ? Color.black.opacity(0.035) : Color.white
    }
}
