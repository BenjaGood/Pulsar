import SwiftUI

struct StressMetricsCard: View {
    var summary: StressSummary

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Stress at a glance")
                    .font(.title2)
                    .bold()
                    .accessibilityAddTraits(.isHeader)

                Text("Key metrics from recent signals")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            GlassEffectContainer(spacing: 8) {
                LazyVGrid(columns: columns, spacing: 10) {
                    StressMetricTile(
                        title: "HRV",
                        value: hrvValue,
                        interpretation: signalDetail(id: "hrv", fallback: "Recent signal"),
                        symbol: "waveform.path.ecg"
                    )

                    StressMetricTile(
                        title: "Heart Rate",
                        value: heartRateValue,
                        interpretation: signalDetail(id: "heart-rate", fallback: "Recent signal"),
                        symbol: "heart"
                    )

                    StressMetricTile(
                        title: "Respiratory Rate",
                        value: respiratoryValue,
                        interpretation: availabilityDetail(id: "respiratory-rate"),
                        symbol: "lungs.fill"
                    )

                    StressMetricTile(
                        title: "Sleep",
                        value: sleepValue,
                        interpretation: availabilityDetail(id: "sleep-duration"),
                        symbol: "moon.stars.fill"
                    )

                    StressMetricTile(
                        title: "Non-Activity Stress",
                        value: stressValue(summary.nonActivityStress),
                        interpretation: levelText(for: summary.nonActivityStress),
                        symbol: "figure.mind.and.body",
                        statusColor: summary.nonActivityStress.map { stressGaugeTint(for: $0) }
                    )

                    StressMetricTile(
                        title: "Adjusted Stress",
                        value: stressValue(summary.activityAdjustedStress),
                        interpretation: levelText(for: summary.activityAdjustedStress),
                        symbol: "leaf.fill",
                        statusColor: summary.activityAdjustedStress.map { stressGaugeTint(for: $0) }
                    )
                }
            }
        }
        .padding(StressDetailsDesign.cardPadding)
        .stressCardSurface()
    }

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 3
        return Array(
            repeating: GridItem(.flexible(minimum: 0), spacing: 10, alignment: .top),
            count: count
        )
    }

    private var heartRateValue: String {
        summary.lastHeartRate.map { "\(Int($0.rounded())) bpm" }
            ?? signal(id: "heart-rate")?.value
            ?? "No data"
    }

    private var hrvValue: String {
        summary.lastHRV.map { "\(Int($0.rounded())) ms" }
            ?? signal(id: "hrv")?.value
            ?? "No data"
    }

    private var respiratoryValue: String {
        guard let value = signal(id: "respiratory-rate")?.value else {
            return "No data"
        }

        return value.replacing("breaths/min", with: "br/min")
    }

    private var sleepValue: String {
        guard let value = signal(id: "sleep-duration")?.value else {
            return "No data"
        }

        guard let minutesText = value.split(separator: " ").first,
              let minutes = Int(minutesText) else {
            return value
        }

        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder)m" }
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }

    private func signal(id: String) -> StressSignal? {
        summary.signals.first { $0.id == id }
    }

    private func signalDetail(id: String, fallback: String) -> String {
        signal(id: id)?.baseline ?? availabilityDetail(id: id, fallback: fallback)
    }

    private func availabilityDetail(id: String, fallback: String = "Near baseline") -> String {
        guard let signal = signal(id: id) else { return "No recent data" }

        switch signal.availability {
        case .available:
            return signal.baseline ?? fallback
        case .limited:
            return "Limited signal"
        case .unavailable:
            return "No recent data"
        }
    }

    private func stressValue(_ value: Int?) -> String {
        value.map(String.init) ?? (summary.state == .workoutPaused || summary.state == .cooldown ? "Paused" : "--")
    }

    private func levelText(for score: Int?) -> String {
        guard let score else {
            return summary.state == .workoutPaused || summary.state == .cooldown ? "Activity filtered" : "Building"
        }

        switch StressLevel.level(for: score) {
        case .low:
            return "Low"
        case .balanced:
            return "Balanced"
        case .elevated:
            return "Elevated"
        case .high:
            return "High"
        }
    }
}
