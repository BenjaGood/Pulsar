//
//  GymSettingsCardSurfaceModifier.swift
//  Pulsar
//

import SwiftUI

struct GymSettingsCardSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: GymSettingsDesign.cardCornerRadius)

        content
            .background(SettingsMonochromeDesign.surface, in: shape)
            .overlay {
                shape
                    .stroke(SettingsMonochromeDesign.border, lineWidth: 0.75)
            }
            .shadow(color: SettingsMonochromeDesign.shadow, radius: 18, y: 8)
    }
}

extension View {
    func gymSettingsCardSurface() -> some View {
        modifier(GymSettingsCardSurfaceModifier())
    }
}
