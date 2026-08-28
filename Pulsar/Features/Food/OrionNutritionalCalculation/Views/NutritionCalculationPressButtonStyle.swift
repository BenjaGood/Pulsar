//
//  NutritionCalculationPressButtonStyle.swift
//  Pulsar
//

import SwiftUI

struct NutritionCalculationPressButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.97

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.12)
                    : .spring(response: 0.30, dampingFraction: 0.86),
                value: configuration.isPressed
            )
    }
}
