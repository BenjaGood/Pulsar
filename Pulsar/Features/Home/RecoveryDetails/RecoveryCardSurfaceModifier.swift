import SwiftUI

struct RecoveryCardSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: RecoveryDetailsDesign.cardCornerRadius)

        content
            .background(fill, in: shape)
            .overlay {
                shape.stroke(.white.opacity(colorScheme == .dark ? 0.18 : 0.72), lineWidth: 0.8)
            }
            .glassEffect(
                reduceTransparency ? .identity : .regular,
                in: .rect(cornerRadius: RecoveryDetailsDesign.cardCornerRadius)
            )
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.12 : 0.035),
                radius: 24,
                y: 10
            )
    }

    private var fill: Color {
        if colorScheme == .dark {
            reduceTransparency
                ? Color(red: 24 / 255, green: 24 / 255, blue: 29 / 255)
                : .black.opacity(0.36)
        } else {
            reduceTransparency ? .white : .white.opacity(0.72)
        }
    }
}

extension View {
    func recoveryCardSurface() -> some View {
        modifier(RecoveryCardSurfaceModifier())
    }
}
