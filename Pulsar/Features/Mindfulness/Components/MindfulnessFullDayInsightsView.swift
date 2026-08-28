//
//  MindfulnessFullDayInsightsView.swift
//  Pulsar
//

import SwiftUI

struct MindfulnessFullDayInsightsView: View {
    var entry: PulsarDailyJournalEntry

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            PulsarFitnessMonochromeBackground()

            ScrollView {
                PulsarGlassEffectGroup(spacing: 8) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Day Insights")
                                    .pulsarTextStyle(.displayLarge)
                                    .foregroundStyle(MindfulnessDesign.primaryText)
                                    .accessibilityAddTraits(.isHeader)

                                Text(entry.date, format: .dateTime.weekday(.wide).month(.wide).day())
                                    .font(.subheadline)
                                    .foregroundStyle(MindfulnessDesign.secondaryText)
                            }

                            Spacer(minLength: 8)

                            Button("Close", systemImage: "xmark", action: dismiss.callAsFunction)
                                .labelStyle(.iconOnly)
                                .font(.title3)
                                .foregroundStyle(MindfulnessDesign.primaryText)
                                .frame(
                                    width: MindfulnessDesign.historyControlSize,
                                    height: MindfulnessDesign.historyControlSize
                                )
                                .mindfulnessCardSurface(
                                    cornerRadius: MindfulnessDesign.historyControlSize / 2,
                                    isInteractive: true,
                                    shadowOpacity: 0.025
                                )
                                .buttonStyle(.plain)
                        }

                        MindfulnessSelectedDayDetailCard(entry: entry)

                        VStack(alignment: .leading, spacing: 14) {
                            Text("Saved context")
                                .pulsarTextStyle(.sectionHeader)
                                .foregroundStyle(MindfulnessDesign.primaryText)

                            LabeledContent("Sleep perception") {
                                Text("\(sleepRating)/5")
                                    .monospacedDigit()
                            }

                            Divider()
                                .overlay(MindfulnessDesign.separator)

                            LabeledContent("Emotions") {
                                Text(emotionText)
                                    .multilineTextAlignment(.trailing)
                            }

                            LabeledContent("Associations") {
                                Text(associationText)
                                    .multilineTextAlignment(.trailing)
                            }

                            if let note = entry.note, !note.isEmpty {
                                Divider()
                                    .overlay(MindfulnessDesign.separator)

                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Reflection")
                                        .font(.subheadline)
                                        .foregroundStyle(MindfulnessDesign.secondaryText)

                                    Text(note)
                                        .font(.body)
                                        .foregroundStyle(MindfulnessDesign.primaryText)
                                }
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(MindfulnessDesign.primaryText)
                        .padding(MindfulnessDesign.historyCardPadding)
                        .mindfulnessCardSurface(
                            cornerRadius: MindfulnessDesign.historyCardCornerRadius,
                            shadowOpacity: 0.035
                        )
                    }
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 22)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                }
            }
            .scrollContentBackground(.visible)
        }
        .pulsarFitnessMonochromeAppearance()
    }

    private var sleepRating: Int {
        Int((entry.sleepPerception * 4).rounded()) + 1
    }

    private var emotionText: String {
        guard !entry.emotionLabels.isEmpty else {
            return MindfulnessEmotion.selected(in: entry).title
        }
        return entry.emotionLabels.map(\.title).joined(separator: ", ")
    }

    private var associationText: String {
        guard !entry.associations.isEmpty else { return "None saved" }
        return entry.associations.map(\.title).joined(separator: ", ")
    }
}

#Preview("Full Day Mindfulness Insights") {
    MindfulnessFullDayInsightsView(
        entry: MindfulnessHistoryPreviewData.entries[0]
    )
}
