//
//  HealthMetricDataItemView.swift
//  Pulsar
//

import SwiftUI

struct HealthMetricDataItemView: View {
    var item: HealthMetricDataItem
    var accent: Color

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: item.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(accent)
                .frame(height: 18)
                .accessibilityHidden(true)

            Text(item.label)
                .font(.system(.caption, design: .default, weight: .medium))
                .foregroundStyle(HealthMetricEducationDesign.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(item.value)
                .font(.system(.caption, design: .default, weight: .bold))
                .foregroundStyle(HealthMetricEducationDesign.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.74)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .top)
        .background(HealthMetricEducationDesign.dataTileBackground, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}
