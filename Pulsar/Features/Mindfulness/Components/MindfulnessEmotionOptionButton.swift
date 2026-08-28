//
//  MindfulnessEmotionOptionButton.swift
//  Pulsar
//

import SwiftUI

struct MindfulnessEmotionOptionButton: View {
    var emotion: MindfulnessEmotion
    var isSelected: Bool
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(isSelected ? 0.90 : 0.48))

                    Circle()
                        .strokeBorder(
                            isSelected ? MindfulnessDesign.primaryText : MindfulnessDesign.separator,
                            lineWidth: isSelected ? 1.4 : 0.7
                        )

                    MindfulnessEmotionFace(emotion: emotion)
                        .frame(width: 28, height: 28)
                        .opacity(isSelected ? 1 : 0.68)
                }
                .frame(width: 52, height: 52)
                .shadow(color: .black.opacity(isSelected ? 0.08 : 0.025), radius: 7, y: 3)
                .scaleEffect(isSelected && !reduceMotion ? 1.04 : 1)

                Text(emotion.title)
                    .font(.caption)
                    .foregroundStyle(isSelected ? MindfulnessDesign.primaryText : MindfulnessDesign.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(emotion.title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
