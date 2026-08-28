//
//  PerformanceHeartMetricRow.swift
//  Pulsar
//

import SwiftUI

struct PerformanceHeartMetricRow: View {
    var title: String
    var subtitle: String? = nil
    var symbol: String
    var tint: Color
    @Binding var value: Double
    var unit: String
    var range: ClosedRange<Double>

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        PerformanceMetricIcon(symbol: symbol, tint: tint)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .font(.headline)
                                .foregroundStyle(.primary)

                            if let subtitle {
                                Text(subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer(minLength: 8)

                        PerformanceMetricValue(value: value, unit: unit)
                    }

                    PerformanceGlassStepper(
                        label: title,
                        value: $value,
                        range: range
                    )
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack(spacing: 10) {
                    PerformanceMetricIcon(symbol: symbol, tint: tint)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.subheadline)
                            .bold()
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        if let subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                        }
                    }

                    Spacer(minLength: 0)

                    PerformanceMetricValue(value: value, unit: unit)

                    PerformanceGlassStepper(
                        label: title,
                        value: $value,
                        range: range
                    )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, PerformanceSettingsDesign.rowVerticalPadding)
        .frame(minHeight: 112)
    }
}
