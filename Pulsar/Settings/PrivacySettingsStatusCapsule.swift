import SwiftUI

struct PrivacySettingsStatusCapsule: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(minHeight: 28)
            .background(SettingsMonochromeDesign.subtleFill, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(SettingsMonochromeDesign.border, lineWidth: 0.7)
            }
    }
}
