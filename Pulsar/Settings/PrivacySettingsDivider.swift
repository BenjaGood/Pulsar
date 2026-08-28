import SwiftUI

struct PrivacySettingsDivider: View {
    var body: some View {
        Divider()
            .overlay(SettingsMonochromeDesign.divider)
            .padding(.leading, 74)
            .padding(.trailing, DataPrivacyDesign.cardHorizontalPadding)
    }
}
