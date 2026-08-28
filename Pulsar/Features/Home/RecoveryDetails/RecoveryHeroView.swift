import SwiftUI

struct RecoveryHeroView: View {
    var scoreText: String
    var score: Int
    var status: RecoveryStatus
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ZStack(alignment: .leading) {
            Image(.recoveryHeroMountains)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, minHeight: heroHeight, maxHeight: heroHeight)
                .accessibilityHidden(true)

            LinearGradient(
                colors: [
                    RecoveryDetailsDesign.pageBackground.opacity(0.88),
                    .white.opacity(0.46),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 14) {
                        RecoveryHeroCopy(scoreText: scoreText, status: status)
                            .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                        RecoveryRingView(scoreText: scoreText, score: score, status: status)
                            .frame(width: 160, height: 160)
                            .frame(width: 280, alignment: .center)
                    }
                } else {
                    ViewThatFits(in: .horizontal) {
                        RecoveryHeroLayout(
                            scoreText: scoreText,
                            score: score,
                            status: status,
                            ringSize: 138,
                            minimumCopyWidth: 165
                        )
                        .fixedSize(horizontal: true, vertical: false)

                        RecoveryHeroLayout(
                            scoreText: scoreText,
                            score: score,
                            status: status,
                            ringSize: 116,
                            minimumCopyWidth: 162
                        )
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(RecoveryDetailsDesign.cardPadding)
        }
        .clipShape(.rect(cornerRadius: RecoveryDetailsDesign.cardCornerRadius))
        .recoveryCardSurface()
    }

    private var heroHeight: Double {
        dynamicTypeSize.isAccessibilitySize ? 520 : 220
    }
}
