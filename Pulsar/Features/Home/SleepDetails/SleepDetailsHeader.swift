import SwiftUI

struct SleepDetailsHeader: View {
    var dateSubtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sleep")
                .pulsarTextStyle(.displayLarge)
                .accessibilityAddTraits(.isHeader)

            Text(dateSubtitle)
                .pulsarTextStyle(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}
