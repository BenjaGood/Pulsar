import SwiftUI

struct StrainGaugeBoundary: View {
    var position: CGFloat
    var color = Color.primary.opacity(0.28)
    var width = 2.0
    var height = 14.0

    var body: some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: height)
            .offset(x: max(0, position - (width / 2)))
            .accessibilityHidden(true)
    }
}
