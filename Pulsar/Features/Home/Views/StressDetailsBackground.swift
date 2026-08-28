import SwiftUI

struct StressDetailsBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        baseColor.ignoresSafeArea()
    }

    private var baseColor: Color {
        colorScheme == .dark
            ? Color(red: 12 / 255, green: 12 / 255, blue: 15 / 255)
            : StressDetailsDesign.pageBackground
    }
}
