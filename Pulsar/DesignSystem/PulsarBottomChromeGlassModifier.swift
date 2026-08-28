import SwiftUI

struct PulsarBottomChromeGlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    let usesNativeAccessoryChrome: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26.0, *) {
            if usesNativeAccessoryChrome {
                content
                    .background(reduceTransparency ? Color(.systemBackground).opacity(0.92) : .clear, in: shape)
                    .overlay { shape.stroke(borderHighlight, lineWidth: contrast == .increased ? 1.2 : 0.75) }
                    .overlay(alignment: .top) { specularHighlight }
                    .overlay(alignment: .bottom) { lowerRefractionHighlight }
            } else {
                content
                    .background(.white.opacity(reduceTransparency ? 0.94 : 0.54), in: shape)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius, style: .continuous))
                    .overlay { shape.stroke(.black.opacity(0.055), lineWidth: 0.7) }
                    .shadow(color: .black.opacity(0.065), radius: 16, y: 8)
            }
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay { shape.stroke(.white.opacity(0.18), lineWidth: 0.75) }
        }
    }

    private var borderHighlight: LinearGradient {
        LinearGradient(
            colors: contrast == .increased
                ? [.white.opacity(0.72), .white.opacity(0.30), .white.opacity(0.12)]
                : [.white.opacity(0.48), .white.opacity(0.16), .white.opacity(0.03)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var specularHighlight: some View {
        LinearGradient(colors: [.clear, .white.opacity(0.70), .white.opacity(0.24), .clear], startPoint: .leading, endPoint: .trailing)
            .frame(height: 1.2)
            .padding(.horizontal, 22)
            .padding(.top, 1.6)
            .clipShape(.capsule)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }

    private var lowerRefractionHighlight: some View {
        LinearGradient(colors: [.clear, .white.opacity(0.18), .clear], startPoint: .leading, endPoint: .trailing)
            .frame(height: 0.8)
            .padding(.horizontal, 28)
            .padding(.bottom, 1)
            .clipShape(.capsule)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }
}
