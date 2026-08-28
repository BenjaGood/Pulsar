//
//  PerformanceGlassStepper.swift
//  Pulsar
//

import SwiftUI

struct PerformanceGlassStepper: View {
    var label: String
    @Binding var value: Double
    var range: ClosedRange<Double>

    var body: some View {
        HStack(spacing: 6) {
            Button("Decrease \(label)", systemImage: "minus", action: decrement)
                .labelStyle(.iconOnly)
                .buttonStyle(.glass(.clear))
                .buttonBorderShape(.circle)
                .controlSize(.regular)
                .tint(.primary)
                .frame(minWidth: 44, minHeight: 44)
                .disabled(value <= range.lowerBound)

            Button("Increase \(label)", systemImage: "plus", action: increment)
                .labelStyle(.iconOnly)
                .buttonStyle(.glass(.clear))
                .buttonBorderShape(.circle)
                .controlSize(.regular)
                .tint(.primary)
                .frame(minWidth: 44, minHeight: 44)
                .disabled(value >= range.upperBound)
        }
        .sensoryFeedback(.selection, trigger: value)
    }

    private func decrement() {
        value = max(range.lowerBound, value - 1)
    }

    private func increment() {
        value = min(range.upperBound, value + 1)
    }
}
