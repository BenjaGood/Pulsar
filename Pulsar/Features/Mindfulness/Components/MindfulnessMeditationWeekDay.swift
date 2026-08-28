//
//  MindfulnessMeditationWeekDay.swift
//  Pulsar
//

import SwiftUI

struct MindfulnessMeditationWeekDay: View {
    var day: PulsarMindfulnessMeditationWeekSnapshot.Day
    var fixedWidth: CGFloat?

    var body: some View {
        VStack(spacing: 6) {
            Text(day.date, format: .dateTime.weekday(.abbreviated))
                .font(.caption)
                .foregroundStyle(MindfulnessDesign.secondaryText)

            Image(systemName: day.hasSession ? "checkmark" : "minus")
                .font(.caption)
                .foregroundStyle(day.hasSession ? MindfulnessDesign.primaryText : MindfulnessDesign.tertiaryText)
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(day.hasSession ? 0.78 : 0.34), in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(MindfulnessDesign.separator, lineWidth: 0.7)
                }
        }
        .frame(width: fixedWidth)
        .frame(maxWidth: fixedWidth == nil ? .infinity : nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide)))
        .accessibilityValue(day.hasSession ? "Meditation complete" : "No meditation logged")
    }
}
