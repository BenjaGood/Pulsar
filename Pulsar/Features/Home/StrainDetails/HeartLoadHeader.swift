import SwiftUI

struct HeartLoadHeader: View {
    @ScaledMetric(relativeTo: .title2) private var titleSize = 25.0

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text("Heart Load")
                    .font(
                        .system(
                            size: titleSize,
                            weight: .regular,
                            design: .serif
                        )
                    )
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                Text("Heart rate throughout the day")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Heart Load")
                    .font(
                        .system(
                            size: titleSize,
                            weight: .regular,
                            design: .serif
                        )
                    )
                    .accessibilityAddTraits(.isHeader)

                Text("Heart rate throughout the day")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
