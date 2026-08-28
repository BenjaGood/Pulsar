import SwiftUI

struct MealScannerInfoSection: View {
    var isCompact: Bool

    var body: some View {
        VStack(spacing: 0) {
            MealScannerInfoRow(
                title: "Two-phase scan",
                detail: "Photo first, LiDAR mapping second",
                symbolName: "sparkles",
                isCompact: isCompact
            )

            Divider()
                .overlay(MealScannerIntroDesign.ink.opacity(0.055))
                .padding(.leading, 62)

            MealScannerInfoRow(
                title: "Accurate results",
                detail: "AI nutrition estimation",
                symbolName: "viewfinder",
                isCompact: isCompact
            )

            Divider()
                .overlay(MealScannerIntroDesign.ink.opacity(0.055))
                .padding(.leading, 62)

            MealScannerInfoRow(
                title: "Private & secure",
                detail: "Your data stays on device",
                symbolName: "checkmark.shield",
                isCompact: isCompact
            )
        }
        .pulsarLiquidGlass(
            cornerRadius: MealScannerIntroDesign.sectionCornerRadius,
            tint: .white.opacity(0.045)
        )
        .accessibilityElement(children: .contain)
    }
}
