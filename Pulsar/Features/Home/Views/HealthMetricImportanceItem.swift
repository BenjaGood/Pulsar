//
//  HealthMetricImportanceItem.swift
//  Pulsar
//

import SwiftUI

struct HealthMetricImportanceItem: View {
    var highlight: HealthMetricEducation.Highlight
    var accent: Color
    var isHorizontal: Bool

    var body: some View {
        Group {
            if isHorizontal {
                HStack(alignment: .top, spacing: 10) {
                    icon
                    copy
                }
            } else {
                VStack(spacing: 8) {
                    icon
                    copy
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.horizontal, isHorizontal ? 0 : 2)
        .accessibilityElement(children: .combine)
    }

    private var icon: some View {
        Image(systemName: highlight.symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(accent)
            .frame(width: 38, height: 38)
            .background(accent.opacity(0.07), in: Circle())
            .accessibilityHidden(true)
    }

    private var copy: some View {
        VStack(alignment: isHorizontal ? .leading : .center, spacing: 4) {
            Text(highlight.title)
                .font(.system(.caption, design: .default, weight: .bold))
                .foregroundStyle(HealthMetricEducationDesign.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)

            Text(highlight.detail)
                .font(.system(.caption, design: .default))
                .foregroundStyle(HealthMetricEducationDesign.secondaryText)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: isHorizontal ? .leading : .center)
    }
}
