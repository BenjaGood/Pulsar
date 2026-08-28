import SwiftUI

struct StrainCardSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)

        content
            .background(cardFill, in: shape)
            .overlay {
                shape.stroke(borderColor, lineWidth: 1)
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.055),
                radius: 18,
                y: 10
            )
    }

    private var cardFill: Color {
        if colorScheme == .dark {
            reduceTransparency
                ? Color(red: 0.105, green: 0.100, blue: 0.120)
                : .black.opacity(0.34)
        } else {
            .white.opacity(reduceTransparency ? 0.97 : 0.84)
        }
    }

    private var borderColor: Color {
        .white.opacity(colorScheme == .dark ? 0.18 : 0.76)
    }
}

extension View {
    func strainCardSurface(
        cornerRadius: CGFloat = StrainDetailsDesign.cardCornerRadius
    ) -> some View {
        modifier(StrainCardSurfaceModifier(cornerRadius: cornerRadius))
    }
}
