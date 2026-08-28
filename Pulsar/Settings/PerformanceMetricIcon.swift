//
//  PerformanceMetricIcon.swift
//  Pulsar
//

import SwiftUI

struct PerformanceMetricIcon: View {
    var symbol: String
    var tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.title3)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(SettingsMonochromeDesign.primary)
            .frame(
                width: PerformanceSettingsDesign.iconSize,
                height: PerformanceSettingsDesign.iconSize
            )
            .accessibilityHidden(true)
    }
}
