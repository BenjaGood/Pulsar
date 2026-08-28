//
//  MuscleLegendView.swift
//  Pulsar
//

import SwiftUI

struct MuscleLegendView: View {
    var entries: [MuscleFocusMapPresentation.Entry]

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 66), spacing: 12)],
            alignment: .leading,
            spacing: 9
        ) {
            ForEach(entries) { entry in
                MuscleLegendItem(entry: entry)
            }
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Muscle focus legend")
    }
}

private struct MuscleLegendItem: View {
    var entry: MuscleFocusMapPresentation.Entry

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        HStack(spacing: 6) {
            if entry.muscleGroup == .cardio {
                Image(systemName: "waveform.path.ecg")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(entry.muscleGroup.accent)
                    .frame(width: 10)
            } else {
                Circle()
                    .fill(entry.muscleGroup.accent.opacity(entry.isActive ? 1 : 0.34))
                    .frame(width: 9, height: 9)
                    .overlay {
                        if differentiateWithoutColor, entry.isActive {
                            Circle().stroke(.white.opacity(0.85), lineWidth: 1)
                        }
                    }
            }

            Text(entry.compactName)
                .font(.caption)
                .foregroundStyle(PulsarTheme.fitnessSecondaryText(for: colorScheme))
                .lineLimit(1)
        }
        .accessibilityLabel("\(entry.displayName), \(entry.intensity.title) intensity")
    }
}
