import SwiftUI

struct RecoveryRingView: View {
    var scoreText: String
    var score: Int
    var status: RecoveryStatus

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress = 0.0

    var body: some View {
        ZStack {
            Circle()
                .stroke(RecoveryDetailsDesign.sage.opacity(0.18), lineWidth: 8)

            Circle()
                .trim(from: 0, to: scoreProgress * progress)
                .stroke(
                    LinearGradient(
                        colors: [
                            RecoveryDetailsDesign.wellnessGreen,
                            RecoveryDetailsDesign.emerald,
                            RecoveryDetailsDesign.deepTeal
                        ],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: RecoveryDetailsDesign.emerald.opacity(0.12), radius: 6)

            VStack(spacing: 2) {
                Text(scoreText)
                    .font(.system(.title, design: .default, weight: .light))
                    .monospacedDigit()

                Text("/100")
                    .pulsarTextStyle(.metadata)
                    .foregroundStyle(.secondary)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .padding(8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recovery visualization")
        .accessibilityValue("Score \(scoreText). \(status.label)")
        .task {
            if reduceMotion {
                progress = 1
            } else {
                withAnimation(.smooth(duration: 0.8)) {
                    progress = 1
                }
            }
        }
    }

    private var scoreProgress: Double {
        min(max(Double(score) / 100, 0), 1)
    }
}
