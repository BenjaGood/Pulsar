import SwiftUI

struct StressSignalsCard: View {
    let signals: [StressSignal]

    init(signals: [StressSignal]) {
        self.signals = signals.isEmpty ? Self.missingSignals : signals
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Signals Used")
                    .font(.title2)
                    .bold()
                    .accessibilityAddTraits(.isHeader)

                Text("Availability and baseline comparison")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            GlassEffectContainer(spacing: 4) {
                VStack(spacing: 0) {
                    ForEach(signals) { signal in
                        StressSignalRow(signal: signal)

                        if signal.id != signals.last?.id {
                            Divider()
                                .padding(.leading, 62)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .stressCardSurface()
        }
    }

    private static let missingSignals: [StressSignal] = [
        StressSignal(id: "hrv", title: "HRV", value: "Not available", baseline: nil, availability: .unavailable),
        StressSignal(id: "heart-rate", title: "Heart rate", value: "Not available", baseline: nil, availability: .unavailable),
        StressSignal(id: "resting-heart-rate", title: "Resting heart rate", value: "Not available", baseline: nil, availability: .unavailable),
        StressSignal(id: "respiratory-rate", title: "Respiratory rate", value: "Not available", baseline: nil, availability: .unavailable),
        StressSignal(id: "non-activity-stress", title: "Non-activity stress", value: "Not available", baseline: "Inactive-only estimate", availability: .unavailable),
        StressSignal(id: "activity-adjusted-stress", title: "Activity-adjusted stress", value: "Not available", baseline: "Movement adjusted estimate", availability: .unavailable),
        StressSignal(id: "recent-load", title: "Recent strain/load", value: "Not available", baseline: nil, availability: .unavailable)
    ]
}

#Preview("Signals and Insights") {
    ScrollView {
        VStack(spacing: StressDetailsDesign.sectionSpacing) {
            StressSignalsCard(
                signals: MockHealthData.stressPreviewSummary(score: 65).signals
            )
            StressInsightsSection(summary: MockHealthData.stressPreviewSummary(score: 65))
        }
        .padding(16)
    }
    .background(StressDetailsDesign.pageBackground)
}
