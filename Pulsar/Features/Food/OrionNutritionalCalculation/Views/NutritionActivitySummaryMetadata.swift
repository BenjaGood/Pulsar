//
//  NutritionActivitySummaryMetadata.swift
//  Pulsar
//

import SwiftUI

struct NutritionActivitySummaryMetadata: View {
    var validEnergyDayCount: Int
    var workoutCount: Int
    var density: NutritionActivityLayoutDensity = .regular

    var body: some View {
        HStack(spacing: density.isVeryCompactHeight ? 8 : (density.isCompactHeight ? 12 : 18)) {
            Label(
                "\(validEnergyDayCount) Valid Energy Days",
                systemImage: "calendar"
            )
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(.black.opacity(0.07))
                .frame(width: 0.5, height: density.isCompactHeight ? 16 : 20)
                .accessibilityHidden(true)

            Label(
                "\(workoutCount) Workouts",
                systemImage: "dumbbell"
            )
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: .infinity)
        }
        .font(.footnote)
        .foregroundStyle(NutritionDesign.secondaryText)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
