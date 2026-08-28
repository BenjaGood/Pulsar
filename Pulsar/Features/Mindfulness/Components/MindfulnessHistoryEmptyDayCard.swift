//
//  MindfulnessHistoryEmptyDayCard.swift
//  Pulsar
//

import SwiftUI

struct MindfulnessHistoryEmptyDayCard: View {
    var date: Date

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "calendar")
                .font(.title2.weight(.medium))
                .foregroundStyle(MindfulnessDesign.primaryText)
                .frame(width: 46, height: 46)
                .background(.black.opacity(0.035), in: .circle)

            VStack(alignment: .leading, spacing: 5) {
                Text("No mood logged")
                    .font(.headline)
                    .foregroundStyle(MindfulnessDesign.primaryText)

                Text("No entry was recorded for \(date.formatted(date: .long, time: .omitted)).")
                    .font(.subheadline)
                    .foregroundStyle(MindfulnessDesign.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MindfulnessDesign.historyCardPadding)
        .mindfulnessCardSurface(
            cornerRadius: MindfulnessDesign.historyCardCornerRadius,
            shadowOpacity: 0.035
        )
        .accessibilityElement(children: .combine)
    }
}

#Preview("Empty Mood History Day") {
    MindfulnessHistoryEmptyDayCard(
        date: MindfulnessHistoryPreviewData.august2026
    )
    .padding(22)
    .background(PulsarFitnessMonochromeBackground())
    .pulsarFitnessMonochromeAppearance()
}
