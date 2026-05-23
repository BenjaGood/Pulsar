//
//  StressHomeMeterView.swift
//  Pulsar
//

import SwiftUI

struct StressHomeMeterView: View {
    var summary: StressSummary

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            centeredGauge
            statusRow
            insightStack
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(cardBorder)
        .shadow(color: shadowColor, radius: colorScheme == .dark ? 22 : 16, y: 10)
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accentGradient)
                .frame(width: 38, height: 38)
                .background(iconBackground, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("Stress")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(primaryText)
                Text("Estimated stress load")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(secondaryText)
            }

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                Text("View details")
                    .font(.caption.weight(.bold))
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(statusColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(statusColor.opacity(colorScheme == .dark ? 0.15 : 0.10), in: Capsule())
        }
    }

    private var centeredGauge: some View {
        StressHaloGaugeView(summary: summary, style: .home)
            .frame(width: 188, height: 188)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 2)
            .padding(.bottom, 2)
    }

    private var statusRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                statusPill
                confidencePill
                sourcePill
                Spacer(minLength: 0)
            }

            VStack(spacing: 8) {
                statusPill
                confidencePill
                sourcePill
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var statusPill: some View {
        Text(summary.displayLevelText)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(statusColor.opacity(colorScheme == .dark ? 0.15 : 0.10), in: Capsule())
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private var sourcePill: some View {
        Text(sourceText)
            .font(.caption.weight(.bold))
            .foregroundStyle(secondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(pillBackground, in: Capsule())
            .lineLimit(1)
            .minimumScaleFactor(0.65)
    }

    private var confidencePill: some View {
        Text(summary.confidence.shortLabel)
            .font(.caption.weight(.bold))
            .foregroundStyle(secondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(pillBackground, in: Capsule())
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private var insightStack: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(insightRows, id: \.self) { insight in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(statusColor.opacity(colorScheme == .dark ? 0.76 : 0.68))
                        .frame(width: 5, height: 5)
                        .padding(.top, 6)
                    Text(insight)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(primaryText.opacity(colorScheme == .dark ? 0.86 : 0.80))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(insightBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var insightRows: [String] {
        let driverTitles = summary.drivers.map(\.title)
        let rows = driverTitles.isEmpty ? summary.driverInsights : driverTitles
        return Array(rows.prefix(2))
    }

    private var sourceText: String {
        let sources = summary.sourceBadges.map(\.displayName)
        guard !sources.isEmpty else { return "No source" }
        let text = sources.prefix(2).joined(separator: " + ")
        return "Source \(text)"
    }

    private var statusColor: Color {
        summary.level?.stressTint(colorScheme: colorScheme) ?? (colorScheme == .dark ? Color.white.opacity(0.74) : Color(red: 0.38, green: 0.43, blue: 0.52))
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.97) : Color(red: 0.08, green: 0.10, blue: 0.15)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.63) : Color(red: 0.35, green: 0.39, blue: 0.47)
    }

    private var pillBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.075) : Color.white.opacity(0.62)
    }

    private var insightBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.055) : Color.white.opacity(0.58)
    }

    private var iconBackground: LinearGradient {
        LinearGradient(
            colors: [
                statusColor.opacity(colorScheme == .dark ? 0.24 : 0.14),
                Color.white.opacity(colorScheme == .dark ? 0.07 : 0.72)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var accentGradient: LinearGradient {
        LinearGradient(
            colors: [
                colorScheme == .dark ? Color.white.opacity(0.94) : Color(red: 0.14, green: 0.16, blue: 0.21),
                statusColor
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [
                            Color(red: 0.13, green: 0.16, blue: 0.24).opacity(0.78),
                            Color(red: 0.06, green: 0.08, blue: 0.14).opacity(0.88),
                            statusColor.opacity(0.10)
                        ]
                        : [
                            Color.white.opacity(0.90),
                            Color(red: 0.95, green: 0.97, blue: 1.00).opacity(0.82),
                            statusColor.opacity(0.08)
                        ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.20 : 0.86),
                        statusColor.opacity(colorScheme == .dark ? 0.16 : 0.24),
                        Color.black.opacity(colorScheme == .dark ? 0.16 : 0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    private var shadowColor: Color {
        colorScheme == .dark ? .black.opacity(0.25) : .black.opacity(0.10)
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
