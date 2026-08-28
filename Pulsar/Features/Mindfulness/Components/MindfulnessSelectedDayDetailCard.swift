//
//  MindfulnessSelectedDayDetailCard.swift
//  Pulsar
//

import SwiftUI

struct MindfulnessSelectedDayDetailCard: View {
    var entry: PulsarDailyJournalEntry

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.date, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.headline)
                    .foregroundStyle(MindfulnessDesign.primaryText)
                    .accessibilityAddTraits(.isHeader)

                Text("Logged at \(entry.createdAt.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(MindfulnessDesign.tertiaryText)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Overall Mood")
                    .font(.subheadline)
                    .foregroundStyle(MindfulnessDesign.primaryText)

                MindfulnessHistoryMoodPill(
                    emotion: MindfulnessEmotion.selected(in: entry)
                )
            }

            Divider()
                .overlay(MindfulnessDesign.separator)

            LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 10) {
                ForEach(MindfulnessQuestion.allCases) { question in
                    MindfulnessHistoryMetricRow(
                        question: question,
                        rating: question.rating(in: entry)
                    )
                }
            }
        }
        .padding(MindfulnessDesign.historyCardPadding)
        .mindfulnessCardSurface(
            cornerRadius: MindfulnessDesign.historyCardCornerRadius,
            shadowOpacity: 0.035
        )
        .accessibilityElement(children: .contain)
    }

    private var metricColumns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(
            repeating: GridItem(.flexible(minimum: 130), spacing: 22, alignment: .top),
            count: count
        )
    }
}

#Preview("Selected Mood History Day") {
    ScrollView {
        MindfulnessSelectedDayDetailCard(
            entry: MindfulnessHistoryPreviewData.entries[0]
        )
        .padding(22)
    }
    .background(PulsarFitnessMonochromeBackground())
    .pulsarFitnessMonochromeAppearance()
}
