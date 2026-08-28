import SwiftUI

struct StressDetailsHeader: View {
    var dateSubtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Stress")
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .accessibilityAddTraits(.isHeader)

            Text(dateSubtitle)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}
