//
//  OrionBarView.swift
//  Pulsar
//

import SwiftUI

struct OrionBarView: View {
    var isInlinePlacement = false
    var usesNativeAccessoryChrome = false
    let onOpen: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: onOpen) {
                label
                    .modifier(OrionLiquidGlassChromeModifier(
                        cornerRadius: cornerRadius,
                        usesNativeAccessoryChrome: usesNativeAccessoryChrome
                    ))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ask Orion")
            .accessibilityHint("Opens the Orion assistant")
        } else {
            Button(action: onOpen) {
                label
                    .background(.ultraThinMaterial, in: .capsule)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(.white.opacity(0.18), lineWidth: 0.7)
                    }
                    .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ask Orion")
            .accessibilityHint("Opens the Orion assistant")
        }
    }

    private var cornerRadius: CGFloat {
        isInlinePlacement ? 23 : 28
    }

    private var label: some View {
        HStack(spacing: isInlinePlacement ? 8 : 11) {
            OrionLogoView(size: isInlinePlacement ? 31 : 38)

            Text("Ask Orion")
                .pulsarTextStyle(.buttonTitle)
                .foregroundStyle(.white.opacity(0.94))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .layoutPriority(1)

            Spacer(minLength: 0)

            Image(systemName: "mic.fill")
                .font(.system(size: isInlinePlacement ? 15 : 17, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: isInlinePlacement ? 32 : 38, height: isInlinePlacement ? 32 : 38)
                .accessibilityHidden(true)
        }
        .padding(.leading, isInlinePlacement ? 7 : 9)
        .padding(.trailing, isInlinePlacement ? 9 : 11)
        .frame(minWidth: 1, maxWidth: .infinity)
        .frame(height: isInlinePlacement ? 44 : 54)
        .contentShape(.rect(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct OrionLiquidGlassChromeModifier: ViewModifier {
    let cornerRadius: CGFloat
    let usesNativeAccessoryChrome: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26.0, *) {
            if usesNativeAccessoryChrome {
                content
                    .overlay {
                        shape
                            .stroke(borderHighlight, lineWidth: 0.75)
                            .blendMode(.plusLighter)
                    }
                    .overlay(alignment: .top) {
                        specularHighlight
                    }
                    .overlay(alignment: .bottom) {
                        lowerRefractionHighlight
                    }
            } else {
                content
                    .glassEffect(
                        .regular.interactive(),
                        in: .rect(cornerRadius: cornerRadius, style: .continuous)
                    )
            }
        } else {
            content
        }
    }

    private var borderHighlight: LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(0.48),
                .white.opacity(0.16),
                .white.opacity(0.03)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var specularHighlight: some View {
        LinearGradient(
            colors: [
                .clear,
                .white.opacity(0.70),
                .white.opacity(0.24),
                .clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1.2)
        .padding(.horizontal, 22)
        .padding(.top, 1.6)
        .clipShape(Capsule())
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    private var lowerRefractionHighlight: some View {
        LinearGradient(
            colors: [
                .clear,
                .white.opacity(0.18),
                .clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 0.8)
        .padding(.horizontal, 28)
        .padding(.bottom, 1)
        .clipShape(Capsule())
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}

struct OrionLogoView: View {
    var size: CGFloat

    var body: some View {
        Image("Orion")
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

#Preview("Orion Bar") {
    ZStack {
        StaticTimeBackgroundView(mode: .night)
            .ignoresSafeArea()

        VStack {
            Spacer()
            OrionBarView {}
                .padding()
        }
    }
}
