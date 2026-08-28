import SwiftUI

struct StressCardSurfaceModifier: ViewModifier {
    var cornerRadius: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)

        content
            .background(fill, in: shape)
            .overlay {
                shape.stroke(.white.opacity(colorScheme == .dark ? 0.16 : 0.80), lineWidth: 0.8)
            }
            .glassEffect(
                reduceTransparency ? .identity : .regular,
                in: .rect(cornerRadius: cornerRadius)
            )
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.12 : 0.035),
                radius: 22,
                y: 9
            )
    }

    private var fill: Color {
        if colorScheme == .dark {
            return reduceTransparency
                ? Color(red: 24 / 255, green: 24 / 255, blue: 28 / 255)
                : .black.opacity(0.34)
        }

        return reduceTransparency ? .white : .white.opacity(0.82)
    }
}

extension View {
    func stressCardSurface(cornerRadius: CGFloat = StressDetailsDesign.cardCornerRadius) -> some View {
        modifier(StressCardSurfaceModifier(cornerRadius: cornerRadius))
    }
}
