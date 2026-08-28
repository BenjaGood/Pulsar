//
//  MeasurementEditorRow.swift
//  Pulsar
//

import SwiftUI

struct MeasurementEditorRow: View {
    var title: String
    var caption: String
    var symbol: String
    var value: String
    var unit: String
    var canDecrement: Bool
    var canIncrement: Bool
    var decrement: () -> Void
    var increment: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var valueSize: CGFloat = 34

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                MeasurementValueContent(
                    title: title,
                    caption: caption,
                    symbol: symbol,
                    value: value,
                    unit: unit,
                    valueSize: valueSize
                )

                Spacer(minLength: 8)

                MeasurementGlassStepper(
                    label: title,
                    canDecrement: canDecrement,
                    canIncrement: canIncrement,
                    decrement: decrement,
                    increment: increment
                )
            }

            VStack(alignment: .leading, spacing: 14) {
                MeasurementValueContent(
                    title: title,
                    caption: caption,
                    symbol: symbol,
                    value: value,
                    unit: unit,
                    valueSize: valueSize
                )

                MeasurementGlassStepper(
                    label: title,
                    canDecrement: canDecrement,
                    canIncrement: canIncrement,
                    decrement: decrement,
                    increment: increment
                )
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .accessibilityElement(children: .contain)
    }
}
