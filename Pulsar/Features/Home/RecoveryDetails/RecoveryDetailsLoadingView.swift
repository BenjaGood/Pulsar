import SwiftUI

struct RecoveryDetailsLoadingView: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()

            Text("Loading recovery details")
                .pulsarTextStyle(.bodyEmphasis)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .padding(RecoveryDetailsDesign.cardPadding)
        .recoveryCardSurface()
    }
}
