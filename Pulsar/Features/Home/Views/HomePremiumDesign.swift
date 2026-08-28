//
//  HomePremiumDesign.swift
//  Pulsar
//

import SwiftUI

enum HomePremiumDesign {
    enum Layout {
        static let screenMargin: CGFloat = 22
        static let sectionSpacing: CGFloat = 16
        static let cardSpacing: CGFloat = 10
        static let cardContentPadding: CGFloat = 14
        static let headerTopPadding: CGFloat = 12
        static let identityToDateSpacing: CGFloat = 24
        static let dateNavigatorBottomInset: CGFloat = 24
        static let dateNavigatorMinWidth: CGFloat = 220
        static let dateNavigatorMaxWidth: CGFloat = 248
        static let dateNavigatorChevronWidth: CGFloat = 44
        static let identitySideInset: CGFloat = 56
    }

    enum Radius {
        static let metricCard: CGFloat = 28
        static let stressCard: CGFloat = 26
        static let insightCard: CGFloat = 18
    }

    static let background = Color(red: 0.968, green: 0.973, blue: 0.982)
    static let surface = Color.white
    static let primaryText = Color(red: 0.055, green: 0.070, blue: 0.105)
    static let secondaryText = Color(red: 0.315, green: 0.345, blue: 0.410)
    static let tertiaryText = Color(red: 0.470, green: 0.500, blue: 0.565)
    static let accent = Color(red: 0.035, green: 0.535, blue: 0.565)
    static let stressTeal = Color(red: 0.020, green: 0.585, blue: 0.615)
    static let border = Color(red: 0.075, green: 0.120, blue: 0.180).opacity(0.095)
    static let shadow = Color(red: 0.075, green: 0.105, blue: 0.165).opacity(0.085)
}
