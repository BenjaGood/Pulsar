//
//  StrainCalendarMetricTile.swift
//  Pulsar
//

import SwiftUI

struct StrainCalendarMetricTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.72), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(value)
                    .font(.title3)
                    .bold()
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .background(
            StrainCalendarDesign.metricBackground,
            in: .rect(cornerRadius: StrainCalendarDesign.metricCornerRadius)
        )
        .accessibilityElement(children: .combine)
    }
}
