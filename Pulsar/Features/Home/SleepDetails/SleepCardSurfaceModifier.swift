import SwiftUI

struct SleepCardSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: SleepDetailsDesign.cardCornerRadius
        )

        if reduceTransparency {
            content
                .background(reducedTransparencyFill, in: shape)
                .overlay {
                    shape.stroke(borderColor, lineWidth: 1)
                }
                .shadow(
                    color: Color(red: 20 / 255, green: 20 / 255, blue: 40 / 255)
                        .opacity(0.05),
                    radius: 40,
                    y: 12
                )
        } else {
            content
                .background(cardFill, in: shape)
                .overlay {
                    shape.stroke(borderColor, lineWidth: 1)
                }
                .glassEffect(
                    .regular,
                    in: .rect(cornerRadius: SleepDetailsDesign.cardCornerRadius)
                )
                .shadow(
                    color: Color(red: 20 / 255, green: 20 / 255, blue: 40 / 255)
                        .opacity(0.05),
                    radius: 40,
                    y: 12
                )
        }
    }

    private var cardFill: Color {
        colorScheme == .dark
            ? .black.opacity(0.28)
            : .white.opacity(0.72)
    }

    private var reducedTransparencyFill: Color {
        colorScheme == .dark
            ? Color(red: 24 / 255, green: 24 / 255, blue: 30 / 255)
            : .white.opacity(0.96)
    }

    private var borderColor: Color {
        .white.opacity(colorScheme == .dark ? 0.22 : 0.55)
    }
}

extension View {
    func sleepCardSurface() -> some View {
        modifier(SleepCardSurfaceModifier())
    }
}
