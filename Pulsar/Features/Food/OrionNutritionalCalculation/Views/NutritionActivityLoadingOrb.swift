//
//  NutritionActivityLoadingOrb.swift
//  Pulsar
//

import SwiftUI

struct NutritionActivityLoadingOrb: View {
    private let contentInset: CGFloat = 18

    @ScaledMetric(relativeTo: .title2) private var preferredDiameter: CGFloat = 168
    var proposedDiameter: CGFloat? = nil

    private var diameter: CGFloat {
        proposedDiameter ?? min(max(preferredDiameter, 156), 176)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.94))
                .overlay {
                    Circle()
                        .strokeBorder(.black.opacity(0.035), lineWidth: 0.6)
                }
                .shadow(color: .black.opacity(0.045), radius: 18, y: 8)

            NutritionActivityLoadingAnimation()
                .frame(
                    width: diameter - (contentInset * 2),
                    height: diameter - (contentInset * 2)
                )
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}
