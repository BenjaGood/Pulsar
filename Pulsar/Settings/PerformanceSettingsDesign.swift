//
//  PerformanceSettingsDesign.swift
//  Pulsar
//

import SwiftUI

enum PerformanceSettingsDesign {
    static let horizontalPadding: CGFloat = 20
    static let cardCornerRadius: CGFloat = 28
    static let sectionSpacing: CGFloat = 30
    static let rowHorizontalPadding: CGFloat = 16
    static let rowVerticalPadding: CGFloat = 18
    static let iconSize: CGFloat = 44
}

extension View {
    func performanceSectionLabel() -> some View {
        self
            .font(.footnote)
            .tracking(1.15)
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }

    func performanceCardSurface() -> some View {
        let shape = RoundedRectangle(cornerRadius: PerformanceSettingsDesign.cardCornerRadius)

        return self
            .background(SettingsMonochromeDesign.surface, in: shape)
            .overlay {
                shape
                    .stroke(SettingsMonochromeDesign.border, lineWidth: 0.75)
            }
            .shadow(color: SettingsMonochromeDesign.shadow, radius: 14, y: 6)
    }
}
