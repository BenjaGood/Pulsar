import SwiftUI

struct RecoveryDetailsStateView: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .foregroundStyle(RecoveryDetailsDesign.strainBlue)
                .accessibilityHidden(true)

            Text(title)
                .pulsarTextStyle(.sectionHeader)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text(message)
                .pulsarTextStyle(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 300)
        .recoveryCardSurface()
    }
}
