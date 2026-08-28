//
//  MuscleFocusChip.swift
//  Pulsar
//

import SwiftUI

struct MuscleFocusChip: View {
    var entry: MuscleFocusMapPresentation.Entry

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(PulsarFitnessMonochromeDesign.active)
                .frame(width: 8, height: 8)

            Text(entry.compactName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(PulsarTheme.fitnessPrimaryText(for: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.48), in: Capsule())
        .modifier(FitnessGlassSurfaceModifier(cornerRadius: 15, borderOpacity: 0.58))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.displayName), \(entry.intensity.title) intensity")
    }
}
