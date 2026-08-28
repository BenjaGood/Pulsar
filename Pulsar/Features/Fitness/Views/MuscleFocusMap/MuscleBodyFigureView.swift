//
//  MuscleBodyFigureView.swift
//  Pulsar
//

import SwiftUI

struct MuscleBodyFigureView: View {
    var isBack: Bool
    var entries: [MuscleFocusMapPresentation.Entry]
    var hasAppeared: Bool
    var isRenderingEnabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var revealProgress = 0.0

    var body: some View {
        VStack(spacing: 3) {
            figureStack
                .aspectRatio(MuscleBodyAssetDimensions.aspectRatio(isBack: isBack), contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .shadow(color: .black.opacity(0.12), radius: 13, y: 7)

            Text(isBack ? "Back" : "Front")
                .font(.caption.weight(.medium))
                .foregroundStyle(PulsarTheme.fitnessTertiaryText(for: colorScheme))
                .accessibilityHidden(true)
        }
        .onAppear {
            animateRevealIfNeeded()
        }
        .onChange(of: hasAppeared) { _, hasAppeared in
            guard hasAppeared else { return }
            animateRevealIfNeeded()
        }
        .onChange(of: muscleOverlayEntries) { _, _ in
            animateRevealIfNeeded(restarting: true)
        }
        .onChange(of: isRenderingEnabled) { _, isRenderingEnabled in
            guard isRenderingEnabled else { return }
            animateRevealIfNeeded()
        }
    }

    @ViewBuilder
    private var figureStack: some View {
        if let baseImageName = MuscleAssetNameResolver.imageName(for: .base(isBack: isBack)),
           MuscleAssetNameResolver.isAvailable(named: baseImageName) {
            GeometryReader { geometry in
                let size = geometry.size

                ZStack {
                    MuscleBodyAlignedImage(imageName: baseImageName)
                        .grayscale(1)
                        .colorInvert()
                        .brightness(-0.30)
                        .contrast(1.55)
                        .frame(width: size.width, height: size.height)
                }
                .frame(width: size.width, height: size.height)
            }
            .modifier(MuscleFigureRasterizationModifier(isEnabled: isRenderingEnabled))
        } else {
            MuscleBodyAssetFallback(isBack: isBack)
        }
    }

    private var muscleOverlayEntries: [MuscleFocusMapPresentation.Entry] {
        entries.filter { entry in
            entry.isActive && entry.muscleGroup != .cardio
        }
    }

    private func animateRevealIfNeeded(restarting: Bool = false) {
        guard hasAppeared, isRenderingEnabled else { return }
        guard restarting || revealProgress < 1 else { return }

        guard !reduceMotion else {
            revealProgress = 1
            return
        }

        revealProgress = 0.34
        withAnimation(.smooth(duration: 0.48)) {
            revealProgress = 1
        }
    }
}

private struct MuscleFigureRasterizationModifier: ViewModifier {
    var isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.drawingGroup(opaque: false, colorMode: .linear)
        } else {
            content
        }
    }
}

private struct MuscleBodyAssetFallback: View {
    var isBack: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.stand")
                .font(.system(size: 42, weight: .light))
#if DEBUG
            Text("Assets pending")
                .font(.caption)
#endif
        }
        .foregroundStyle(PulsarTheme.fitnessTertiaryText(for: colorScheme))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isBack ? "Back body asset unavailable" : "Front body asset unavailable")
    }
}
