//
//  GymSettingsDesign.swift
//  Pulsar
//

import SwiftUI

enum GymSettingsDesign {
    static let accent = SettingsMonochromeDesign.primary
    static let horizontalPadding: CGFloat = 24
    static let sectionSpacing: CGFloat = 26
    static let cardCornerRadius: CGFloat = 30
    static let cardPadding: CGFloat = 22
    static let rowCornerRadius: CGFloat = 22
    static let maximumContentWidth: CGFloat = 680

    static let iconGradient = LinearGradient(
        colors: [
            Color.black.opacity(0.035),
            Color.black.opacity(0.085)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func selectionAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion
            ? nil
            : .smooth(duration: 0.32)
    }
}
