import SwiftUI

struct StrainHeroCard: View {
    @ObservedObject var viewModel: StrainDetailsViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Image(.strainNatureBackground)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .opacity(colorScheme == .dark ? 0.18 : 0.34)
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black.opacity(0.08), location: 0.38),
                                .init(color: .black.opacity(0.82), location: 0.58),
                                .init(color: .black, location: 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    }
                    .accessibilityHidden(true)

                LinearGradient(
                    colors: [
                        heroTextBackground,
                        heroTextBackground.opacity(0.88),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: proxy.size.width, height: proxy.size.height)

                VStack(alignment: .leading, spacing: 12) {
                    if dynamicTypeSize <= .large {
                        HStack(alignment: .bottom, spacing: 18) {
                            StrainHeroCurrentMetric(
                                scoreText: viewModel.scoreText,
                                statusText: viewModel.statusText
                            )

                            Spacer(minLength: 12)

                            StrainHeroTargetMetric(
                                targetText: viewModel.recommendedTargetText
                            )
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 18) {
                            StrainHeroCurrentMetric(
                                scoreText: viewModel.scoreText,
                                statusText: viewModel.statusText
                            )

                            StrainHeroTargetMetric(
                                targetText: viewModel.recommendedTargetText
                            )
                        }
                    }

                    Spacer(minLength: 2)

                    PremiumStrainGauge(
                        current: viewModel.hasCurrentStrainValue
                            ? viewModel.summary.score
                            : nil,
                        targetRange: viewModel.targetRange
                    )

                    if proxy.size.width >= 350, dynamicTypeSize <= .large {
                        HStack(spacing: 9) {
                            StrainLoadPill(
                                title: "Active Strain",
                                value: viewModel.activeStrainText,
                                tint: StrainDetailsDesign.strainOrange
                            )
                            .frame(maxWidth: .infinity)

                            StrainLoadPill(
                                title: "Passive Strain",
                                value: viewModel.passiveStrainText,
                                tint: StrainDetailsDesign.passiveCyan
                            )
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        VStack(spacing: 9) {
                            StrainLoadPill(
                                title: "Active Strain",
                                value: viewModel.activeStrainText,
                                tint: StrainDetailsDesign.strainOrange
                            )

                            StrainLoadPill(
                                title: "Passive Strain",
                                value: viewModel.passiveStrainText,
                                tint: StrainDetailsDesign.passiveCyan
                            )
                        }
                    }
                }
                .padding(StrainDetailsDesign.cardPadding)
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height,
                    alignment: .topLeading
                )
            }
        }
        .frame(height: heroHeight)
        .clipShape(.rect(cornerRadius: StrainDetailsDesign.cardCornerRadius))
        .strainCardSurface()
        .accessibilityElement(children: .contain)
    }

    private var heroHeight: CGFloat {
        if dynamicTypeSize >= .accessibility3 {
            650
        } else if dynamicTypeSize.isAccessibilitySize {
            530
        } else {
            238
        }
    }

    private var heroTextBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.075, green: 0.070, blue: 0.085)
            : .white
    }
}
