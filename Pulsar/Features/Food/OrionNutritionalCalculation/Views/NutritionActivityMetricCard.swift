//
//  NutritionActivityMetricCard.swift
//  Pulsar
//

import SwiftUI

struct NutritionActivityMetricCard: View {
    var symbolName: String
    var value: String
    var unit: String? = nil
    var label: String
    var density: NutritionActivityLayoutDensity = .regular

    var body: some View {
        VStack(spacing: density.isVeryCompactHeight ? 6 : (density.isCompactHeight ? 9 : 14)) {
            Image(systemName: symbolName)
                .font(.system(size: density.isVeryCompactHeight ? 16 : (density.isCompactHeight ? 17 : 19), weight: .medium))
                .foregroundStyle(NutritionDesign.primaryText)
                .frame(width: density.metricIconDiameter, height: density.metricIconDiameter)
                .background(.black.opacity(0.028), in: .circle)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(density.isVeryCompactHeight ? .title3 : .title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(NutritionDesign.primaryText)
                    .monospacedDigit()

                if let unit {
                    Text(unit)
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(NutritionDesign.secondaryText)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.68)

            Text(label)
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(NutritionDesign.secondaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.76)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, density.metricVerticalPadding)
        .frame(maxWidth: .infinity)
        .frame(height: density.metricCardHeight)
        .background(.black.opacity(0.014), in: .rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(.black.opacity(0.05), lineWidth: 0.55)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(unit.map { "\(value) \($0)" } ?? value)
    }
}
