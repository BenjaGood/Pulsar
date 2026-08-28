//
//  MeasurementEditorCard.swift
//  Pulsar
//

import SwiftUI

struct MeasurementEditorCard: View {
    @Binding var heightCentimeters: Double
    @Binding var weightKilograms: Double
    var units: UnitPreference

    var body: some View {
        VStack(spacing: 0) {
            MeasurementEditorRow(
                title: "Height",
                caption: "Current",
                symbol: "figure.stand",
                value: heightValue,
                unit: heightUnit,
                canDecrement: heightCentimeters > 100,
                canIncrement: heightCentimeters < 230,
                decrement: decrementHeight,
                increment: incrementHeight
            )

            Divider()
                .overlay(Color.black.opacity(0.025))
                .padding(.horizontal, 18)

            MeasurementEditorRow(
                title: "Weight",
                caption: "Current",
                symbol: "scalemass",
                value: weightValue,
                unit: weightUnit,
                canDecrement: weightKilograms > 35,
                canIncrement: weightKilograms < 220,
                decrement: decrementWeight,
                increment: incrementWeight
            )
        }
        .measurementsCardSurface()
        .sensoryFeedback(.selection, trigger: heightCentimeters)
        .sensoryFeedback(.selection, trigger: weightKilograms)
    }

    private var heightValue: String {
        guard units == .imperial else {
            return heightCentimeters.formatted(.number.precision(.fractionLength(0)))
        }

        let inches = Int((heightCentimeters / 2.54).rounded())
        return "\(inches / 12)′ \(inches % 12)″"
    }

    private var heightUnit: String {
        units == .imperial ? "" : "cm"
    }

    private var weightValue: String {
        if units == .imperial {
            return (weightKilograms * 2.20462).formatted(.number.precision(.fractionLength(0)))
        }

        return weightKilograms.formatted(.number.precision(.fractionLength(1)))
    }

    private var weightUnit: String {
        units == .imperial ? "lb" : "kg"
    }

    private func decrementHeight() {
        heightCentimeters = max(100, heightCentimeters - 1)
    }

    private func incrementHeight() {
        heightCentimeters = min(230, heightCentimeters + 1)
    }

    private func decrementWeight() {
        weightKilograms = max(35, weightKilograms - 0.5)
    }

    private func incrementWeight() {
        weightKilograms = min(220, weightKilograms + 0.5)
    }
}
