import SwiftUI

struct StrainDetailsBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            baseColor

            RadialGradient(
                colors: [
                    StrainDetailsDesign.strainOrange.opacity(
                        colorScheme == .dark ? 0.08 : 0.035
                    ),
                    .clear
                ],
                center: .bottomTrailing,
                startRadius: 12,
                endRadius: 440
            )

            RadialGradient(
                colors: [
                    StrainDetailsDesign.restingViolet.opacity(
                        colorScheme == .dark ? 0.07 : 0.025
                    ),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 8,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }

    private var baseColor: Color {
        colorScheme == .dark
            ? Color(red: 0.055, green: 0.050, blue: 0.065)
            : StrainDetailsDesign.pageBackground
    }
}
