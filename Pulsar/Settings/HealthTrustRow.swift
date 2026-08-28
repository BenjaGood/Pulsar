//
//  HealthTrustRow.swift
//  Pulsar
//

import SwiftUI

struct HealthTrustRow: View {
    let symbol: String
    let title: String
    let description: String

    @ScaledMetric(relativeTo: .subheadline) private var symbolSize: CGFloat = 18
    @ScaledMetric(relativeTo: .subheadline) private var checkmarkSize: CGFloat = 20

    var body: some View {
        HStack(alignment: .top, spacing: HealthSettingsDesign.rowSpacing) {
            Image(systemName: symbol)
                .font(.system(size: symbolSize))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .bold()

                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Image(systemName: "checkmark.circle")
                .font(.system(size: checkmarkSize))
                .foregroundStyle(SettingsMonochromeDesign.primary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, HealthSettingsDesign.rowVerticalPadding)
        .accessibilityElement(children: .combine)
    }
}
