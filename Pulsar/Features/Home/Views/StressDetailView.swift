//
//  StressDetailView.swift
//  Pulsar
//

import SwiftUI

struct StressDetailView: View {
    var summary: StressSummary

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard
                gaugeCard
                physiologyGrid
                StressTimelineChartView(samples: summary.dailySamples, summary: summary)
                driversSection
                signalsSection
                StressEducationCard()
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .background(PulsarSectionBackground())
        .navigationTitle("Stress")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Stress")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(primaryText)
                    Text("Estimated from available HealthKit signals. Not a medical diagnosis.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 10)

                confidenceBadge
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(summary.displayScoreText)
                    .font(summary.currentScore == nil ? .title2.weight(.bold) : .system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(primaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)

                Text(summary.displayLevelText)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(tint.opacity(colorScheme == .dark ? 0.15 : 0.10), in: Capsule())

                Spacer(minLength: 0)
            }

            if let updated = summary.lastUpdated {
                Label("Updated \(updated.formatted(date: .omitted, time: .shortened))", systemImage: "clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryText)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground(cornerRadius: 28))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(cardBorder(cornerRadius: 28))
    }

    private var gaugeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            StressHaloGaugeView(summary: summary, style: .detail)
                .frame(maxWidth: .infinity)
                .frame(height: 286)

            Text(summary.explanation)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(cardBackground(cornerRadius: 30))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(cardBorder(cornerRadius: 30))
    }

    private var physiologyGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Current physiology", subtitle: "Recent HR and HRV with activity filtered out")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                StressSnapshotTile(title: "Current Stress", value: summary.displayScoreText, subtitle: summary.displayLevelText, tint: tint)
                StressSnapshotTile(title: "Last HR", value: heartRateText, subtitle: timestampText(summary.lastHeartRateTimestamp), tint: tint)
                StressSnapshotTile(title: "Last HRV", value: hrvText, subtitle: timestampText(summary.lastHRVTimestamp), tint: tint)
                StressSnapshotTile(title: "Non-Activity", value: stressText(summary.nonActivityStress), subtitle: "Stillness estimate", tint: tint)
                StressSnapshotTile(title: "Adjusted", value: stressText(summary.activityAdjustedStress), subtitle: summary.movementStateText ?? "Movement filter", tint: tint)
                StressSnapshotTile(title: "Confidence", value: summary.confidence.shortLabel, subtitle: summary.stressStatusText ?? "Measuring", tint: confidenceColor)
            }
        }
    }

    private var driversSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Key drivers", subtitle: "Signals moving your stress estimate")

            ForEach(driverRows) { driver in
                StressDriverCard(driver: driver)
            }
        }
    }

    private var signalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Signals used", subtitle: "Availability and baseline comparison")

            VStack(spacing: 8) {
                ForEach(signalRows) { signal in
                    StressSignalRow(signal: signal)
                }
            }
            .padding(10)
            .background(cardBackground(cornerRadius: 26))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(cardBorder(cornerRadius: 26))
        }
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(primaryText)
            Text(subtitle)
                .font(.caption.weight(.medium))
                .foregroundStyle(secondaryText)
        }
        .padding(.horizontal, 2)
    }

    private var confidenceBadge: some View {
        Text(summary.confidence.shortLabel)
            .font(.caption.weight(.bold))
            .foregroundStyle(confidenceColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(confidenceColor.opacity(colorScheme == .dark ? 0.15 : 0.10), in: Capsule())
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }

    private var driverRows: [StressDriver] {
        if !summary.drivers.isEmpty {
            return summary.drivers
        }

        let fallback = summary.driverInsights.enumerated().map { index, insight in
            StressDriver(
                id: "fallback-driver-\(index)",
                title: insight,
                detail: "Based on available wearable signals compared with your baseline.",
                severity: .neutral,
                relatedMetric: nil
            )
        }

        if !fallback.isEmpty {
            return fallback
        }

        return [
            StressDriver(
                id: "stable-stress",
                title: "Stress is stable today",
                detail: "Pulsar will show stronger drivers as more wearable signals become available.",
                severity: .neutral,
                relatedMetric: nil
            )
        ]
    }

    private var signalRows: [StressSignal] {
        if !summary.signals.isEmpty {
            return summary.signals
        }

        return [
            StressSignal(id: "hrv", title: "HRV", value: "Not available", baseline: nil, availability: .unavailable),
            StressSignal(id: "heart-rate", title: "Heart rate", value: "Not available", baseline: nil, availability: .unavailable),
            StressSignal(id: "resting-heart-rate", title: "Resting heart rate", value: "Not available", baseline: nil, availability: .unavailable),
            StressSignal(id: "respiratory-rate", title: "Respiratory rate", value: "Not available", baseline: nil, availability: .unavailable),
            StressSignal(id: "sleep-performance", title: "Sleep performance", value: "Not available", baseline: nil, availability: .unavailable),
            StressSignal(id: "recent-load", title: "Recent strain/load", value: "Not available", baseline: nil, availability: .unavailable)
        ]
    }

    private var heartRateText: String {
        summary.lastHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "No data"
    }

    private var hrvText: String {
        summary.lastHRV.map { "\(Int($0.rounded())) ms" } ?? "No data"
    }

    private func stressText(_ value: Int?) -> String {
        value.map(String.init) ?? (summary.state == .workoutPaused || summary.state == .cooldown ? "Paused" : "--")
    }

    private func timestampText(_ date: Date?) -> String {
        date.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" } ?? "Freshness limited"
    }

    private var tint: Color {
        summary.level?.stressTint(colorScheme: colorScheme) ?? Color(red: 0.45, green: 0.62, blue: 0.92)
    }

    private var confidenceColor: Color {
        switch summary.confidence {
        case .high:
            return Color(red: 0.25, green: 0.78, blue: 0.56)
        case .moderate:
            return Color(red: 0.92, green: 0.66, blue: 0.24)
        case .low:
            return Color(red: 1.00, green: 0.50, blue: 0.32)
        case .missing:
            return secondaryText
        }
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.96) : Color(red: 0.08, green: 0.10, blue: 0.15)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.62) : Color(red: 0.35, green: 0.39, blue: 0.47)
    }

    private func cardBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [
                            Color.white.opacity(0.085),
                            Color(red: 0.06, green: 0.08, blue: 0.14).opacity(0.86),
                            tint.opacity(0.08)
                        ]
                        : [
                            Color.white.opacity(0.88),
                            Color(red: 0.96, green: 0.98, blue: 1.00).opacity(0.78),
                            tint.opacity(0.06)
                        ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func cardBorder(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.18 : 0.84),
                        tint.opacity(colorScheme == .dark ? 0.13 : 0.20),
                        Color.black.opacity(colorScheme == .dark ? 0.14 : 0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
}

private struct StressSnapshotTile: View {
    var title: String
    var value: String
    var subtitle: String
    var tint: Color

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.70)
            Text(subtitle)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(secondaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    tint.opacity(colorScheme == .dark ? 0.14 : 0.10),
                    colorScheme == .dark ? Color.white.opacity(0.055) : Color.white.opacity(0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(tint.opacity(colorScheme == .dark ? 0.16 : 0.20), lineWidth: 1)
        )
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.96) : Color(red: 0.08, green: 0.10, blue: 0.15)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.62) : Color(red: 0.35, green: 0.39, blue: 0.47)
    }
}

#Preview("Stress Detail - Full Day") {
    NavigationStack {
        StressDetailView(summary: MockHealthData.stressDetailSummary)
    }
}

#Preview("Stress Detail - Missing") {
    NavigationStack {
        StressDetailView(summary: .missing)
    }
}
