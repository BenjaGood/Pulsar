//
//  MindfulnessDesign.swift
//  Pulsar
//

import SwiftUI

enum MindfulnessDesign {
    static let primaryText = PulsarTabPalette.primaryText
    static let secondaryText = PulsarTabPalette.secondaryText
    static let tertiaryText = PulsarTabPalette.tertiaryText
    static let track = PulsarTabPalette.inactive
    static let separator = PulsarTabPalette.separator
    static let active = PulsarTabPalette.active

    static let primaryCornerRadius: CGFloat = 30
    static let compactCornerRadius: CGFloat = 22
    static let cardPadding: CGFloat = 20

    static let historyCardCornerRadius: CGFloat = 28
    static let historyCardPadding: CGFloat = 16
    static let historyControlSize: CGFloat = 44
    static let historySectionSpacing: CGFloat = 10
}

extension View {
    func mindfulnessCardSurface(
        cornerRadius: CGFloat = MindfulnessDesign.primaryCornerRadius,
        isInteractive: Bool = false,
        shadowOpacity: Double = PulsarTabLayout.primaryCardShadowOpacity
    ) -> some View {
        pulsarFitnessMonochromeSurface(
            cornerRadius: cornerRadius,
            isInteractive: isInteractive,
            shadowOpacity: shadowOpacity
        )
    }

    @ViewBuilder
    func mindfulnessStaticGlassTransition() -> some View {
        if #available(iOS 26.0, *) {
            glassEffectTransition(.identity)
        } else {
            self
        }
    }
}
