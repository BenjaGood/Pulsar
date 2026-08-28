//
//  NutritionCalculationEditableRow.swift
//  Pulsar
//

import SwiftUI

struct NutritionCalculationEditableRow<ValueContent: View>: View {
    var title: String
    var symbolName: String
    var isActive: Bool
    @ViewBuilder var valueContent: ValueContent

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: NutritionCalculationDesign.rowSpacing) {
                        NutritionCalculationSymbolBadge(symbolName: symbolName)
                        titleLabel
                    }

                    valueContent
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack(spacing: NutritionCalculationDesign.rowSpacing) {
                    NutritionCalculationSymbolBadge(symbolName: symbolName)
                    titleLabel
                    Spacer(minLength: 10)
                    valueContent
                }
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background(
            NutritionDesign.primaryText.opacity(isActive ? 0.026 : 0),
            in: .rect(cornerRadius: 14)
        )
        .scaleEffect(isActive && !reduceMotion ? 0.995 : 1)
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.12)
                : .spring(response: 0.30, dampingFraction: 0.88),
            value: isActive
        )
    }

    private var titleLabel: some View {
        Text(title)
            .pulsarTextStyle(.label)
            .foregroundStyle(NutritionDesign.primaryText)
    }
}
