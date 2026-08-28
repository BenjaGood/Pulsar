//
//  SettingsMonochromeDesign.swift
//  Pulsar
//

import SwiftUI

enum SettingsMonochromeDesign {
    static let pageBackground = Color(red: 0.985, green: 0.982, blue: 0.975)
    static let surface = Color.white
    static let primary = Color.black
    static let secondary = Color.black.opacity(0.58)
    static let tertiary = Color.black.opacity(0.36)
    static let subtleFill = Color.black.opacity(0.045)
    static let selectedFill = Color.black
    static let border = Color.black.opacity(0.085)
    static let divider = Color.black.opacity(0.075)
    static let shadow = Color.black.opacity(0.045)
    static let disabled = Color.black.opacity(0.32)

    static func selectionAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .smooth(duration: 0.32)
    }
}
