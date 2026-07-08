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
        PulsarGlassCard(
            cornerRadius: cornerRadius,
            contentPadding: 0,
            tint: tint.opacity(0.08),
            isInteractive: isInteractive
        ) {
            content
        }
            .shadow(color: .black.opacity(appearance.glassShadowOpacity), radius: appearance.glassShadowRadius, y: appearance.glassShadowY)
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
        let shape = Capsule(style: .continuous)

        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(shape.fill(Color.black.opacity(PulsarGlassStandard.fillOpacity)))
            .overlay {
                shape
                    .stroke(.white.opacity(PulsarGlassStandard.strokeOpacity), lineWidth: PulsarGlassStandard.strokeWidth)
            }
            .modifier(PremiumGlassPillEffect(tint: tint, nativeTintOpacity: 0.08))
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
                .pulsarTextStyle(.title)
                .foregroundStyle(.white)
                .padding(40)
        }
        .padding(30)
    }
}
