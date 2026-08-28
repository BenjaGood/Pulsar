//
//  MindfulnessQuestionnaireView.swift
//  Pulsar
//

import SwiftUI

struct MindfulnessQuestionnaireView: View {
    var question: MindfulnessQuestion
    var stepIndex: Int
    var totalSteps: Int
    var remainingQuestions: ArraySlice<MindfulnessQuestion>
    @Binding var rating: Double
    var isUpdating: Bool
    var showsSaveError: Bool
    var onAdvance: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            MindfulnessActiveQuestionCard(
                question: question,
                stepIndex: stepIndex,
                totalSteps: totalSteps,
                rating: $rating,
                isFinalStep: stepIndex == totalSteps - 1,
                isUpdating: isUpdating,
                showsSaveError: showsSaveError,
                onAdvance: onAdvance
            )
            .id(question.id)
            .mindfulnessStaticGlassTransition()
            .transition(.opacity.combined(with: .offset(y: 8)))

            if !remainingQuestions.isEmpty {
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(MindfulnessDesign.separator)
                        .frame(width: 1)
                        .padding(.vertical, 20)
                        .padding(.leading, 20.5)

                    VStack(spacing: 10) {
                        ForEach(remainingQuestions.enumerated(), id: \.element.id) { offset, question in
                            MindfulnessQuestionProgressRow(
                                question: question,
                                stepNumber: stepIndex + offset + 2
                            )
                            .mindfulnessStaticGlassTransition()
                        }
                    }
                }
            }
        }
    }
}

#Preview("Guided Mindfulness Question") {
    @Previewable @State var rating = 3.0

    ScrollView {
        MindfulnessQuestionnaireView(
            question: .energy,
            stepIndex: 0,
            totalSteps: MindfulnessQuestion.allCases.count,
            remainingQuestions: MindfulnessQuestion.allCases.dropFirst(),
            rating: $rating,
            isUpdating: false,
            showsSaveError: false,
            onAdvance: {}
        )
        .padding(22)
    }
    .background(PulsarFitnessMonochromeBackground())
    .pulsarFitnessMonochromeAppearance()
}
