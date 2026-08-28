import SwiftUI

struct SleepEntryTransitionModifier: ViewModifier {
    var isVisible: Bool
    var delay: Double
    var offset: CGFloat
    var reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : offset)
            .animation(
                reduceMotion ? nil : .smooth(duration: 0.72).delay(delay),
                value: isVisible
            )
    }
}

extension View {
    func sleepEntryTransition(
        isVisible: Bool,
        delay: Double,
        offset: CGFloat,
        reduceMotion: Bool
    ) -> some View {
        modifier(
            SleepEntryTransitionModifier(
                isVisible: isVisible,
                delay: delay,
                offset: offset,
                reduceMotion: reduceMotion
            )
        )
    }
}
