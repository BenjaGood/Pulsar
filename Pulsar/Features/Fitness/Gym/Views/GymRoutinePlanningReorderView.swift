//
//  GymRoutinePlanningReorderView.swift
//  Pulsar
//

import SwiftUI
import UIKit

/// Keeps reorder gesture state local to the Planning list while the builder view
/// model remains the authoritative owner of the routine draft.
struct GymRoutinePlanningReorderView<RowContent: View>: View {
    typealias ReorderGesture = AnyGesture<Void>

    let exercises: [PulsarRoutineExercise]
    let supersetBlockIDs: (UUID) -> Set<UUID>
    let visibleBounds: CGRect
    let move: (UUID, Int) -> Bool
    let onDragBegan: () -> Void
    let onAutoscroll: (UUID, UnitPoint) -> Void
    @ViewBuilder let rowContent: (PulsarRoutineExercise, ReorderGesture, Bool) -> RowContent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var draggingID: UUID?
    @State private var draggingBlockIDs: Set<UUID> = []
    @State private var insertionIndex: Int?
    @State private var autoscrollTask: Task<Void, Never>?
    @State private var autoscrollDirection: GymRoutinePlanningAutoscrollDirection?

    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(exercises) { exercise in
                rowContent(exercise, reorderGesture(for: exercise), draggingBlockIDs.contains(exercise.id))
                    .id(exercise.id)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: GymRoutinePlanningRowFramesKey.self,
                                value: [exercise.id: proxy.frame(in: .named(GymRoutinePlanningCoordinateSpace.name))]
                            )
                        }
                    }
                    .scaleEffect(draggingBlockIDs.contains(exercise.id) && !reduceMotion ? 1.015 : 1)
                    .opacity(draggingBlockIDs.contains(exercise.id) && reduceMotion ? 0.94 : 1)
                    .shadow(
                        color: .black.opacity(draggingBlockIDs.contains(exercise.id) && !reduceMotion ? 0.28 : 0),
                        radius: draggingBlockIDs.contains(exercise.id) && !reduceMotion ? 16 : 0,
                        y: draggingBlockIDs.contains(exercise.id) && !reduceMotion ? 8 : 0
                    )
                    .zIndex(draggingBlockIDs.contains(exercise.id) ? 1 : 0)
            }
        }
        .onPreferenceChange(GymRoutinePlanningRowFramesKey.self) { rowFrames = $0 }
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.82), value: exercises.map(\.id))
        .onDisappear(perform: finishDrag)
    }

    private func reorderGesture(for exercise: PulsarRoutineExercise) -> ReorderGesture {
        let gesture = LongPressGesture(minimumDuration: 0.4, maximumDistance: 10)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(GymRoutinePlanningCoordinateSpace.name)))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                beginDragIfNeeded(for: exercise.id)
                if let drag {
                    updateDrag(for: exercise.id, location: drag.location)
                }
            }
            .onEnded { _ in
                finishDrag()
            }

        return AnyGesture(gesture.map { _ in () })
    }

    private func beginDragIfNeeded(for exerciseID: UUID) {
        guard draggingID == nil else { return }
        draggingID = exerciseID
        draggingBlockIDs = supersetBlockIDs(exerciseID)
        insertionIndex = nil
        onDragBegan()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func updateDrag(for exerciseID: UUID, location: CGPoint) {
        let destination = destinationIndex(for: location)
        if insertionIndex != destination {
            insertionIndex = destination
            if move(exerciseID, destination) {
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
        updateAutoscroll(for: location)
    }

    private func destinationIndex(for location: CGPoint) -> Int {
        let orderedFrames = exercises.enumerated().compactMap { index, exercise -> (Int, CGRect)? in
            guard let frame = rowFrames[exercise.id] else { return nil }
            return (index, frame)
        }

        for (index, frame) in orderedFrames where location.y < frame.midY {
            return index
        }
        return exercises.count
    }

    private func updateAutoscroll(for location: CGPoint) {
        let direction: GymRoutinePlanningAutoscrollDirection?
        let edgeInset: CGFloat = 64
        if location.y < visibleBounds.minY + edgeInset {
            direction = .up
        } else if location.y > visibleBounds.maxY - edgeInset {
            direction = .down
        } else {
            direction = nil
        }

        guard let direction else {
            stopAutoscroll()
            return
        }
        guard autoscrollDirection != direction else { return }
        stopAutoscroll()
        autoscrollDirection = direction

        autoscrollTask = Task { @MainActor in
            while !Task.isCancelled {
                scrollOneRow(direction: direction)
                try? await Task.sleep(nanoseconds: 180_000_000)
            }
        }
    }

    private func scrollOneRow(direction: GymRoutinePlanningAutoscrollDirection) {
        let orderedRows = exercises.compactMap { exercise -> (PulsarRoutineExercise, CGRect)? in
            guard let frame = rowFrames[exercise.id] else { return nil }
            return (exercise, frame)
        }
        guard !orderedRows.isEmpty else { return }

        switch direction {
        case .up:
            let firstVisibleIndex = orderedRows.firstIndex { $0.1.maxY >= visibleBounds.minY } ?? 0
            guard firstVisibleIndex > 0 else { return }
            onAutoscroll(orderedRows[firstVisibleIndex - 1].0.id, .top)
        case .down:
            let lastVisibleIndex = orderedRows.lastIndex { $0.1.minY <= visibleBounds.maxY } ?? orderedRows.count - 1
            guard lastVisibleIndex < orderedRows.count - 1 else { return }
            onAutoscroll(orderedRows[lastVisibleIndex + 1].0.id, .bottom)
        }
    }

    private func finishDrag() {
        stopAutoscroll()
        draggingID = nil
        draggingBlockIDs = []
        insertionIndex = nil
    }

    private func stopAutoscroll() {
        autoscrollTask?.cancel()
        autoscrollTask = nil
        autoscrollDirection = nil
    }
}

enum GymRoutinePlanningCoordinateSpace {
    static let name = "gym-routine-planning-reorder"
}

private enum GymRoutinePlanningAutoscrollDirection {
    case up
    case down
}

private struct GymRoutinePlanningRowFramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newest in newest })
    }
}
