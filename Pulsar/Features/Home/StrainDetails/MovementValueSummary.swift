import SwiftUI

struct MovementValueSummary: View {
    @ScaledMetric(relativeTo: .largeTitle) private var stepValueSize = 31.0

    var steps: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "shoeprints.fill")
                .font(.title2)
                .foregroundStyle(StrainDetailsDesign.movementTeal)
                .frame(width: 30)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Movement")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(steps.formatted())
                        .font(
                            .system(
                                size: stepValueSize,
                                weight: .regular,
                                design: .serif
                            )
                        )
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text("steps")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
