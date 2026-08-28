//
//  SlideToFinishWorkoutControl.swift
//  Pulsar
//

import SwiftUI

struct SlideToFinishWorkoutControl: View {
    static let completionThreshold: CGFloat = 0.88

    let isFinishing: Bool
    let onFinish: () -> Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var controlWidth: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var didSubmit = false
    @State private var didTriggerThresholdFeedback = false
    @State private var feedbackTrigger = 0

    private let trackHeight: CGFloat = 72
    private let knobSize: CGFloat = 60
    private let trackInset: CGFloat = 6

    var body: some View {
        ZStack(alignment: layoutDirection == .rightToLeft ? .trailing : .leading) {
            Capsule()
                .fill(Color.white.opacity(0.78))
                .overlay {
                    Capsule()
                        .stroke(PulsarFitnessMonochromeDesign.hairline, lineWidth: 1)
                }
                .pulsarLiquidGlass(cornerRadius: trackHeight / 2, isClear: true)

            Text(isFinishing ? "Finishing workout…" : "Slide to finish workout")
                .font(.headline)
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                .opacity(max(0.22, 1 - progress * 0.72))
                .padding(.horizontal, knobSize + 22)
                .frame(maxWidth: .infinity)

            knob
                .padding(trackInset)
                .offset(x: signedKnobOffset)
        }
        .frame(height: trackHeight)
        .transaction { transaction in
            if isDragging {
                transaction.animation = nil
            }
        }
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.width
        } action: { _, width in
            controlWidth = width
        }
        .sensoryFeedback(.success, trigger: feedbackTrigger)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Finish workout")
        .accessibilityValue(isFinishing ? "Finishing" : "Slide to confirm")
        .accessibilityHint("Ends the active workout on iPhone and Apple Watch.")
        .accessibilityAction(named: "Finish workout", performAccessibleFinish)
    }

    private var knob: some View {
        ZStack {
            Circle()
                .fill(Color.black)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)

            if isFinishing {
                ProgressView()
                    .tint(.white)
            } else {
                Image(systemName: layoutDirection == .rightToLeft ? "arrow.left" : "arrow.right")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
        }
        .frame(width: knobSize, height: knobSize)
        .contentShape(.circle)
        .gesture(dragGesture, isEnabled: !isFinishing && !didSubmit)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged(handleDragChanged)
            .onEnded(handleDragEnded)
    }

    private var maximumTravel: CGFloat {
        max(0, controlWidth - knobSize - trackInset * 2)
    }

    private var progress: CGFloat {
        Self.normalizedProgress(translation: displayedDragOffset, maximumTravel: maximumTravel)
    }

    private var displayedDragOffset: CGFloat {
        isFinishing || didSubmit ? maximumTravel : dragOffset
    }

    private var signedKnobOffset: CGFloat {
        let offset = displayedDragOffset
        return layoutDirection == .rightToLeft ? -offset : offset
    }

    static func normalizedProgress(translation: CGFloat, maximumTravel: CGFloat) -> CGFloat {
        guard maximumTravel > 0 else { return 0 }
        return clampedTranslation(translation, maximumTravel: maximumTravel) / maximumTravel
    }

    static func clampedTranslation(_ translation: CGFloat, maximumTravel: CGFloat) -> CGFloat {
        min(max(translation, 0), max(0, maximumTravel))
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        guard !isFinishing, !didSubmit else { return }
        if !isDragging {
            isDragging = true
        }
        let directionalTranslation = value.translation.width * (layoutDirection == .rightToLeft ? -1 : 1)
        dragOffset = Self.clampedTranslation(directionalTranslation, maximumTravel: maximumTravel)

        let currentProgress = Self.normalizedProgress(
            translation: directionalTranslation,
            maximumTravel: maximumTravel
        )
        if currentProgress >= Self.completionThreshold, !didTriggerThresholdFeedback {
            didTriggerThresholdFeedback = true
            feedbackTrigger += 1
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        guard !isFinishing, !didSubmit else { return }
        isDragging = false
        let directionalTranslation = value.translation.width * (layoutDirection == .rightToLeft ? -1 : 1)
        let finalProgress = Self.normalizedProgress(
            translation: directionalTranslation,
            maximumTravel: maximumTravel
        )
        dragOffset = Self.clampedTranslation(directionalTranslation, maximumTravel: maximumTravel)

        if finalProgress >= Self.completionThreshold {
            submitFinish()
        } else {
            resetKnob()
        }
    }

    private func performAccessibleFinish() {
        guard !isFinishing, !didSubmit else { return }
        dragOffset = maximumTravel
        didTriggerThresholdFeedback = true
        feedbackTrigger += 1
        submitFinish()
    }

    private func submitFinish() {
        guard !isFinishing, !didSubmit else { return }
        didSubmit = true
        dragOffset = maximumTravel
        if onFinish() {
            return
        } else {
            didSubmit = false
            resetKnob()
        }
    }

    private func resetKnob() {
        didTriggerThresholdFeedback = false
        if reduceMotion {
            dragOffset = 0
        } else {
            withAnimation(.snappy(duration: 0.18)) {
                dragOffset = 0
            }
        }
    }
}
