import SwiftUI

struct PrivacySettingsIcon: View {
    var symbol: String
    var tint: Color
    var size: CGFloat = DataPrivacyDesign.iconSize

    var body: some View {
        Image(systemName: symbol)
            .font(.title3)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(SettingsMonochromeDesign.primary)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
