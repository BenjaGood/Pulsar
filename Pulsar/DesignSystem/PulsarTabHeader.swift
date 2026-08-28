//
//  PulsarTabHeader.swift
//  Pulsar
//

import SwiftUI

struct PulsarTabHeader: View {
    var systemImage: String
    var title: String
    var subtitle: String
    var onAdd: (() -> Void)?
    var addAccessibilityLabel: String

    private var primaryTextOverride: Color?
    private var secondaryTextOverride: Color?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var textBlockMinimumHeight = 62.0

    init(
        systemImage: String,
        title: String,
        subtitle: String,
        primaryText: Color? = nil,
        secondaryText: Color? = nil,
        onAdd: (() -> Void)? = nil,
        addAccessibilityLabel: String = "Add"
    ) {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.primaryTextOverride = primaryText
        self.secondaryTextOverride = secondaryText
        self.onAdd = onAdd
        self.addAccessibilityLabel = addAccessibilityLabel
    }

    var body: some View {
        HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(primaryText)
                .frame(width: 32, height: 32)
                .frame(width: 52, height: 52)
                .background(PulsarCircularGlassSurface(cornerRadius: 26))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .pulsarTextStyle(.displayLarge)
                    .foregroundStyle(primaryText)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.72)

                Text(subtitle)
                    .pulsarTextStyle(.label)
                    .foregroundStyle(secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: textBlockMinimumHeight,
                alignment: .leading
            )

            if let onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(primaryText)
                        .frame(width: 52, height: 52)
                        .background(PulsarCircularGlassSurface(cornerRadius: 26))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(addAccessibilityLabel)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
    }

    private var primaryText: Color {
        primaryTextOverride ?? (colorScheme == .dark ? .white.opacity(0.96) : Color(red: 0.07, green: 0.10, blue: 0.14))
    }

    private var secondaryText: Color {
        secondaryTextOverride ?? (colorScheme == .dark ? .white.opacity(0.62) : Color(red: 0.36, green: 0.40, blue: 0.48))
    }
}
