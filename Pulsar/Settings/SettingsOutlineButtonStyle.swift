//
//  SettingsOutlineButtonStyle.swift
//  Pulsar
//

import SwiftUI

struct SettingsOutlineButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .background(
                SettingsMonochromeDesign.surface.opacity(configuration.isPressed ? 0.82 : 1),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(SettingsMonochromeDesign.border, lineWidth: 0.75)
            }
            .shadow(color: SettingsMonochromeDesign.shadow, radius: 8, y: 3)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.22),
                value: configuration.isPressed
            )
    }
}
