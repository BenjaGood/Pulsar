//
//  StressHomeMeterView.swift
//  Pulsar
//

import SwiftUI

struct StressHomeMeterView: View {
    var summary: StressSummary

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.homeAdaptiveAppearance) private var appearance

    var body: some View {
        PulsarGlassEffectGroup(spacing: 8) {
            PremiumGlassContainer(
                cornerRadius: HomePremiumDesign.Radius.stressCard,
                tint: statusColor,
                isInteractive: true,
                shadowColor: HomePremiumDesign.shadow.opacity(0.42),
                shadowRadius: 9,
                shadowY: 4
            ) {
                ZStack(alignment: .bottom) {
                    mountainArtwork

                    VStack(alignment: .leading, spacing: 0) {
                        header

                        PremiumStressGaugeView(summary: summary)
                            .frame(maxWidth: .infinity)
                            .frame(height: gaugeHeight)
                            .padding(.top, 8)

                        Text(contextualMessage)
                            .font(.footnote)
                            .foregroundStyle(appearance.secondaryText)
                            .multilineTextAlignment(.center)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 18)
                            .padding(.top, 10)
                            .padding(.bottom, 18)

                        insightCapsule
                    }
                    .padding(.horizontal, HomePremiumDesign.Layout.cardContentPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .clipShape(.rect(cornerRadius: HomePremiumDesign.Radius.stressCard))
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(.rect(cornerRadius: HomePremiumDesign.Radius.stressCard))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stress, \(summary.displayScoreText), \(homeStressLevelText). \(contextualMessage)")
        .accessibilityValue("\(summary.confidence.shortLabel). \(sourceText)")
    }

    private var mountainArtwork: some View {
        Image("StressBackground")
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: 132)
            .clipped()
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.30), location: 0.34),
                        .init(color: .black, location: 0.68)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .opacity(reduceTransparency ? 0.24 : 0.36)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var header: some View {
        headerIdentity
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerIdentity: some View {
        HStack(spacing: 7) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(statusColor)
                .frame(width: 34, height: 34)
                .background(statusColor.opacity(0.055), in: Circle())
                .overlay { Circle().stroke(statusColor.opacity(0.10), lineWidth: 0.6) }

            VStack(alignment: .leading, spacing: 1) {
                Text("Stress")
                    .font(.headline)
                    .foregroundStyle(appearance.primaryText)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(appearance.tertiaryText)
                    .lineLimit(1)
            }
        }
    }

    private var insightCapsule: some View {
        PremiumGlassPill(tint: statusColor, horizontalPadding: 10, verticalPadding: 6) {
            HStack(spacing: 8) {
                Image(systemName: insightSymbol)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(statusColor)

                Text(insightPrompt)
                    .font(.footnote)
                    .foregroundStyle(appearance.secondaryText)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.84)

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(appearance.tertiaryText)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var subtitle: String {
        switch summary.state {
        case .workoutPaused, .cooldown:
            return summary.stressStatusText ?? "Current stress"
        default:
            return "Current stress"
        }
    }

    private var gaugeHeight: CGFloat {
        hasStressScore ? 166 : 132
    }

    private var hasStressScore: Bool {
        summary.score != nil
    }

    private var contextualMessage: String {
        summary.explanation
    }

    private var insightPrompt: String {
        guard summary.score != nil else {
            return "Learn how stress is estimated"
        }

        if summary.state == .lowConfidence {
            return "Review available stress signals"
        }

        switch summary.level {
        case .low:
            return "See what is supporting your balance"
        case .balanced:
            return "Review today’s stress signals"
        case .elevated, .high:
            return "View contributing stress signals"
        case nil:
            return "Review today’s stress signals"
        }
    }

    private var insightSymbol: String {
        switch summary.level {
        case .low, .balanced:
            return "sparkles"
        case .elevated:
            return "wind"
        case .high:
            return "bolt.heart"
        case nil:
            return "heart.text.square"
        }
    }

    private var homeStressLevelText: String {
        summary.displayLevelText
    }

    private var sourceText: String {
        let sources = summary.sourceBadges.map(\.displayName)
        guard !sources.isEmpty else { return "No source" }
        let text = sources.prefix(2).joined(separator: " + ")
        return "Source \(text)"
    }

    private var statusColor: Color {
        stressGaugeTint(for: summary.score)
    }
}

struct StressHomeMeterButtonStyle: ButtonStyle {
    var glowColor: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.994 : 1)
            .brightness(configuration.isPressed ? 0.008 : 0)
            .shadow(color: glowColor.opacity(configuration.isPressed ? 0.045 : 0), radius: 7, y: 3)
            .animation(reduceMotion ? nil : .spring(duration: 0.30, bounce: 0.06), value: configuration.isPressed)
    }
}

#Preview("Stress Meter - Low") {
    StressHomeMeterView(summary: MockHealthData.stressPreviewSummary(score: 18))
        .padding()
        .background(HomePremiumDesign.background)
        .environment(\.homeAdaptiveAppearance, .premium)
}

#Preview("Stress Meter - Elevated") {
    StressHomeMeterView(summary: MockHealthData.stressPreviewSummary(score: 64, confidence: .moderate))
        .padding()
        .background(HomePremiumDesign.background)
        .environment(\.homeAdaptiveAppearance, .premium)
}

#Preview("Stress Meter - Not Enough Data") {
    StressHomeMeterView(summary: .buildingBaseline(date: .now, baselineWindowDays: 4, analyzedSampleCount: 5, sourceBadges: [.sample]))
        .padding()
        .background(HomePremiumDesign.background)
        .environment(\.homeAdaptiveAppearance, .premium)
}
