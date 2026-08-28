import SwiftUI

struct StressInsightCardSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(fill, in: .rect(cornerRadius: 30))
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.13 : 0.035),
                radius: 20,
                y: 8
            )
    }

    private var fill: Color {
        colorScheme == .dark
            ? Color(red: 28 / 255, green: 28 / 255, blue: 32 / 255)
            : .white.opacity(0.94)
    }
}

extension View {
    func stressInsightCardSurface() -> some View {
        modifier(StressInsightCardSurfaceModifier())
    }
}
