import SwiftUI

struct SleepDetailsStateView: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(.largeTitle, design: .default, weight: .light))
                .foregroundStyle(SleepDetailsDesign.deep)

            Text(title)
                .pulsarTextStyle(.sectionHeader)
                .multilineTextAlignment(.center)

            Text(message)
                .pulsarTextStyle(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 300)
        .sleepCardSurface()
    }
}
