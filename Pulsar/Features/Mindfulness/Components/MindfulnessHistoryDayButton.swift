//
//  MindfulnessHistoryDayButton.swift
//  Pulsar
//

import SwiftUI

struct MindfulnessHistoryDayButton: View {
    var date: Date
    var isInDisplayedMonth: Bool
    var isSelected: Bool
    var entry: PulsarDailyJournalEntry?
    var action: () -> Void

    @ScaledMetric(relativeTo: .callout) private var selectionSize = 40.0

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(date, format: .dateTime.day())
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(dayTextColor)
                    .frame(
                        width: min(selectionSize, 44),
                        height: min(selectionSize, 44)
                    )
                    .overlay {
                        Circle()
                            .strokeBorder(
                                MindfulnessDesign.primaryText.opacity(isSelected ? 0.52 : 0),
                                lineWidth: 1.2
                            )
                    }

                Circle()
                    .fill(dotColor)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var dayTextColor: Color {
        isInDisplayedMonth
            ? MindfulnessDesign.primaryText
            : MindfulnessDesign.tertiaryText.opacity(0.55)
    }

    private var dotColor: Color {
        guard isInDisplayedMonth, let entry else { return .clear }
        if isSelected { return MindfulnessDesign.primaryText }
        let intensity = 0.24 + min(abs(entry.valence), 1) * 0.34
        return MindfulnessDesign.primaryText.opacity(intensity)
    }

    private var accessibilityValue: String {
        guard let entry else { return "No mood logged" }
        let score = (entry.wellnessAverage * 5)
            .formatted(.number.precision(.fractionLength(1)))
        return "Mood logged, wellness average \(score) out of 5"
    }
}
