import SwiftUI

enum DataPrivacyDesign {
    static let horizontalPadding: CGFloat = 20
    static let maximumContentWidth: CGFloat = 640
    static let cardCornerRadius: CGFloat = 22
    static let cardHorizontalPadding: CGFloat = 16
    static let cardVerticalPadding: CGFloat = 12
    static let iconSize: CGFloat = 44
    static let rowMinimumHeight: CGFloat = 68

    static let violet = SettingsMonochromeDesign.primary

    static var pageBackground: Color {
        SettingsMonochromeDesign.pageBackground
    }

    static var cardBackground: Color {
        SettingsMonochromeDesign.surface
    }
}

extension View {
    func dataPrivacyCardSurface() -> some View {
        self
            .background(
                DataPrivacyDesign.cardBackground,
                in: .rect(cornerRadius: DataPrivacyDesign.cardCornerRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DataPrivacyDesign.cardCornerRadius)
                    .stroke(SettingsMonochromeDesign.border, lineWidth: 0.75)
            }
            .shadow(
                color: SettingsMonochromeDesign.shadow,
                radius: 16,
                y: 6
            )
    }
}
