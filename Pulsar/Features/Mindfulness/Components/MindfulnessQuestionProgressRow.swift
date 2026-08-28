//
//  MindfulnessQuestionProgressRow.swift
//  Pulsar
//

import SwiftUI

struct MindfulnessQuestionProgressRow: View {
    var question: MindfulnessQuestion
    var stepNumber: Int

    var body: some View {
        HStack(spacing: 12) {
            Text("\(stepNumber)")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(MindfulnessDesign.secondaryText)
                .frame(width: 42, height: 42)
                .background(Color.white.opacity(0.76), in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(MindfulnessDesign.separator, lineWidth: 0.7)
                }
                .zIndex(1)

            Label(question.title, systemImage: question.symbolName)
                .font(.body)
                .foregroundStyle(MindfulnessDesign.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                .padding(.horizontal, 16)
                .mindfulnessCardSurface(
                    cornerRadius: 23,
                    shadowOpacity: 0.025
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(stepNumber), \(question.title)")
    }
}
