//
//  MindfulnessActiveQuestionCard.swift
//  Pulsar
//

import SwiftUI

struct MindfulnessActiveQuestionCard: View {
    var question: MindfulnessQuestion
    var stepIndex: Int
    var totalSteps: Int
    @Binding var rating: Double
    var isFinalStep: Bool
    var isUpdating: Bool
    var showsSaveError: Bool
    var onAdvance: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                MindfulnessSegmentedProgress(currentStep: stepIndex, totalSteps: totalSteps)

                Text("\(stepIndex + 1) of \(totalSteps)")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(MindfulnessDesign.secondaryText)
                    .fixedSize()
            }

            questionIdentity

            VStack(spacing: 10) {
                HStack {
                    Text("Very Low")
                    Spacer()
                    Text("Very High")
                }
                .font(.footnote)
                .foregroundStyle(MindfulnessDesign.secondaryText)

                Slider(value: $rating, in: 1...5, step: 1) {
                    Text(question.title)
                }
                .tint(MindfulnessDesign.active)
                .accessibilityValue("\(Int(rating.rounded())) out of 5")

                HStack(spacing: 0) {
                    ForEach(1...5, id: \.self) { value in
                        Text("\(value)")
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(
                                value == Int(rating.rounded())
                                    ? MindfulnessDesign.primaryText
                                    : MindfulnessDesign.secondaryText
                            )
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            if showsSaveError {
                Label("Your mood could not be saved. Please try again.", systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(MindfulnessDesign.secondaryText)
            }

            HStack {
                Spacer()

                Button(action: onAdvance) {
                    Text(actionTitle)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 26)
                        .frame(minWidth: 126, minHeight: 48)
                        .background(MindfulnessDesign.active, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint(isFinalStep ? "Saves today's complete mood check-in" : "Moves to the next question")
            }
        }
        .padding(MindfulnessDesign.cardPadding)
        .mindfulnessCardSurface()
    }

    private var questionIdentity: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))

        return layout {
            Image(systemName: question.symbolName)
                .font(.title2.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(MindfulnessDesign.primaryText)
                .frame(width: 58, height: 58)
                .background {
                    Color.clear
                        .mindfulnessCardSurface(cornerRadius: 29, shadowOpacity: 0.03)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(question.title)
                    .pulsarTextStyle(.displayMedium)
                    .foregroundStyle(MindfulnessDesign.primaryText)
                    .accessibilityAddTraits(.isHeader)

                Text(question.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(MindfulnessDesign.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actionTitle: String {
        guard isFinalStep else { return "Next" }
        return isUpdating ? "Update Mood" : "Log Mood"
    }
}
