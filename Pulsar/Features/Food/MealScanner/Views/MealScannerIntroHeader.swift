import SwiftUI

struct MealScannerIntroHeader: View {
    var isLiDARReady: Bool
    var isCompact: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            Text("3D Meal Scanner")
                .pulsarTextStyle(.displayLarge)
                .foregroundStyle(MealScannerIntroDesign.ink)
                .multilineTextAlignment(.center)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.76)
                .accessibilityAddTraits(.isHeader)

            Text("LiDAR  ·  IMAGE  ·  AI")
                .font(.caption.weight(.medium))
                .tracking(dynamicTypeSize.isAccessibilitySize ? 2.4 : 4.2)
                .foregroundStyle(MealScannerIntroDesign.tertiaryInk)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.8)
                .padding(.top, isCompact ? 8 : 11)

            HStack(spacing: 9) {
                Circle()
                    .fill(isLiDARReady ? MealScannerIntroDesign.mint : MealScannerIntroDesign.tertiaryInk)
                    .frame(width: 8, height: 8)
                    .shadow(
                        color: isLiDARReady ? MealScannerIntroDesign.mint.opacity(0.38) : .clear,
                        radius: 5
                    )
                    .accessibilityHidden(true)

                Text(isLiDARReady ? "LIDAR READY" : "PHOTO READY")
                    .font(.caption.weight(.medium))
                    .tracking(1.7)
                    .foregroundStyle(MealScannerIntroDesign.secondaryInk)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: isCompact ? 34 : 38)
            .pulsarLiquidGlass(cornerRadius: 19, isClear: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isLiDARReady ? "LiDAR ready" : "Photo scanning ready")
            .padding(.top, isCompact ? 14 : 18)
        }
        .frame(maxWidth: .infinity)
    }
}
