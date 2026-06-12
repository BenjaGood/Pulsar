//
//  OrionBarView.swift
//  Pulsar
//

import SwiftUI

struct OrionBarView: View {
    var isInlinePlacement = false
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: isInlinePlacement ? 8 : 11) {
                OrionLogoView(size: isInlinePlacement ? 31 : 38)

                Text("Ask Orion")
                    .font(.system(size: isInlinePlacement ? 15 : 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .layoutPriority(1)
                    .shadow(color: .black.opacity(0.42), radius: 1.6, x: 0, y: 1)

                Spacer(minLength: 0)

                Image(systemName: "mic.fill")
                    .font(.system(size: isInlinePlacement ? 15 : 17, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: isInlinePlacement ? 28 : 34, height: isInlinePlacement ? 32 : 38)
                    .shadow(color: .black.opacity(0.34), radius: 1.4, x: 0, y: 1)
                    .accessibilityHidden(true)
            }
            .padding(.leading, isInlinePlacement ? 7 : 9)
            .padding(.trailing, isInlinePlacement ? 9 : 11)
            .frame(minWidth: 1, maxWidth: .infinity)
            .frame(height: isInlinePlacement ? 44 : 54)
            .contentShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .modifier(OrionBarBackgroundModifier(cornerRadius: cornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask Orion")
        .accessibilityHint("Opens the Orion assistant")
    }

    private var cornerRadius: CGFloat {
        isInlinePlacement ? 23 : 28
    }
}

struct OrionLogoView: View {
    var size: CGFloat

    var body: some View {
        Image("Orion")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .stroke(.white.opacity(0.22), lineWidth: 0.6)
                    .blendMode(.plusLighter)
            }
            .shadow(color: Color(red: 0.44, green: 0.76, blue: 1.0).opacity(0.16), radius: 8, x: 0, y: 3)
            .accessibilityHidden(true)
    }
}

private struct OrionBarBackgroundModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 18) {
                content
                    .background(glassTint, in: shape)
                    .overlay {
                        shape
                            .stroke(innerDepthGradient, lineWidth: 1)
                            .blendMode(.overlay)
                    }
                    .glassEffect(
                        .regular
                            .tint(Color(red: 0.48, green: 0.66, blue: 0.95).opacity(0.075))
                            .interactive(),
                        in: .rect(cornerRadius: cornerRadius, style: .continuous)
                    )
                    .overlay {
                        shape
                            .stroke(borderGradient, lineWidth: 0.75)
                            .blendMode(.plusLighter)
                    }
                    .overlay(alignment: .top) {
                        specularHighlight
                    }
                    .overlay(alignment: .bottom) {
                        bottomRefraction
                    }
                    .shadow(color: Color(red: 0.32, green: 0.62, blue: 1.0).opacity(0.10), radius: 18, x: 0, y: 8)
                    .shadow(color: .black.opacity(0.18), radius: 20, x: 0, y: 12)
            }
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(glassTint, in: shape)
                .overlay {
                    shape
                        .stroke(borderGradient, lineWidth: 0.75)
                }
                .overlay(alignment: .top) {
                    specularHighlight
                }
                .overlay(alignment: .bottom) {
                    bottomRefraction
                }
                .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 10)
        }
    }

    private var glassTint: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.10),
                Color(red: 0.14, green: 0.18, blue: 0.27).opacity(0.24),
                Color(red: 0.04, green: 0.07, blue: 0.12).opacity(0.18)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(0.46),
                Color(red: 0.74, green: 0.88, blue: 1.0).opacity(0.24),
                .white.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var innerDepthGradient: LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(0.20),
                .clear,
                .black.opacity(0.24)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var specularHighlight: some View {
        LinearGradient(
            colors: [
                .clear,
                .white.opacity(0.52),
                Color(red: 0.73, green: 0.86, blue: 1.0).opacity(0.22),
                .clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1.4)
        .padding(.horizontal, 18)
        .padding(.top, 1.5)
        .clipShape(Capsule())
        .blendMode(.plusLighter)
    }

    private var bottomRefraction: some View {
        LinearGradient(
            colors: [
                .clear,
                Color(red: 0.55, green: 0.76, blue: 1.0).opacity(0.14),
                .clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
        .padding(.horizontal, 24)
        .padding(.bottom, 1)
        .clipShape(Capsule())
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
