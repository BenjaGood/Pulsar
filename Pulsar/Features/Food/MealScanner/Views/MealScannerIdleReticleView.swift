import SwiftUI

struct MealScannerIdleReticleView: View {
    var isLiDARReady: Bool

    var body: some View {
        VStack {
            HStack {
                corner
                Spacer()
                corner.rotationEffect(.degrees(90))
            }
            Spacer()
            HStack {
                corner.rotationEffect(.degrees(-90))
                Spacer()
                corner.rotationEffect(.degrees(180))
            }
        }
        .accessibilityHidden(true)
    }

    private var corner: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 27))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 27, y: 0))
        }
        .stroke(
            isLiDARReady ? MealScannerIntroDesign.mint.opacity(0.72) : MealScannerIntroDesign.tertiaryInk.opacity(0.42),
            style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
        )
        .frame(width: 27, height: 27)
    }
}
