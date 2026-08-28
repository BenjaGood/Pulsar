import SwiftUI
import UIKit

struct GymSavedRoutinesView: View {
    @ObservedObject var routineStore: PulsarRoutineStore
    @ObservedObject var historyStore: PulsarGymWorkoutHistoryStore
    var onBack: () -> Void
    var onCreateRoutine: () -> Void
    var onStartRoutine: (PulsarRoutine) -> Void
    var onEditRoutine: (PulsarRoutine) -> Void

    @State private var routinePendingDeletion: PulsarRoutine?
    @State private var isDeleteDialogPresented = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.white
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    GymSavedRoutinesHeader(
                        onBack: onBack,
                        onCreateRoutine: onCreateRoutine
                    )

                    if routineStore.routines.isEmpty {
                        GymSavedRoutinesEmptyState(onCreateRoutine: onCreateRoutine)
                            .frame(maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 14) {
                                ForEach(routineStore.routines) { routine in
                                    GymSavedRoutineCard(
                                        routine: routine,
                                        lastPerformed: lastPerformedDate(for: routine),
                                        onStart: {
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            onStartRoutine(routine)
                                        },
                                        onEdit: {
                                            onEditRoutine(routine)
                                        },
                                        onDuplicate: {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            _ = routineStore.duplicate(routine)
                                        },
                                        onDelete: {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            routinePendingDeletion = routine
                                            isDeleteDialogPresented = true
                                        }
                                    )
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        .scrollBounceBehavior(.basedOnSize)
                        .contentMargins(
                            .bottom,
                            geometry.safeAreaInsets.bottom + 16,
                            for: .scrollContent
                        )
                        .ignoresSafeArea(.container, edges: .bottom)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .confirmationDialog(
            "Delete routine?",
            isPresented: $isDeleteDialogPresented,
            titleVisibility: .visible,
            presenting: routinePendingDeletion
        ) { routine in
            Button("Delete Routine", role: .destructive) {
                routineStore.delete(routine)
                routinePendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                routinePendingDeletion = nil
            }
        } message: { _ in
            Text("This only removes the saved routine. Completed workout history stays intact.")
        }
    }

    private func lastPerformedDate(for routine: PulsarRoutine) -> Date? {
        historyStore.sessions
            .filter { $0.routineId == routine.id && $0.finishedAt != nil }
            .map(\.startedAt)
            .max()
    }
}

private struct GymSavedRoutinesEmptyState: View {
    var onCreateRoutine: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No saved routines yet", systemImage: "figure.strengthtraining.traditional")
        } description: {
            Text("Create your first routine and Pulsar will keep the plan here for faster gym starts.")
        } actions: {
            Button("Create your first routine", systemImage: "plus", action: onCreateRoutine)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(PulsarFitnessMonochromeDesign.primaryText)
        }
        .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
    }
}

private struct GymSavedRoutinesPreview: View {
    var startsAtBottom = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.white
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    GymSavedRoutinesHeader(
                        onBack: {},
                        onCreateRoutine: {}
                    )

                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(PulsarRoutine.savedRoutinesPreview) { routine in
                                GymSavedRoutineCard(
                                    routine: routine,
                                    lastPerformed: routine.updatedAt,
                                    onStart: {},
                                    onEdit: {},
                                    onDuplicate: {},
                                    onDelete: {}
                                )
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                    .contentMargins(
                        .bottom,
                        geometry.safeAreaInsets.bottom + 16,
                        for: .scrollContent
                    )
                    .ignoresSafeArea(.container, edges: .bottom)
                    .defaultScrollAnchor(startsAtBottom ? .bottom : .top)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
        }
        .pulsarFitnessMonochromeAppearance()
    }
}

private extension PulsarRoutine {
    static var savedRoutinesPreview: [PulsarRoutine] {
        [
            previewRoutine(
                name: "Friday",
                emoji: "🦵",
                groups: [.glutes, .quadriceps, .calves],
                daysAgo: 1
            ),
            previewRoutine(
                name: "Thursday",
                emoji: "💪",
                groups: [.lats, .upperMiddleBack, .biceps],
                daysAgo: 2
            ),
            previewRoutine(
                name: "Wednesday",
                emoji: "🍑",
                groups: [.glutes, .hamstrings, .calves],
                daysAgo: 50
            ),
            previewRoutine(
                name: "Tuesday",
                emoji: "💪",
                groups: [.chest, .shoulders, .triceps],
                daysAgo: 48
            )
        ]
    }

    static func previewRoutine(
        name: String,
        emoji: String,
        groups: [PulsarMuscleGroup],
        daysAgo: Int
    ) -> PulsarRoutine {
        let exercises = (0..<6).map { index in
            let group = groups[index % groups.count]
            let exercise = PulsarExercise.custom(
                id: "preview-\(name)-\(index)",
                name: "Preview Exercise \(index + 1)",
                primaryMuscleGroup: group,
                thumbnailURL: nil
            )
            return PulsarRoutineExercise(
                exercise: exercise,
                order: index,
                plannedSets: 3,
                plannedReps: 10,
                plannedRestSeconds: 105
            )
        }
        let performedAt = Date.now.addingTimeInterval(TimeInterval(-daysAgo * 86_400))
        return PulsarRoutine(
            name: name,
            emoji: emoji,
            createdAt: performedAt,
            updatedAt: performedAt,
            exercises: exercises
        )
    }
}

#Preview("My Routines - Standard", traits: .fixedLayout(width: 393, height: 852)) {
    GymSavedRoutinesPreview()
}

#Preview("My Routines - Pro Max", traits: .fixedLayout(width: 430, height: 932)) {
    GymSavedRoutinesPreview()
}

#Preview("My Routines - Small", traits: .fixedLayout(width: 375, height: 667)) {
    GymSavedRoutinesPreview()
}

#Preview("My Routines - Accessibility", traits: .fixedLayout(width: 393, height: 852)) {
    GymSavedRoutinesPreview()
        .environment(\.dynamicTypeSize, .accessibility2)
}

#Preview("My Routines - Active Device") {
    GymSavedRoutinesPreview()
}

#Preview("My Routines - Bottom Safe Area") {
    GymSavedRoutinesPreview(startsAtBottom: true)
}
