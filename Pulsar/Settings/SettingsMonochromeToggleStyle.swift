//
//  SettingsMonochromeToggleStyle.swift
//  Pulsar
//

import SwiftUI

struct SettingsMonochromeToggleStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(SettingsMonochromeDesign.selectionAnimation(reduceMotion: reduceMotion)) {
                configuration.isOn.toggle()
            }
        } label: {
            ZStack {
                Capsule()
                    .fill(
                        configuration.isOn
                            ? Color.black.opacity(0.10)
                            : Color.black.opacity(0.14)
                    )
                    .frame(width: 51, height: 31)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(configuration.isOn ? .black : .white)
                            .overlay {
                                Circle()
                                    .stroke(
                                        configuration.isOn
                                            ? Color.clear
                                            : Color.black.opacity(0.14),
                                        lineWidth: 0.75
                                    )
                            }
                            .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
                            .padding(3)
                    }
            }
            .frame(width: 51)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
