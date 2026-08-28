//
//  MindfulnessHistoryMoodPill.swift
//  Pulsar
//

import SwiftUI

struct MindfulnessHistoryMoodPill: View {
    var emotion: MindfulnessEmotion

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .strokeBorder(MindfulnessDesign.primaryText, lineWidth: 1.2)

                MindfulnessEmotionFace(emotion: emotion)
                    .frame(width: 19, height: 19)
            }
            .frame(width: 27, height: 27)
            .accessibilityHidden(true)

            Text(emotion.title)
                .font(.body)
                .foregroundStyle(MindfulnessDesign.primaryText)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .mindfulnessCardSurface(cornerRadius: 18, shadowOpacity: 0.015)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Overall mood, \(emotion.title)")
    }
}
