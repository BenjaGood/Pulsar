//
//  MindfulnessWeekdayMoodIndicator.swift
//  Pulsar
//

import SwiftUI

struct MindfulnessWeekdayMoodIndicator: View {
    var day: PulsarMindfulnessWeekSnapshot.Day

    @Environment(\.calendar) private var calendar

    var body: some View {
        VStack(spacing: 7) {
            Text(day.date, format: .dateTime.weekday(.abbreviated))
                .font(.caption)
                .foregroundStyle(isToday ? MindfulnessDesign.primaryText : MindfulnessDesign.secondaryText)

            ZStack {
                Circle()
                    .fill(Color.white.opacity(day.entry == nil ? 0.34 : 0.76))
                    .overlay {
                        Circle()
                            .strokeBorder(
                                isToday ? MindfulnessDesign.primaryText : MindfulnessDesign.separator,
                                lineWidth: isToday ? 1.1 : 0.7
                            )
                    }

                if let emotion {
                    MindfulnessEmotionFace(emotion: emotion)
                        .frame(width: 19, height: 19)
                        .opacity(day.entry == nil ? 0.38 : 0.78)
                } else {
                    Image(systemName: "minus")
                        .font(.caption2)
                        .foregroundStyle(MindfulnessDesign.tertiaryText)
                }
            }
            .frame(width: 34, height: 34)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityValue(emotion?.title ?? "No mood logged")
    }

    private var emotion: MindfulnessEmotion? {
        guard let entry = day.entry else { return nil }
        return MindfulnessEmotion.selected(in: PulsarDailyJournalDraft(entry: entry))
    }

    private var isToday: Bool {
        calendar.isDateInToday(day.date)
    }
}
