//
//  MeasurementsDesign.swift
//  Pulsar
//

import SwiftUI

enum MeasurementsDesign {
    static let accent = SettingsMonochromeDesign.primary
    static let background = SettingsMonochromeDesign.pageBackground
    static let horizontalPadding: CGFloat = 18
    static let cardCornerRadius: CGFloat = 24
    static let sectionSpacing: CGFloat = 20
    static let spring = Animation.smooth(duration: 0.32)
}

extension View {
    func measurementsCardSurface() -> some View {
        let shape = RoundedRectangle(cornerRadius: MeasurementsDesign.cardCornerRadius)

        return self
            .background(SettingsMonochromeDesign.surface, in: shape)
            .overlay {
                shape
                    .stroke(SettingsMonochromeDesign.border, lineWidth: 0.7)
            }
            .shadow(color: SettingsMonochromeDesign.shadow, radius: 12, y: 5)
    }
}
