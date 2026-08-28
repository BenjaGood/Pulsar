//
//  PerformanceTrainingRow.swift
//  Pulsar
//

import SwiftUI

struct PerformanceTrainingRow: View {
    var title: String
    var value: String
    var symbol: String
    var tint: Color

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        PerformanceMetricIcon(symbol: symbol, tint: tint)

                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .bold()
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }

                    Text(value)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.leading, PerformanceSettingsDesign.iconSize + 14)
                }
            } else {
                HStack(spacing: 14) {
                    PerformanceMetricIcon(symbol: symbol, tint: tint)

                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 12)

                    Text(value)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .bold()
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.horizontal, PerformanceSettingsDesign.rowHorizontalPadding)
        .padding(.vertical, 14)
        .frame(minHeight: 76)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
