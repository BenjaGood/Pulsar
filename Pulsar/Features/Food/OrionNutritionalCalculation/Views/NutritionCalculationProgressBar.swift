//
//  NutritionCalculationProgressBar.swift
//  Pulsar
//

import SwiftUI

struct NutritionCalculationProgressBar: View {
    var progress: Double
    var currentStep: Int
    var totalSteps: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(.black.opacity(0.075))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(NutritionDesign.primaryText)
                        .frame(width: proxy.size.width * min(max(progress, 0), 1))
                }
        }
        .frame(height: 3)
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.14)
                : .spring(response: 0.46, dampingFraction: 0.90),
            value: progress
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calculation progress")
        .accessibilityValue("Step \(currentStep) of \(totalSteps)")
    }
}
