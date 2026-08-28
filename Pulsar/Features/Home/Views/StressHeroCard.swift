import SwiftUI

struct StressHeroCard: View {
    var summary: StressSummary

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        cardContent.stressHeroSurface()
    }

    private var cardContent: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
                    .frame(maxWidth: .infinity)
                    .frame(height: StressDetailsDesign.heroAccessibilityHeight)
            } else {
                GeometryReader { proxy in
                    regularLayout(size: proxy.size)
                }
                .aspectRatio(StressDetailsDesign.heroAspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
            }
        }
        .clipShape(.rect(cornerRadius: StressDetailsDesign.heroCornerRadius))
    }

    // MARK: - Regular layout

    private func regularLayout(size: CGSize) -> some View {
        let padding = StressDetailsDesign.heroPadding
        let contentWidth = max(0, size.width - padding * 2)
        let copyWidth = contentWidth * StressDetailsDesign.heroCopyWidthFraction
        let gaugeWidth = contentWidth * StressDetailsDesign.heroGaugeWidthFraction

        return ZStack(alignment: .bottom) {
            heroArtwork(cardSize: size)

            ZStack(alignment: .topLeading) {
                StressHeroCopy(summary: summary)
                    .frame(width: copyWidth, alignment: .leading)

                LuxuryStressGaugeView(summary: summary)
                    .frame(width: gaugeWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                StressHeroTimestamp(summary: summary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .padding(.horizontal, padding)
            .padding(.top, 18)
            .padding(.bottom, 14)
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: - Accessibility layout

    private var accessibilityLayout: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { proxy in
                heroArtwork(cardSize: proxy.size)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
            }

            VStack(alignment: .leading, spacing: 24) {
                StressHeroCopy(summary: summary)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

                LuxuryStressGaugeView(summary: summary)
                    .frame(height: 280)
                    .frame(maxWidth: .infinity)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

                Spacer(minLength: 0)

                StressHeroTimestamp(summary: summary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Artwork

    /// Landscape artwork anchored to the lower portion of the card with a
    /// vertical fade so it dissolves toward the center, never a flat wash.
    private func heroArtwork(cardSize: CGSize) -> some View {
        Image(.stressHeroLandscape)
            .resizable()
            .scaledToFill()
            .frame(width: max(0, cardSize.width), height: max(0, cardSize.height * 0.62))
            .clipped()
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.00),
                        .init(color: .black.opacity(0.16), location: 0.30),
                        .init(color: .black.opacity(0.62), location: 0.62),
                        .init(color: .black.opacity(0.94), location: 1.00)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .opacity(reduceTransparency ? 0.34 : 0.52)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#Preview("Premium Stress Hero") {
    StressHeroCard(summary: MockHealthData.stressPreviewSummary(score: 10))
        .padding(20)
        .background(StressDetailsBackground())
}

#Preview("Premium Stress Hero - Medium") {
    StressHeroCard(summary: MockHealthData.stressPreviewSummary(score: 42))
        .padding(20)
        .background(StressDetailsBackground())
}
