import SwiftUI

struct SleepDetailsLoadingView: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()

            Text("Loading sleep details")
                .pulsarTextStyle(.cardTitle)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .sleepCardSurface()
    }
}
