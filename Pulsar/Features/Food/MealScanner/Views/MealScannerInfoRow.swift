import SwiftUI

struct MealScannerInfoRow: View {
    var title: String
    var detail: String
    var symbolName: String
    var isCompact: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 17, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(MealScannerIntroDesign.ink)
                .frame(width: 38, height: 38)
                .pulsarLiquidGlass(cornerRadius: 12, isClear: true)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .pulsarTextStyle(.cardTitle)
                    .foregroundStyle(MealScannerIntroDesign.ink)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)

                Text(detail)
                    .pulsarTextStyle(.metadata)
                    .foregroundStyle(MealScannerIntroDesign.secondaryInk)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.78)
                    .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MealScannerIntroDesign.ink.opacity(0.72))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 10 : 0)
        .frame(minHeight: isCompact ? 60 : 68)
        .accessibilityElement(children: .combine)
    }
}
