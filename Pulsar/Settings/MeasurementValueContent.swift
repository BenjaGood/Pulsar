//
//  MeasurementValueContent.swift
//  Pulsar
//

import SwiftUI

struct MeasurementValueContent: View {
    var title: String
    var caption: String
    var symbol: String
    var value: String
    var unit: String
    var valueSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label {
                Text(title)
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: symbol)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(SettingsMonochromeDesign.primary)
            }
            .font(.body.bold())

            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: valueSize, weight: .regular, design: .default))
                    .tracking(-0.8)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)

                if !unit.isEmpty {
                    Text(unit)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
