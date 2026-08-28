import SwiftUI

struct StrainHeroCurrentMetric: View {
    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize = 54.0

    var scoreText: String
    var statusText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("CURRENT STRAIN")
                .font(.caption)
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            Text(scoreText)
                .font(.system(size: scoreSize, weight: .light, design: .serif))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .accessibilityLabel(
                    scoreText == "--"
                        ? "Current strain unavailable"
                        : "Current strain \(scoreText)"
                )

            Text(statusText)
                .font(.caption)
                .foregroundStyle(StrainDetailsDesign.strainOrange)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    StrainDetailsDesign.strainOrange.opacity(0.10),
                    in: Capsule()
                )
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(statusText)
        }
    }
}
