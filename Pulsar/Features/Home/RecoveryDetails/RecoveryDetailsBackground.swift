import SwiftUI

struct RecoveryDetailsBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            baseColor

            RadialGradient(
                colors: [
                    RecoveryDetailsDesign.mint.opacity(colorScheme == .dark ? 0.10 : 0.34),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 460
            )

            RadialGradient(
                colors: [
                    RecoveryDetailsDesign.sage.opacity(colorScheme == .dark ? 0.07 : 0.035),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 12,
                endRadius: 560
            )
        }
        .ignoresSafeArea()
    }

    private var baseColor: Color {
        colorScheme == .dark
            ? Color(red: 12 / 255, green: 12 / 255, blue: 16 / 255)
            : RecoveryDetailsDesign.pageBackground
    }
}
