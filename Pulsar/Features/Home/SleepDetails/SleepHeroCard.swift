import SwiftUI

struct SleepHeroCard: View {
    @ObservedObject var viewModel: SleepDetailsViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var artworkVisible = false

    var body: some View {
        ZStack(alignment: .leading) {
            Image(.sleepHeroLandscape)
                .resizable()
                .scaledToFill()
                .frame(
                    maxWidth: .infinity,
                    minHeight: heroHeight,
                    maxHeight: heroHeight
                )
                .offset(x: 6)
                .blur(radius: 1.2)
                .opacity(artworkVisible ? 0.78 : 0)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.18), location: 0.28),
                            .init(color: .black, location: 0.54),
                            .init(color: .black, location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
                .accessibilityHidden(true)

            LinearGradient(
                colors: [
                    SleepDetailsDesign.pageBackground.opacity(0.96),
                    SleepDetailsDesign.pageBackground.opacity(0.62),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    SleepDurationCounter(totalMinutes: viewModel.summary.totalSleepMinutes)

                    Text("Total Sleep")
                        .pulsarTextStyle(.metadata)
                        .foregroundStyle(.secondary)
                }

                Label {
                    Text(viewModel.statusText)
                } icon: {
                    Circle()
                        .fill(SleepDetailsDesign.deep)
                        .frame(width: 10, height: 10)
                }
                .pulsarTextStyle(.bodyEmphasis)
                .foregroundStyle(SleepDetailsDesign.deep)

                Spacer(minLength: 6)

                GlassEffectContainer(spacing: 8) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            if let alarmBadgeText = viewModel.alarmBadgeText {
                                SleepHeroChip(
                                    title: alarmBadgeText,
                                    symbol: "alarm.fill",
                                    tint: SleepDetailsDesign.awake
                                )
                            }

                            SleepHeroChip(
                                title: viewModel.rhythmBadgeText,
                                symbol: "moon.stars.fill",
                                tint: SleepDetailsDesign.deep
                            )
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            if let alarmBadgeText = viewModel.alarmBadgeText {
                                SleepHeroChip(
                                    title: alarmBadgeText,
                                    symbol: "alarm.fill",
                                    tint: SleepDetailsDesign.awake
                                )
                            }

                            SleepHeroChip(
                                title: viewModel.rhythmBadgeText,
                                symbol: "moon.stars.fill",
                                tint: SleepDetailsDesign.deep
                            )
                        }
                    }
                }
            }
            .padding(SleepDetailsDesign.cardPadding)
            .frame(maxWidth: .infinity, minHeight: heroHeight, alignment: .leading)
        }
        .clipShape(.rect(cornerRadius: SleepDetailsDesign.cardCornerRadius))
        .sleepCardSurface()
        .task {
            if reduceMotion {
                artworkVisible = true
            } else {
                withAnimation(.smooth(duration: 0.84)) {
                    artworkVisible = true
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var heroHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 340 : 248
    }
}
