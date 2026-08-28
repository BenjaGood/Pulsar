import SwiftUI

struct StressHeroSurfaceModifier: ViewModifier {
    var cornerRadius: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)

        content
            .background(fill, in: shape)
            .overlay {
                shape.stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(colorScheme == .dark ? 0.14 : 0.56),
                            .white.opacity(0.08),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.6
                )
            }
            .glassEffect(
                reduceTransparency ? .identity : .regular,
                in: .rect(cornerRadius: cornerRadius)
            )
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.10 : 0.028),
                radius: 26,
                y: 10
            )
    }

    private var fill: Color {
        if colorScheme == .dark {
            reduceTransparency
                ? Color(red: 24 / 255, green: 24 / 255, blue: 28 / 255)
                : .black.opacity(0.30)
        } else {
            reduceTransparency ? .white : .white.opacity(0.88)
        }
    }
}

extension View {
    func stressHeroSurface(cornerRadius: CGFloat = StressDetailsDesign.heroCornerRadius) -> some View {
        modifier(StressHeroSurfaceModifier(cornerRadius: cornerRadius))
    }
}
