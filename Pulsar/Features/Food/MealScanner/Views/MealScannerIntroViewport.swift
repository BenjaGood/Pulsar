import SwiftUI

struct MealScannerIntroViewport: View {
    var isLiDARReady: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: MealScannerIntroDesign.viewportCornerRadius)
                .fill(.white.opacity(reduceTransparency ? 0.88 : 0.035))

            Canvas { context, size in
                let spacing: CGFloat = 24
                var x = spacing
                while x < size.width {
                    var y = spacing
                    while y < size.height {
                        let dot = Path(ellipseIn: CGRect(x: x, y: y, width: 1.4, height: 1.4))
                        context.fill(dot, with: .color(MealScannerIntroDesign.ink.opacity(0.055)))
                        y += spacing
                    }
                    x += spacing
                }
            }
            .padding(18)
            .accessibilityHidden(true)

            MealScannerIdleReticleView(isLiDARReady: isLiDARReady)
                .padding(26)

            Image(systemName: "camera")
                .font(.system(size: 29, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(MealScannerIntroDesign.ink.opacity(0.86))
                .frame(width: 72, height: 72)
                .pulsarLiquidGlass(cornerRadius: 36, isClear: true)
                .accessibilityHidden(true)

            RoundedRectangle(cornerRadius: MealScannerIntroDesign.viewportCornerRadius)
                .strokeBorder(.white.opacity(0.74), lineWidth: 0.8)
                .overlay {
                    RoundedRectangle(cornerRadius: MealScannerIntroDesign.viewportCornerRadius - 2)
                        .strokeBorder(MealScannerIntroDesign.ink.opacity(0.045), lineWidth: 0.6)
                        .padding(2)
                }
                .allowsHitTesting(false)
        }
        .pulsarLiquidGlass(
            cornerRadius: MealScannerIntroDesign.viewportCornerRadius,
            tint: .white.opacity(0.06),
            isClear: true
        )
        .shadow(color: .black.opacity(0.055), radius: 18, y: 9)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Meal scanner viewport")
        .accessibilityHint("Position the full plate inside the corner guides before starting")
    }
}
