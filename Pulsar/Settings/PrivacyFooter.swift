import SwiftUI

struct PrivacyFooter: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                icon
                commitment
                learnMore
            }

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    icon
                    commitment
                }
                learnMore
            }
        }
        .font(.footnote)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var icon: some View {
        Image(systemName: "checkmark.shield")
            .foregroundStyle(DataPrivacyDesign.violet.opacity(0.7))
            .accessibilityHidden(true)
    }

    private var commitment: some View {
        Text("Pulsar is committed to your privacy.")
            .foregroundStyle(.secondary)
    }

    private var learnMore: some View {
        Text("Learn more")
            .foregroundStyle(DataPrivacyDesign.violet)
            .underline()
    }
}
