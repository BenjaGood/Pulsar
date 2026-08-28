import SwiftUI

struct PrivacySummaryCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                standardLayout
            }
        }
        .padding(.horizontal, DataPrivacyDesign.cardHorizontalPadding)
        .padding(.vertical, DataPrivacyDesign.cardVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dataPrivacyCardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Your Data is Secure. Pulsar uses Apple Health as the central health data source. Local profile values are stored on this device for now."
        )
    }

    private var standardLayout: some View {
        HStack(spacing: 12) {
            PrivacySettingsIcon(
                symbol: "checkmark.shield",
                tint: DataPrivacyDesign.violet,
                size: 44
            )

            copy
        }
    }

    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            PrivacySettingsIcon(
                symbol: "checkmark.shield",
                tint: DataPrivacyDesign.violet,
                size: 44
            )

            copy
        }
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Your Data is Secure")
                .font(.subheadline)
                .bold()
                .foregroundStyle(.primary)

            Text("Pulsar uses Apple Health as the central health data source. Local profile values are stored on this device for now.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
