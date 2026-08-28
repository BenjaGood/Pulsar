//
//  NutritionActivityLayoutDensity.swift
//  Pulsar
//

import SwiftUI

struct NutritionActivityLayoutDensity {
    let isCompactHeight: Bool
    let isVeryCompactHeight: Bool

    init(availableHeight: CGFloat) {
        isCompactHeight = availableHeight < 790
        isVeryCompactHeight = availableHeight < 680
    }

    static let regular = NutritionActivityLayoutDensity(availableHeight: 900)

    var topPadding: CGFloat { isVeryCompactHeight ? 2 : (isCompactHeight ? 4 : 8) }
    var bottomPadding: CGFloat { isCompactHeight ? 2 : 6 }
    var sectionSpacing: CGFloat { isVeryCompactHeight ? 8 : (isCompactHeight ? 10 : 14) }

    var loadingAnimationHeight: CGFloat { isVeryCompactHeight ? 170 : (isCompactHeight ? 190 : 215) }
    var loadingRippleWidth: CGFloat { isVeryCompactHeight ? 184 : (isCompactHeight ? 210 : 244) }
    var loadingOrbDiameter: CGFloat { isVeryCompactHeight ? 116 : (isCompactHeight ? 132 : 148) }

    var healthCardPadding: CGFloat { isVeryCompactHeight ? 12 : (isCompactHeight ? 15 : 18) }
    var healthContentSpacing: CGFloat { isVeryCompactHeight ? 8 : (isCompactHeight ? 11 : 15) }
    var metricCardHeight: CGFloat { isVeryCompactHeight ? 112 : (isCompactHeight ? 130 : 142) }
    var metricVerticalPadding: CGFloat { isVeryCompactHeight ? 8 : (isCompactHeight ? 10 : 13) }
    var metricIconDiameter: CGFloat { isVeryCompactHeight ? 34 : (isCompactHeight ? 38 : 42) }
    var informationVerticalPadding: CGFloat { isVeryCompactHeight ? 7 : (isCompactHeight ? 8 : 10) }
    var secondaryButtonHeight: CGFloat { isVeryCompactHeight ? 48 : (isCompactHeight ? 50 : 54) }
}
