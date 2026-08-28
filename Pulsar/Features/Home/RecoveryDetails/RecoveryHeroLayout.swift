import SwiftUI

struct RecoveryHeroLayout: View {
    var scoreText: String
    var score: Int
    var status: RecoveryStatus
    var ringSize: Double
    var minimumCopyWidth: Double

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            RecoveryHeroCopy(scoreText: scoreText, status: status)
            .frame(minWidth: minimumCopyWidth, maxWidth: .infinity, alignment: .leading)

            RecoveryRingView(scoreText: scoreText, score: score, status: status)
                .frame(width: ringSize, height: ringSize)
                .layoutPriority(1)
        }
    }
}
