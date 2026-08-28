//
//  HealthSettingsDesign.swift
//  Pulsar
//

import SwiftUI

enum HealthSettingsDesign {
    static let horizontalPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 28
    static let cardSpacing: CGFloat = 28
    static let cardHorizontalPadding: CGFloat = 24
    static let cardVerticalPadding: CGFloat = 26
    static let cardCornerRadius: CGFloat = 32
    static let connectionIconSize: CGFloat = 76
    static let statusIndicatorSize: CGFloat = 56
    static let actionButtonMinimumHeight: CGFloat = 58
    static let rowSpacing: CGFloat = 12
    static let rowVerticalPadding: CGFloat = 10
    static let maximumContentWidth: CGFloat = 640
    static let maximumButtonWidth: CGFloat = 480
    static let privacyFooterMaximumWidth: CGFloat = 360

    static var background: Color {
        SettingsMonochromeDesign.pageBackground
    }
}
