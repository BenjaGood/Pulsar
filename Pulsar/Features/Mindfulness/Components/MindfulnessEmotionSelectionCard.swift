//
//  MindfulnessEmotionSelectionCard.swift
//  Pulsar
//

import SwiftUI

struct MindfulnessEmotionSelectionCard: View {
    @Binding var draft: PulsarDailyJournalDraft
    var onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var feedbackSequence = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("How are you feeling?")
                    .pulsarTextStyle(.displayMedium)
                    .foregroundStyle(MindfulnessDesign.primaryText)
                    .accessibilityAddTraits(.isHeader)

                Text("Select your current emotion")
                    .font(.subheadline)
                    .foregroundStyle(MindfulnessDesign.secondaryText)
            }

            emotionOptions

            Label {
                Text("Logging how you feel helps you build self-awareness and track your progress.")
                    .font(.subheadline)
                    .foregroundStyle(MindfulnessDesign.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "sparkles")
                    .font(.body)
                    .foregroundStyle(MindfulnessDesign.secondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.36), in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(MindfulnessDesign.separator, lineWidth: 0.7)
            }

            Button("Continue", action: onContinue)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(MindfulnessDesign.active, in: Capsule())
                .contentShape(Capsule())
                .buttonStyle(MindfulnessContinueButtonStyle())
                .accessibilityHint("Begins the six-question mood check-in")
        }
        .padding(MindfulnessDesign.cardPadding)
        .mindfulnessCardSurface()
        .sensoryFeedback(.selection, trigger: feedbackSequence)
    }

    @ViewBuilder
    private var emotionOptions: some View {
        if dynamicTypeSize.isAccessibilitySize {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(minimum: 72), spacing: 10), count: 3),
                spacing: 12
            ) {
                options
            }
        } else {
            HStack(alignment: .top, spacing: 4) {
                options
            }
        }
    }

    @ViewBuilder
    private var options: some View {
        ForEach(MindfulnessEmotion.allCases) { emotion in
            MindfulnessEmotionOptionButton(
                emotion: emotion,
                isSelected: selectedEmotion == emotion,
                action: { select(emotion) }
            )
        }
    }

    private var selectedEmotion: MindfulnessEmotion {
        MindfulnessEmotion.selected(in: draft)
    }

    private func select(_ emotion: MindfulnessEmotion) {
        guard selectedEmotion != emotion else { return }
        withAnimation(reduceMotion ? .linear(duration: 0.01) : .smooth(duration: 0.22)) {
            emotion.apply(to: &draft)
        }
        feedbackSequence += 1
    }
}
