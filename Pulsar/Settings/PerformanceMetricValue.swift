//
//  PerformanceMetricValue.swift
//  Pulsar
//

import SwiftUI

struct PerformanceMetricValue: View {
    var value: Double
    var unit: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value, format: .number.precision(.fractionLength(0)))
                .font(.title2)
                .monospacedDigit()
                .foregroundStyle(.primary)

            Text(unit)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 44, alignment: .trailing)
        .accessibilityElement(children: .combine)
    }
}
