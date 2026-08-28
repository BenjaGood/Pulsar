//
//  StrainCalendarSurfaceModifier.swift
//  Pulsar
//

import SwiftUI

struct StrainCalendarSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.thinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.white.opacity(0.56))
                }
            }
            .shadow(color: .black.opacity(0.055), radius: 18, y: 8)
    }
}

extension View {
    func strainCalendarSurface(cornerRadius: CGFloat) -> some View {
        modifier(StrainCalendarSurfaceModifier(cornerRadius: cornerRadius))
    }
}
