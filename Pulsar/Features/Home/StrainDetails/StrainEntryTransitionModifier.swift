import SwiftUI

struct StrainEntryTransitionModifier: ViewModifier {
    var isVisible: Bool
    var delay: Double
    var offset: CGFloat
    var reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: reduceMotion || isVisible ? 0 : offset)
            .animation(
                .smooth(duration: reduceMotion ? 0.2 : 0.55)
                    .delay(reduceMotion ? 0 : delay),
                value: isVisible
            )
    }
}

extension View {
    func strainEntryTransition(
        isVisible: Bool,
        delay: Double,
        offset: CGFloat,
        reduceMotion: Bool
    ) -> some View {
        modifier(
            StrainEntryTransitionModifier(
                isVisible: isVisible,
                delay: delay,
                offset: offset,
                reduceMotion: reduceMotion
            )
        )
    }
}
