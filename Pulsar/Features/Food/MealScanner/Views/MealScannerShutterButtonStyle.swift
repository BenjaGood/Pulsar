//
//  MealScannerShutterButtonStyle.swift
//  Pulsar
//

import SwiftUI

struct MealScannerShutterButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.smooth(duration: reduceMotion ? 0 : 0.14), value: configuration.isPressed)
    }
}
