import SwiftUI

struct SleepDetailsBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            baseColor

            RadialGradient(
                colors: [
                    SleepDetailsDesign.deep.opacity(colorScheme == .dark ? 0.12 : 0.07),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 12,
                endRadius: 360
            )

            RadialGradient(
                colors: [
                    SleepDetailsDesign.core.opacity(colorScheme == .dark ? 0.07 : 0.035),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 8,
                endRadius: 440
            )
        }
        .ignoresSafeArea()
    }

    private var baseColor: Color {
        colorScheme == .dark
            ? Color(red: 12 / 255, green: 12 / 255, blue: 16 / 255)
            : SleepDetailsDesign.pageBackground
    }
}
