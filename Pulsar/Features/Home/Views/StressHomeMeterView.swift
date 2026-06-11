//
//  StressHomeMeterView.swift
//  Pulsar
//

import SwiftUI

struct StressHomeMeterView: View {
    var summary: StressSummary

    @Environment(\.homeAdaptiveAppearance) private var appearance

    var body: some View {
        PremiumGlassContainer(cornerRadius: 34, tint: statusColor, isInteractive: true) {
            VStack(alignment: .leading, spacing: 8) {
                header

                PremiumStressGaugeView(summary: summary)
                    .frame(maxWidth: .infinity)
                    .frame(height: gaugeHeight)

                statusStack
                insightCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(summary.confidence.shortLabel). \(sourceText)")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(statusColor.opacity(0.10))
                        .overlay {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [statusColor.opacity(0.18), .clear],
                                        center: .center,
                                        startRadius: 2,
                                        endRadius: 34
                                    )
                                )
                        }
                )
                .overlay {
                    Circle()
                        .stroke(appearance.headerBorderColor.opacity(0.42), lineWidth: 0.8)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text("Stress")
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                    .foregroundStyle(appearance.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
                Text(subtitle)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(appearance.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 8)

            PremiumGlassPill(tint: statusColor, horizontalPadding: 13, verticalPadding: 9) {
                HStack(spacing: 8) {
                    Text("View details")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(appearance.primaryText.opacity(0.92))
            }
        }
    }

    private var statusStack: some View {
        VStack(spacing: 7) {
            HStack {
                Spacer(minLength: 0)
                statusPill
                Spacer(minLength: 0)
            }

            if hasStressScore {
                VStack(spacing: 2) {
                    Text(lastUpdatedText)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(appearance.timeAccentText)
                        .monospacedDigit()
                    Text(lastUpdatedCaption)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(appearance.tertiaryText)
                }
            }

        }
        .frame(maxWidth: .infinity)
    }

    private var statusPill: some View {
        PremiumGlassPill(tint: statusColor, horizontalPadding: 12, verticalPadding: 8) {
            HStack(spacing: 8) {
                Image(systemName: typicalRangeSymbol)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Text(typicalRangeText)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
            .foregroundStyle(statusColor)
        }
    }

    private var insightCard: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.10))
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [statusColor.opacity(0.22), .clear],
                            center: .center,
                            startRadius: 2,
                            endRadius: 36
                        )
                    )
                Image(systemName: insightSymbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(statusColor)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 5) {
                Text(insightTitle)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(appearance.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Text(insightBody)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(appearance.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 6)

            Image(systemName: "chevron.right")
                .font(.headline.weight(.semibold))
                .foregroundStyle(appearance.tertiaryText)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.020, green: 0.026, blue: 0.044).opacity(0.14),
                            Color.black.opacity(0.085),
                            statusColor.opacity(0.018)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(appearance.headerBorderColor.opacity(0.36), lineWidth: 0.55)
        }
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(appearance.headerBorderColor.opacity(0.30), lineWidth: 0.45)
                .blur(radius: 0.2)
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
        hasStressScore ? 136 : 104
    }

    private var hasStressScore: Bool {
        summary.score != nil
    }

    private var typicalRangeText: String {
        if summary.state == .lowConfidence {
            return summary.confidence.shortLabel
        }

        guard summary.score != nil else {
            if summary.state == .buildingBaseline { return "Building your baseline" }
            return "Awaiting stress signals"
        }

        switch summary.level {
        case .low, .balanced:
            return "Within your typical range"
        case .elevated:
            return "Slightly above typical"
        case .high:
            return "Above your typical range"
        case nil:
            return "Stress estimate ready"
        }
    }

    private var typicalRangeSymbol: String {
        if summary.state == .lowConfidence {
            return "exclamationmark.triangle"
        }

        guard summary.score != nil else { return "clock.badge.checkmark" }
        switch summary.level {
        case .low, .balanced:
            return "checkmark.square"
        case .elevated:
            return "exclamationmark.triangle"
        case .high:
            return "exclamationmark.octagon"
        case nil:
            return "waveform.path.ecg"
        }
    }

    private var insightTitle: String {
        guard summary.score != nil else {
            return summary.displayLevelText
        }

        if summary.state == .lowConfidence {
            return summary.confidence.shortLabel
        }

        return "Your stress is \(homeStressLevelText.lowercased())"
    }

    private var insightBody: String {
        guard summary.score != nil else {
            return summary.explanation
        }

        if summary.state == .lowConfidence {
            return summary.explanation
        }

        if homeStressLevelText == "Low" {
            return "Great balance. Keep it up."
        }

        if let driver = summary.drivers.first {
            return driver.detail
        }

        if let insight = summary.driverInsights.first {
            return insight
        }

        return summary.explanation
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
        guard let score = summary.score else { return summary.displayLevelText }
        switch score {
        case 0...33:
            return "Low"
        case 34...66:
            return "Medium"
        default:
            return "High"
        }
    }

    private var sourceText: String {
        let sources = summary.sourceBadges.map(\.displayName)
        guard !sources.isEmpty else { return "No source" }
        let text = sources.prefix(2).joined(separator: " + ")
        return "Source \(text)"
    }

    private var latestUpdateDate: Date? {
        summary.lastUpdated ?? summary.queryEnd
    }

    private var lastUpdatedText: String {
        guard let date = latestUpdateDate else {
            return "Not updated"
        }
        return date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
    }

    private var lastUpdatedCaption: String {
        latestUpdateDate == nil ? "No recent update" : "Last updated"
    }

    private var statusColor: Color {
        stressGaugeTint(for: summary.score)
    }
}

struct StressHomeMeterButtonStyle: ButtonStyle {
    var glowColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .brightness(configuration.isPressed ? 0.035 : 0)
            .shadow(color: glowColor.opacity(configuration.isPressed ? 0.28 : 0), radius: 18, y: 8)
            .animation(.spring(response: 0.30, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

#Preview("Stress Meter - Low") {
    StressHomeMeterView(summary: MockHealthData.stressPreviewSummary(score: 18))
        .padding()
        .background(PulsarSectionBackground())
}

#Preview("Stress Meter - Elevated") {
    StressHomeMeterView(summary: MockHealthData.stressPreviewSummary(score: 64, confidence: .moderate))
        .padding()
        .background(PulsarSectionBackground())
}

#Preview("Stress Meter - High") {
    StressHomeMeterView(summary: MockHealthData.stressPreviewSummary(score: 88, confidence: .low))
        .padding()
        .background(PulsarSectionBackground())
}

#Preview("Stress Meter - Centered 86") {
    StressHomeMeterView(summary: MockHealthData.stressPreviewSummary(score: 86, confidence: .high))
        .padding()
        .background(PulsarSectionBackground())
}

#Preview("Stress Meter - Not Enough Data") {
    StressHomeMeterView(summary: .buildingBaseline(date: Date(), baselineWindowDays: 4, analyzedSampleCount: 5, sourceBadges: [.sample]))
        .padding()
        .background(PulsarSectionBackground())
}
