//
//  PerformanceHeartMetricsCard.swift
//  Pulsar
//

import SwiftUI

struct PerformanceHeartMetricsCard: View {
    @Binding var maxHeartRate: Double
    var maxHeartRateSubtitle: String
    @Binding var restingHeartRate: Double
    @Binding var hrv: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HEART METRICS")
                .performanceSectionLabel()

            VStack(spacing: 0) {
                PerformanceHeartMetricRow(
                    title: "Max Heart Rate",
                    subtitle: maxHeartRateSubtitle,
                    symbol: "heart.circle",
                    tint: .black,
                    value: $maxHeartRate,
                    unit: "bpm",
                    range: 120...230
                )

                SettingsDivider()

                PerformanceHeartMetricRow(
                    title: "Resting HR Baseline",
                    symbol: "heart.fill",
                    tint: .black,
                    value: $restingHeartRate,
                    unit: "bpm",
                    range: 35...90
                )

                SettingsDivider()

                PerformanceHeartMetricRow(
                    title: "HRV Baseline",
                    subtitle: "SDNN baseline",
                    symbol: "waveform.path.ecg",
                    tint: .black,
                    value: $hrv,
                    unit: "ms",
                    range: 10...180
                )
            }
            .performanceCardSurface()
        }
    }
}
