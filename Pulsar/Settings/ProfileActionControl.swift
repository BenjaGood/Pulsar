//
//  ProfileActionControl.swift
//  Pulsar
//

import SwiftUI

extension View {
    func profileActionControl(
        tint: Color = SettingsMonochromeDesign.primary,
        controlSize: ControlSize = .large
    ) -> some View {
        self
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(controlSize)
            .tint(SettingsMonochromeDesign.primary)
    }
}
