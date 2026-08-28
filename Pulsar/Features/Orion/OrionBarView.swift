//
//  OrionBarView.swift
//  Pulsar
//

import SwiftUI

private enum OrionBarMetrics {
    static let regularHeight: CGFloat = 50
    static let compactHeight: CGFloat = 44
    static let regularCornerRadius: CGFloat = 25
    static let compactCornerRadius: CGFloat = 22
}

struct OrionBarView: View {
    var isInlinePlacement = false
    var usesNativeAccessoryChrome = false
    let onOpen: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: onOpen) {
                label
                    .modifier(PulsarBottomChromeGlassModifier(
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
                    .shadow(color: .black.opacity(0.10), radius: 14, x: 0, y: 7)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ask Orion")
            .accessibilityHint("Opens the Orion assistant")
        }
    }

    private var cornerRadius: CGFloat {
        isInlinePlacement ? OrionBarMetrics.compactCornerRadius : OrionBarMetrics.regularCornerRadius
    }

    private var label: some View {
        HStack(spacing: isInlinePlacement ? 8 : 13) {
            Image("oriononly")
                .renderingMode(.original)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(
                    width: isInlinePlacement ? 32 : 38,
                    height: isInlinePlacement ? 32 : 38
                )
                .accessibilityHidden(true)

            Text("Ask Orion")
                .font(.headline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .layoutPriority(1)

            Spacer(minLength: 0)

            Image(systemName: "mic.fill")
                .font(.system(size: isInlinePlacement ? 15 : 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: isInlinePlacement ? 30 : 34, height: isInlinePlacement ? 30 : 34)
                .accessibilityHidden(true)
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .frame(minWidth: 1, maxWidth: .infinity)
        .frame(height: isInlinePlacement ? OrionBarMetrics.compactHeight : OrionBarMetrics.regularHeight)
        .contentShape(.rect(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct OrionLogoView: View {
    var size: CGFloat

    var body: some View {
        Image("Orion")
            .renderingMode(.original)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

#Preview("Orion Bar") {
    ZStack {
        HomePremiumDesign.background
            .ignoresSafeArea()

        VStack {
            Spacer()
            OrionBarView {}
                .padding()
        }
    }
}
