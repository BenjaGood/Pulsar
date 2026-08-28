//
//  PremiumGlassCard.swift
//  Pulsar
//

import SwiftUI

struct PremiumGlassContainer<Content: View>: View {
    var cornerRadius: CGFloat = 32
    var tint: Color = HomePremiumDesign.accent
    var isInteractive = false
    var shadowColor: Color = HomePremiumDesign.shadow
    var shadowRadius: CGFloat = 18
    var shadowY: CGFloat = 9
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)

        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape.fill(
                    reduceTransparency
                        ? Color(.systemBackground)
                        : HomePremiumDesign.surface.opacity(0.76)
                )
            }
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(reduceTransparency ? 0 : 0.32),
                            tint.opacity(reduceTransparency ? 0.025 : 0.045),
                            Color.white.opacity(reduceTransparency ? 0 : 0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .allowsHitTesting(false)
            }
            .overlay {
                shape.stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.96),
                            tint.opacity(contrast == .increased ? 0.24 : 0.13),
                            HomePremiumDesign.border.opacity(contrast == .increased ? 1.9 : 1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: contrast == .increased ? 1.25 : 0.75
                )
                .allowsHitTesting(false)
            }
            .shadow(color: shadowColor, radius: shadowRadius, y: shadowY)
            .modifier(
                PremiumHomeSurfaceEffect(
                    cornerRadius: cornerRadius,
                    isInteractive: isInteractive,
                    reduceTransparency: reduceTransparency
                )
            )
    }
}

private struct PremiumHomeSurfaceEffect: ViewModifier {
    var cornerRadius: CGFloat
    var isInteractive: Bool
    var reduceTransparency: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content.glassEffect(
                .regular
                    .tint(Color.white.opacity(0.16))
                    .interactive(isInteractive),
                in: .rect(cornerRadius: cornerRadius)
            )
        } else if !reduceTransparency {
            content.background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius)
            )
        } else {
            content
        }
    }
}

struct PremiumGlassPill<Content: View>: View {
    var tint: Color = HomePremiumDesign.accent
    var horizontalPadding: CGFloat = 12
    var verticalPadding: CGFloat = 8
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = Capsule()

        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background {
                shape.fill(
                    reduceTransparency
                        ? Color(.systemBackground)
                        : Color.white.opacity(0.70)
                )
            }
            .overlay {
                shape.stroke(
                    tint.opacity(contrast == .increased ? 0.30 : 0.16),
                    lineWidth: contrast == .increased ? 1.15 : 0.7
                )
            }
            .modifier(
                PremiumHomePillEffect(
                    tint: tint,
                    reduceTransparency: reduceTransparency
                )
            )
    }
}

private struct PremiumHomePillEffect: ViewModifier {
    var tint: Color
    var reduceTransparency: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content.glassEffect(
                .regular.tint(tint.opacity(0.055)),
                in: .capsule
            )
        } else if !reduceTransparency {
            content.background(.thinMaterial, in: Capsule())
        } else {
            content
        }
    }
}

#Preview("Premium Home Glass") {
    PremiumGlassContainer(tint: .green) {
        Text("Glass")
            .font(.title2)
            .foregroundStyle(HomePremiumDesign.primaryText)
            .padding(40)
    }
    .padding(30)
    .background(HomePremiumDesign.background)
    .environment(\.homeAdaptiveAppearance, .premium)
}
