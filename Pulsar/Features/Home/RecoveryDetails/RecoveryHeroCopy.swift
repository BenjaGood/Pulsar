import SwiftUI

struct RecoveryHeroCopy: View {
    var scoreText: String
    var status: RecoveryStatus
    @ScaledMetric(relativeTo: .largeTitle) private var scoreFontSize = 56.0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(scoreText)
                    .font(.system(size: scoreFontSize, weight: .light, design: .default))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityLabel("Recovery score")
                    .accessibilityValue(scoreText)

                Text("Recovery Score")
                    .pulsarTextStyle(.metadata)
                    .foregroundStyle(.secondary)
            }

            Label {
                Text(status.label)
            } icon: {
                Circle()
                    .fill(RecoveryDetailsDesign.wellnessGreen)
                    .frame(width: 10, height: 10)
            }
            .pulsarTextStyle(.metadata)
            .foregroundStyle(RecoveryDetailsDesign.wellnessGreen)
            .lineLimit(2)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(RecoveryDetailsDesign.mint.opacity(0.72), in: Capsule())
            .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
    }
}
