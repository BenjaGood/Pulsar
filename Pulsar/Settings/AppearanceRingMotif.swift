//
//  AppearanceRingMotif.swift
//  Pulsar
//

import SwiftUI

struct AppearanceRingMotif: View {
    var diameter: CGFloat
    var spacing: CGFloat

    var body: some View {
        HStack(spacing: spacing) {
            Circle()
                .stroke(Color.black.opacity(0.34), lineWidth: 1.8)
                .frame(width: diameter, height: diameter)

            Circle()
                .stroke(Color.black.opacity(0.60), lineWidth: 1.8)
                .frame(width: diameter, height: diameter)

            Circle()
                .stroke(Color.black.opacity(0.86), lineWidth: 1.8)
                .frame(width: diameter, height: diameter)
        }
    }
}
