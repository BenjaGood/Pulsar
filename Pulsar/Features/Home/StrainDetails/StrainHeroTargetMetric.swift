import SwiftUI

struct StrainHeroTargetMetric: View {
    @ScaledMetric(relativeTo: .title) private var targetSize = 26.0

    var targetText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TARGET RANGE")
                .font(.caption)
                .tracking(0.7)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            Text(targetText)
                .font(.system(size: targetSize, weight: .regular, design: .serif))
                .monospacedDigit()
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            targetText == "--"
                ? "Target range unavailable"
                : "Target range \(targetText)"
        )
    }
}
