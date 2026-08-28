//
//  MindfulnessMeditationTemplateCard.swift
//  Pulsar
//

import SwiftUI

struct MindfulnessMeditationTemplateCard: View {
    var template: PulsarMeditationTemplate
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Image(systemName: template.category.symbolName)
                        .font(.headline)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(MindfulnessDesign.primaryText)
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.56), in: Circle())
                        .overlay {
                            Circle()
                                .strokeBorder(MindfulnessDesign.separator, lineWidth: 0.7)
                        }
                        .accessibilityHidden(true)

                    Spacer(minLength: 8)

                    Text(template.durationText)
                        .font(.caption)
                        .foregroundStyle(MindfulnessDesign.secondaryText)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(MindfulnessDesign.track.opacity(0.45), in: Capsule())
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(template.title)
                        .font(.headline)
                        .foregroundStyle(MindfulnessDesign.primaryText)
                        .lineLimit(2)

                    Text(template.category.title)
                        .font(.caption)
                        .foregroundStyle(MindfulnessDesign.tertiaryText)

                    Text(template.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(MindfulnessDesign.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 166, alignment: .leading)
            .mindfulnessCardSurface(
                cornerRadius: 24,
                isInteractive: true,
                shadowOpacity: 0.035
            )
            .contentShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(template.title), \(template.durationText)")
        .accessibilityHint("Starts this meditation")
    }
}
