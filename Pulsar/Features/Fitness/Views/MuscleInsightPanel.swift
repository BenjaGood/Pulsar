//
//  MuscleInsightPanel.swift
//  Pulsar
//

import SwiftUI

struct MuscleInsightPanel: View {
    var presentation: MuscleFocusMapPresentation

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            MuscleInsightSymbol()

            VStack(alignment: .leading, spacing: 4) {
                Text("INSIGHT")
                    .font(.caption.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.active)

                Text(presentation.insight)
                    .font(.subheadline)
                    .foregroundStyle(PulsarTheme.fitnessSecondaryText(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
            }

            Spacer(minLength: 4)

            MuscleIntensityMeter(intensity: presentation.overallIntensity)
                .frame(width: 88, alignment: .leading)
        }
        .padding(12)
        .background(.white.opacity(colorScheme == .dark ? 0.045 : 0.54), in: RoundedRectangle(cornerRadius: 22))
        .modifier(FitnessGlassSurfaceModifier(cornerRadius: 22, tint: PulsarFitnessMonochromeDesign.primaryText, borderOpacity: 0.50))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(presentation.insightTitle). \(presentation.insight). Overall intensity: \(presentation.overallIntensity.title).")
    }
}

private struct MuscleInsightSymbol: View {
    var body: some View {
        Image(systemName: "chart.line.uptrend.xyaxis")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
            .frame(width: 38, height: 38)
            .background(PulsarFitnessMonochromeDesign.primaryText.opacity(0.12), in: Circle())
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

private struct MuscleIntensityMeter: View {
    var intensity: MuscleIntensity

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("INTENSITY")
                .font(.caption.weight(.semibold))
                .tracking(0.7)
                .foregroundStyle(PulsarTheme.fitnessTertiaryText(for: colorScheme))

            HStack(spacing: 3) {
                ForEach(0..<6, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(fill(for: index))
                        .frame(width: 11, height: 12)
                }
            }

            Text(intensity.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(PulsarTheme.fitnessSecondaryText(for: colorScheme))
        }
        .accessibilityHidden(true)
    }

    private func fill(for index: Int) -> Color {
        let activeSegments = intensity.rank * 2
        guard index < activeSegments else {
            return .white.opacity(colorScheme == .dark ? 0.055 : 0.18)
        }
        let progress = Double(index) / 5
        return PulsarFitnessMonochromeDesign.primaryText
    }
}
