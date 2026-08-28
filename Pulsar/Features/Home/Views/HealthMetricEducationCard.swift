//
//  HealthMetricEducationCard.swift
//  Pulsar
//

import SwiftUI

struct HealthMetricEducationCard<Content: View>: View {
    var title: String
    var symbol: String
    var accent: Color
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 38, height: 38)
                    .background(accent.opacity(0.07), in: Circle())
                    .accessibilityHidden(true)

                Text(title)
                    .font(.system(.headline, design: .default, weight: .bold))
                    .foregroundStyle(HealthMetricEducationDesign.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            reduceTransparency ? Color.white : Color.white.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 24)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.black.opacity(0.055), lineWidth: 0.75)
        }
        .shadow(color: Color.black.opacity(0.04), radius: 12, y: 6)
        .pulsarLiquidGlass(cornerRadius: 24, isClear: true)
    }
}
