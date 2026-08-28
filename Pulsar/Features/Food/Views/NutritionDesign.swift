//
//  NutritionDesign.swift
//  Pulsar
//

import SwiftUI

enum NutritionDesign {
    static let cardCornerRadius = PulsarTabLayout.primaryCardCornerRadius

    static var pageBackground: LinearGradient { PulsarTabPalette.pageBackground }
    static let cardBackground = PulsarTabPalette.cardBackground
    static let primaryText = PulsarTabPalette.primaryText
    static let secondaryText = PulsarTabPalette.secondaryText
    static let tertiaryText = PulsarTabPalette.tertiaryText
    static let separator = PulsarTabPalette.separator
    static let shadowColor = PulsarTabPalette.shadowColor
    static let track = PulsarTabPalette.inactive

    static let protein = Color(red: 0.39, green: 0.61, blue: 0.28)
    static let carbohydrates = Color(red: 0.28, green: 0.53, blue: 0.88)
    static let fat = Color(red: 0.92, green: 0.53, blue: 0.12)
    static let calorie = PulsarTabPalette.active
}

extension View {
    func nutritionCardSurface(cornerRadius: CGFloat = NutritionDesign.cardCornerRadius) -> some View {
        pulsarFitnessMonochromeSurface(
            cornerRadius: cornerRadius,
            shadowOpacity: PulsarTabLayout.primaryCardShadowOpacity
        )
    }
}
