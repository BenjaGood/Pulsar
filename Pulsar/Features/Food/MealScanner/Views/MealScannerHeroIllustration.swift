//
//  MealScannerHeroIllustration.swift
//  Pulsar
//

import SwiftUI

struct MealScannerHeroIllustration: View {
    var body: some View {
        Image(decorative: "MealScanner3DIcon")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .scaleEffect(1.14)
            .frame(width: 98, height: 98)
            .clipShape(Circle(), style: FillStyle(antialiased: true))
    }
}

#Preview {
    MealScannerHeroIllustration()
        .frame(width: 120, height: 110)
        .padding()
        .background(NutritionDesign.pageBackground)
}
