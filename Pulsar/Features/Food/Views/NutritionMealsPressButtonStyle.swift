//
//  NutritionMealsPressButtonStyle.swift
//  Pulsar
//

import SwiftUI

struct NutritionMealsPressButtonStyle: ButtonStyle {
    var flashesRed = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(
                flashesRed && configuration.isPressed
                    ? Color.red
                    : NutritionDesign.primaryText
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.12)
                    : .spring(response: 0.28, dampingFraction: 0.84),
                value: configuration.isPressed
            )
    }
}
