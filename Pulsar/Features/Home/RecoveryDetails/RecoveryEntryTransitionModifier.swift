import SwiftUI

struct RecoveryEntryTransitionModifier: ViewModifier {
    var isVisible: Bool
    var delay: Double
    var offset: Double
    var reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: reduceMotion || isVisible ? 0 : offset)
            .animation(
                .smooth(duration: reduceMotion ? 0.18 : 0.46).delay(delay),
                value: isVisible
            )
    }
}

extension View {
    func recoveryEntryTransition(
        isVisible: Bool,
        delay: Double,
        offset: Double,
        reduceMotion: Bool
    ) -> some View {
        modifier(
            RecoveryEntryTransitionModifier(
                isVisible: isVisible,
                delay: delay,
                offset: offset,
                reduceMotion: reduceMotion
            )
        )
    }
}
