//
//  HealthConnectionIcon.swift
//  Pulsar
//

import SwiftUI

struct HealthConnectionIcon: View {
    @ScaledMetric(relativeTo: .title) private var iconSize = HealthSettingsDesign.connectionIconSize
    @ScaledMetric(relativeTo: .title) private var heartSize: CGFloat = 36
    var body: some View {
        Image(systemName: "heart")
            .font(.system(size: heartSize))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(SettingsMonochromeDesign.primary)
            .frame(width: iconSize, height: iconSize)
            .background(SettingsMonochromeDesign.subtleFill, in: .rect(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .stroke(SettingsMonochromeDesign.border, lineWidth: 0.75)
            }
            .shadow(color: SettingsMonochromeDesign.shadow, radius: 14, y: 7)
        .accessibilityHidden(true)
    }
}
