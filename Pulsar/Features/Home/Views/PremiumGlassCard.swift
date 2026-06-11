//
//  PremiumGlassCard.swift
//  Pulsar
//

import SwiftUI

struct PremiumGlassContainer<Content: View>: View {
    var cornerRadius: CGFloat = 32
    var tint: Color = Color(red: 0.46, green: 0.86, blue: 0.66)
    var isInteractive = false
    @ViewBuilder var content: Content

    @Environment(\.homeAdaptiveAppearance) private var appearance

    var body: some View {
        content
            .background(glassFill)
            .clipShape(cardShape)
            .overlay(refractiveHighlights)
            .overlay(cardBorder)
            .overlay(innerHighlight)
            .background(contactGlow)
            .shadow(color: .black.opacity(appearance.glassShadowOpacity), radius: appearance.glassShadowRadius, y: appearance.glassShadowY)
            .modifier(
                PremiumGlassEffect(
                    cornerRadius: cornerRadius,
                    tint: appearance.nativeGlassTint,
                    nativeTintOpacity: appearance.nativeGlassTintOpacity,
                    isInteractive: isInteractive
                )
            )
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var glassFill: some View {
        cardShape
            .fill(
                LinearGradient(
                    colors: appearance.glassFillColors(tint: tint),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                cardShape
                    .fill(
                        RadialGradient(
                            colors: appearance.glassRadialColors(tint: tint),
                            center: .bottom,
                            startRadius: 18,
                            endRadius: 240
                        )
                    )
                    .blendMode(.screen)
            }
    }

    private var cardBorder: some View {
        cardShape
            .stroke(
                LinearGradient(
                    colors: appearance.glassBorderColors(tint: tint),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.55
            )
    }

    private var refractiveHighlights: some View {
        cardShape
            .fill(
                LinearGradient(
                    colors: appearance.glassHighlightColors(),
                    startPoint: .topLeading,
                    endPoint: UnitPoint(x: 0.58, y: 0.62)
                )
            )
            .blendMode(.screen)
            .overlay(alignment: .bottomTrailing) {
                cardShape
                    .inset(by: 1.2)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .clear,
                                tint.opacity(appearance.usesLightText ? 0.13 : 0.10),
                                .white.opacity(appearance.usesLightText ? 0.055 : 0.080)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
                    .blur(radius: 0.2)
            }
            .allowsHitTesting(false)
    }

    private var innerHighlight: some View {
        cardShape
            .inset(by: 1)
            .stroke(
                LinearGradient(
                    colors: appearance.glassInnerBorderColors(tint: tint),
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.45
            )
            .blendMode(.screen)
            .allowsHitTesting(false)
    }

    private var contactGlow: some View {
        cardShape
            .stroke(
                LinearGradient(
                    colors: [
                        .clear,
                        tint.opacity(0.19),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.1
            )
            .blur(radius: 10)
            .offset(y: 3)
            .opacity(appearance.contactGlowOpacity(for: tint))
    }
}

private struct PremiumGlassEffect: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color
    var nativeTintOpacity: Double
    var isInteractive: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26.0, *) {
            if isInteractive {
                content.glassEffect(.regular.tint(tint.opacity(nativeTintOpacity)).interactive(), in: .rect(cornerRadius: cornerRadius, style: .continuous))
            } else {
                content.glassEffect(.regular.tint(tint.opacity(nativeTintOpacity)), in: .rect(cornerRadius: cornerRadius, style: .continuous))
            }
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
        }
    }
}

struct PremiumGlassPill<Content: View>: View {
    var tint: Color = .white
    var horizontalPadding: CGFloat = 12
    var verticalPadding: CGFloat = 8
    @ViewBuilder var content: Content

    @Environment(\.homeAdaptiveAppearance) private var appearance

    var body: some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: appearance.pillFillColors(tint: tint),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: appearance.pillBorderColors(tint: tint),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.55
                    )
            }
            .overlay {
                Capsule(style: .continuous)
                    .inset(by: 1)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(appearance.usesLightText ? 0.090 : 0.135), .clear, tint.opacity(0.050)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.4
                    )
            }
            .modifier(PremiumGlassPillEffect(tint: appearance.nativeGlassTint, nativeTintOpacity: appearance.nativeGlassTintOpacity))
    }
}

private struct PremiumGlassPillEffect: ViewModifier {
    var tint: Color
    var nativeTintOpacity: Double

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(tint.opacity(nativeTintOpacity * 0.80)), in: .rect(cornerRadius: 999, style: .continuous))
        } else {
            content.background(.ultraThinMaterial, in: Capsule(style: .continuous))
        }
    }
}

#Preview("Premium Glass Card") {
    ZStack {
        StaticTimeBackgroundView(mode: .sunset)
        PremiumGlassContainer(tint: .green) {
            Text("Glass")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(40)
        }
        .padding(30)
    }
}
