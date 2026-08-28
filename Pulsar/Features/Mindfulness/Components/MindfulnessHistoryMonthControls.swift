//
//  MindfulnessHistoryMonthControls.swift
//  Pulsar
//

import SwiftUI

struct MindfulnessHistoryMonthControls: View {
    var onPrevious: () -> Void
    var onNext: () -> Void
    var onToday: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            MindfulnessHistoryChevronButton(
                title: "Previous month",
                systemImage: "chevron.left",
                action: onPrevious
            )

            MindfulnessHistoryChevronButton(
                title: "Next month",
                systemImage: "chevron.right",
                action: onNext
            )

            Spacer(minLength: 12)

            Button("Today", systemImage: "calendar", action: onToday)
                .font(.body)
                .foregroundStyle(MindfulnessDesign.primaryText)
                .padding(.horizontal, 16)
                .frame(height: MindfulnessDesign.historyControlSize)
                .mindfulnessCardSurface(
                    cornerRadius: MindfulnessDesign.historyControlSize / 2,
                    isInteractive: true,
                    shadowOpacity: 0.018
                )
                .buttonStyle(.plain)
                .accessibilityHint("Shows the current month and selects today")
        }
    }
}
