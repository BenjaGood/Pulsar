import SwiftUI

struct PrivacySettingsSection<Content: View>: View {
    var title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.footnote)
                .bold()
                .tracking(1.05)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content
            }
            .buttonStyle(.plain)
            .dataPrivacyCardSurface()
        }
    }
}
