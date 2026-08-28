//
//  MuscleBodyAssetMapView.swift
//  Pulsar
//

import SwiftUI

struct MuscleBodyAssetMapView: View {
    var presentation: MuscleFocusMapPresentation
    var hasAppeared: Bool
    var isRenderingEnabled: Bool

    var body: some View {
        ZStack {
            HStack(alignment: .center, spacing: 2) {
                MuscleBodyFigureView(
                    isBack: false,
                    entries: presentation.entries,
                    hasAppeared: hasAppeared,
                    isRenderingEnabled: isRenderingEnabled
                )
                .frame(maxWidth: .infinity)

                MuscleBodyFigureView(
                    isBack: true,
                    entries: presentation.entries,
                    hasAppeared: hasAppeared,
                    isRenderingEnabled: isRenderingEnabled
                )
                .frame(maxWidth: .infinity)
            }

            VStack(spacing: 6) {
                Rectangle()
                    .fill(.black.opacity(0.055))
                    .frame(width: 0.7)
                    .frame(maxHeight: .infinity)

                Image(systemName: "waveform.path.ecg")
                    .font(.caption)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.tertiaryText)
                    .padding(5)
                    .background(.white.opacity(0.82), in: Circle())

                Rectangle()
                    .fill(.black.opacity(0.055))
                    .frame(width: 0.7)
                    .frame(maxHeight: .infinity)
            }
            .padding(.vertical, 54)
            .accessibilityHidden(true)
        }
        .frame(height: 370)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        let highlights = presentation.entries
            .filter(\.isActive)
            .map { "\($0.displayName) \($0.intensity.title.lowercased())" }
            .joined(separator: ", ")
        return highlights.isEmpty
            ? "Front and back muscle focus maps. No muscle activity logged."
            : "Front and back muscle focus maps. \(highlights)."
    }
}
