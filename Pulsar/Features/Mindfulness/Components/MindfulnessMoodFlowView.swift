//
//  MindfulnessMoodFlowView.swift
//  Pulsar
//

import SwiftUI

struct MindfulnessMoodFlowView: View {
    @Binding var draft: PulsarDailyJournalDraft
    var loggedEntry: PulsarDailyJournalEntry?
    var onLog: () -> Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isQuestionnaireActive = false
    @State private var activeQuestionIndex = 0
    @State private var activeRating = 3.0
    @State private var showsSaveError = false

    private let questions = MindfulnessQuestion.allCases

    var body: some View {
        PulsarGlassEffectGroup(spacing: PulsarTabLayout.sectionSpacing) {
            VStack(spacing: PulsarTabLayout.sectionSpacing) {
                MindfulnessEmotionSelectionCard(
                    draft: $draft,
                    onContinue: beginQuestionnaire
                )

                if isQuestionnaireActive {
                    MindfulnessQuestionnaireView(
                        question: activeQuestion,
                        stepIndex: activeQuestionIndex,
                        totalSteps: questions.count,
                        remainingQuestions: questions.suffix(from: activeQuestionIndex + 1),
                        rating: $activeRating,
                        isUpdating: loggedEntry != nil,
                        showsSaveError: showsSaveError,
                        onAdvance: advance
                    )
                }
            }
        }
    }

    private var activeQuestion: MindfulnessQuestion {
        questions[activeQuestionIndex]
    }

    private func beginQuestionnaire() {
        guard !isQuestionnaireActive else { return }

        activeQuestionIndex = 0
        activeRating = questions[0].rating(in: draft)
        showsSaveError = false
        withAnimation(flowAnimation) {
            isQuestionnaireActive = true
        }
    }

    private func advance() {
        activeQuestion.store(rating: activeRating, in: &draft)
        showsSaveError = false

        guard activeQuestionIndex == questions.count - 1 else {
            let nextIndex = activeQuestionIndex + 1
            withAnimation(flowAnimation) {
                activeQuestionIndex = nextIndex
                activeRating = questions[nextIndex].rating(in: draft)
            }
            return
        }

        guard onLog() else {
            showsSaveError = true
            return
        }

        withAnimation(flowAnimation) {
            isQuestionnaireActive = false
            activeQuestionIndex = 0
        }
    }

    private var flowAnimation: Animation {
        reduceMotion
            ? .linear(duration: 0.01)
            : .easeInOut(duration: 0.28)
    }
}
