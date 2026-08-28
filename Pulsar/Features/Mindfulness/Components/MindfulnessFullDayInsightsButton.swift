//
//  MindfulnessFullDayInsightsButton.swift
//  Pulsar
//

import SwiftUI

struct MindfulnessFullDayInsightsButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.body)
                    .accessibilityHidden(true)

                Text("View full day insights")
                    .font(.body)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(MindfulnessDesign.primaryText)
            .padding(.horizontal, MindfulnessDesign.historyCardPadding)
            .frame(maxWidth: .infinity, minHeight: 54)
            .contentShape(.rect)
        }
        .mindfulnessCardSurface(
            cornerRadius: 27,
            isInteractive: true,
            shadowOpacity: 0.025
        )
        .buttonStyle(.plain)
        .accessibilityHint("Opens all saved insights for the selected day")
    }
}
