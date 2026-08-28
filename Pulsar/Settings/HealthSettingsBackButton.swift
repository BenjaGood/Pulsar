//
//  HealthSettingsBackButton.swift
//  Pulsar
//

import SwiftUI

struct HealthSettingsBackButton: View {
    let action: () -> Void

    var body: some View {
        Button("Back", systemImage: "chevron.left", action: action)
            .labelStyle(.iconOnly)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 48, height: 48)
            .background(SettingsMonochromeDesign.surface, in: Circle())
            .overlay {
                Circle()
                    .stroke(SettingsMonochromeDesign.border, lineWidth: 0.75)
            }
            .shadow(color: SettingsMonochromeDesign.shadow, radius: 16, y: 8)
    }
}
