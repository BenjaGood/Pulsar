import SwiftUI

struct StrainDetailsHeader: View {
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 46.0

    var dateSubtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Strain")
                .font(.system(size: titleSize, weight: .regular, design: .serif))
                .accessibilityAddTraits(.isHeader)

            Text(dateSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
    }
}
