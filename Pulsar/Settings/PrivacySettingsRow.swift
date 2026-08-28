import SwiftUI

struct PrivacySettingsRow: View {
    var title: String
    var subtitle: String
    var symbol: String
    var tint: Color
    var trailingValue: String? = nil
    var usesStatusCapsule = false

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
        .padding(.vertical, 8)
        .frame(
            minHeight: dynamicTypeSize.isAccessibilitySize
                ? nil
                : DataPrivacyDesign.rowMinimumHeight
        )
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var standardLayout: some View {
        HStack(spacing: 12) {
            PrivacySettingsIcon(symbol: symbol, tint: tint)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    titleText

                    Spacer(minLength: 6)

                    trailingContent
                }

                subtitleText
            }
        }
    }

    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                PrivacySettingsIcon(symbol: symbol, tint: tint)

                Spacer(minLength: 8)

                trailingContent
            }

            copy
        }
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 4) {
            titleText
            subtitleText
        }
    }

    private var titleText: some View {
        Text(title)
            .font(.subheadline)
            .bold()
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var subtitleText: some View {
        Text(subtitle)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var trailingContent: some View {
        HStack(spacing: 9) {
            if let trailingValue {
                if usesStatusCapsule {
                    PrivacySettingsStatusCapsule(text: trailingValue)
                } else {
                    Text(trailingValue)
                        .font(.footnote)
                        .foregroundStyle(DataPrivacyDesign.violet)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .bold()
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }
}
