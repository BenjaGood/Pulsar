//
//  NutritionCalculationScreenHeader.swift
//  Pulsar
//

import SwiftUI

struct NutritionCalculationScreenHeader: View {
    var title: String
    var subtitle: String? = nil
    var canMoveBack: Bool
    var usesCompactSpacing = false
    var onBack: () -> Void
    var onClose: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: usesCompactSpacing ? 6 : 10) {
            Capsule()
                .fill(.black.opacity(0.14))
                .frame(width: 36, height: 5)
                .accessibilityHidden(true)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    controls
                    titleLabel
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            } else {
                ZStack {
                    titleLabel
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    controls
                }
                .frame(maxWidth: .infinity, minHeight: usesCompactSpacing ? 44 : 48)
            }

            if let subtitle {
                Text(subtitle)
                    .pulsarTextStyle(.metadata)
                    .foregroundStyle(NutritionDesign.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, usesCompactSpacing ? 0 : 1)
                    .accessibilitySortPriority(0)
            }
        }
    }

    private var titleLabel: some View {
        Text(title)
            .pulsarTextStyle(.displayMedium)
            .foregroundStyle(NutritionDesign.primaryText)
            .accessibilityAddTraits(.isHeader)
    }

    private var controls: some View {
        HStack {
            if canMoveBack {
                NutritionCalculationHeaderButton(
                    title: "Back",
                    symbolName: "chevron.left",
                    action: onBack
                )
            } else {
                Color.clear
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }

            Spacer(minLength: 72)

            NutritionCalculationHeaderButton(
                title: "Close",
                symbolName: "xmark",
                action: onClose
            )
        }
    }
}
