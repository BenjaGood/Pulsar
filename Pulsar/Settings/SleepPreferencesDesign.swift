import SwiftUI

enum SleepPreferencesDesign {
    static let horizontalPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 24
    static let cardCornerRadius: CGFloat = 30
    static let cardPadding: CGFloat = 20
    static let rowHorizontalPadding: CGFloat = 18
    static let rowVerticalPadding: CGFloat = 15
    static let iconSize: CGFloat = 44

    static let selectedGradient = LinearGradient(
        colors: [
            Color.black,
            Color.black.opacity(0.82)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
}

extension View {
    func sleepSectionLabel() -> some View {
        self
            .font(.footnote)
            .tracking(1.05)
            .foregroundStyle(.secondary)
    }

    func sleepPreferencesCardSurface() -> some View {
        let shape = RoundedRectangle(cornerRadius: SleepPreferencesDesign.cardCornerRadius)

        return self
            .background(SettingsMonochromeDesign.surface, in: shape)
            .overlay {
                shape
                    .stroke(SettingsMonochromeDesign.border, lineWidth: 0.75)
            }
            .shadow(color: SettingsMonochromeDesign.shadow, radius: 18, y: 8)
    }
}
