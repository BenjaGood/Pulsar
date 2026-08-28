//
//  MindfulnessHistoryMetricRow.swift
//  Pulsar
//

import SwiftUI

struct MindfulnessHistoryMetricRow: View {
    var question: MindfulnessQuestion
    var rating: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: question.symbolName)
                    .font(.subheadline)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(MindfulnessDesign.primaryText)
                    .frame(width: 20)
                    .accessibilityHidden(true)

                Text(question.title)
                    .font(.subheadline)
                    .foregroundStyle(MindfulnessDesign.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 6)

                Text("\(rating)/5")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(MindfulnessDesign.secondaryText)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(MindfulnessDesign.track.opacity(0.55))

                    Capsule()
                        .fill(MindfulnessDesign.primaryText)
                        .frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(question.title), \(rating) out of 5")
    }

    private var progress: Double {
        Double(min(max(rating, 1), 5)) / 5
    }
}
