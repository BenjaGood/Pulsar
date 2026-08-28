import SwiftUI

struct RecoveryTrendCard: View {
    var points: [RecoveryTrendPoint]
    var currentScoreText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RecoveryTrendHeader(currentScoreText: currentScoreText)

            RecoveryTrendGraphView(points: points)
        }
        .padding(RecoveryDetailsDesign.cardPadding)
        .recoveryCardSurface()
    }
}
