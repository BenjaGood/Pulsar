//
//  PulsarGlassCard.swift
//  Pulsar
//

import SwiftUI

enum PulsarGlassStandard {
    static let cardCornerRadius: CGFloat = 28
    static let compactCornerRadius: CGFloat = 24
    static let buttonCornerRadius: CGFloat = 16
    static let iconCircleSize: CGFloat = 44

    static let fillOpacity: Double = 0.18
    static let tintedFillOpacity: Double = 0.22
    static let reducedTransparencyFillOpacity: Double = 0.84

    static let strokeOpacity: Double = 0.14
    static let tintedStrokeOpacity: Double = 0.18
    static let reducedTransparencyStrokeOpacity: Double = 0.24
    static let reducedTransparencyTintedStrokeOpacity: Double = 0.26
    static let strokeWidth: CGFloat = 0.8
    static let tintedStrokeWidth: CGFloat = 0.9

    static let tintedShadowOpacity: Double = 0.18
    static let tintedShadowRadius: CGFloat = 16
    static let tintedShadowY: CGFloat = 9

    static let prominentButtonTint = Color(red: 0.38, green: 0.72, blue: 1.00).opacity(0.48)
}

struct PulsarGlassCard<Content: View>: View {
    var cornerRadius: CGFloat = PulsarGlassStandard.cardCornerRadius
    var contentPadding: CGFloat = 18
    var tint: Color?
    var fillOpacity: Double?
    var suppressShadow = false
    var isInteractive = false
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.pulsarFitnessUsesMonochromeAppearance) private var usesFitnessMonochromeAppearance

    init(
        cornerRadius: CGFloat = PulsarGlassStandard.cardCornerRadius,
        contentPadding: CGFloat = 18,
        tint: Color? = nil,
        fillOpacity: Double? = nil,
        suppressShadow: Bool = false,
        isInteractive: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.contentPadding = contentPadding
        self.tint = tint
        self.fillOpacity = fillOpacity
        self.suppressShadow = suppressShadow
        self.isInteractive = isInteractive
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if usesFitnessMonochromeAppearance {
            baseContent
                .pulsarFitnessMonochromeSurface(
                    cornerRadius: cornerRadius,
                    isInteractive: isInteractive,
                    shadowOpacity: suppressShadow ? 0 : 0.055
                )
        } else if tint != nil {
            let resolvedFillOpacity = fillOpacity ?? (reduceTransparency ? PulsarGlassStandard.reducedTransparencyFillOpacity : PulsarGlassStandard.tintedFillOpacity)
            baseContent
                .background {
                    shape.fill(
                        Color.black
                            .opacity(resolvedFillOpacity)
                    )
                }
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(reduceTransparency ? 0.05 : 0.10),
                                .white.opacity(0.02),
                                Color.black.opacity(reduceTransparency ? 0.06 : 0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .allowsHitTesting(false)
                }
                .overlay {
                    shape.strokeBorder(
                        .white.opacity(reduceTransparency ? PulsarGlassStandard.reducedTransparencyTintedStrokeOpacity : PulsarGlassStandard.tintedStrokeOpacity),
                        lineWidth: PulsarGlassStandard.tintedStrokeWidth
                    )
                }
                .modifier(PulsarGlassCardShadowModifier(suppressed: suppressShadow))
                .pulsarLiquidGlass(cornerRadius: cornerRadius, interactive: isInteractive, isClear: true)
        } else {
            baseContent
                .background {
                    shape.fill(
                        Color.black
                            .opacity(reduceTransparency ? PulsarGlassStandard.reducedTransparencyFillOpacity : PulsarGlassStandard.fillOpacity)
                    )
                }
                .overlay {
                    shape.strokeBorder(
                        .white.opacity(reduceTransparency ? PulsarGlassStandard.reducedTransparencyStrokeOpacity : PulsarGlassStandard.strokeOpacity),
                        lineWidth: PulsarGlassStandard.strokeWidth
                    )
                }
                .pulsarLiquidGlass(cornerRadius: cornerRadius, interactive: isInteractive)
        }
    }

    private var baseContent: some View {
        content
            .padding(contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PulsarGlassCardShadowModifier: ViewModifier {
    var suppressed: Bool

    func body(content: Content) -> some View {
        if suppressed {
            content
        } else {
            content
                .shadow(
                    color: .black.opacity(PulsarGlassStandard.tintedShadowOpacity),
                    radius: PulsarGlassStandard.tintedShadowRadius,
                    y: PulsarGlassStandard.tintedShadowY
                )
        }
    }
}

struct PulsarGlassIconCircle: View {
    var size: CGFloat = PulsarGlassStandard.iconCircleSize
    var tint: Color = Color(red: 0.68, green: 0.80, blue: 0.92)
    var systemImage: String
    var symbolScale: CGFloat = 0.42

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: max(12, size * symbolScale), weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(PulsarCircularGlassSurface(cornerRadius: size / 2, tint: tint))
    }
}

extension View {
    @ViewBuilder
    func pulsarGlassProminent(
        tint: Color = PulsarGlassStandard.prominentButtonTint,
        cornerRadius: CGFloat = PulsarGlassStandard.buttonCornerRadius
    ) -> some View {
        if #available(iOS 26.0, *) {
            self
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.roundedRectangle(radius: cornerRadius))
                .controlSize(.regular)
                .tint(tint)
                .foregroundStyle(.white)
        } else {
            self
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: cornerRadius))
                .controlSize(.regular)
                .tint(tint)
                .foregroundStyle(.white)
        }
    }
}

#Preview("Pulsar Glass Card") {
    ZStack {
        MindfulnessScenicBackground()
        VStack(spacing: 16) {
            PulsarGlassCard {
                Text("Untinted")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            PulsarGlassCard(tint: .cyan) {
                Text("Tinted")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            Button("Log") {}
                .frame(maxWidth: .infinity, minHeight: 24)
                .pulsarGlassProminent()
        }
        .padding(24)
    }
}
