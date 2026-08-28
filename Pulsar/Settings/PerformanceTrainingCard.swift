//
//  PerformanceTrainingCard.swift
//  Pulsar
//

import SwiftUI

struct PerformanceTrainingCard: View {
    @Binding var trainingLevel: TrainingLevel
    @Binding var heartRateZoneMethod: HeartRateZoneMethod

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TRAINING")
                .performanceSectionLabel()

            VStack(spacing: 0) {
                Menu {
                    Picker("Intensity Level", selection: $trainingLevel) {
                        ForEach(TrainingLevel.allCases) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                } label: {
                    PerformanceTrainingRow(
                        title: "Intensity Level",
                        value: trainingLevel.rawValue,
                        symbol: "chart.bar.fill",
                        tint: .black
                    )
                }

                SettingsDivider()

                Menu {
                    Picker("Heart Rate Source", selection: $heartRateZoneMethod) {
                        ForEach(HeartRateZoneMethod.allCases) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                } label: {
                    PerformanceTrainingRow(
                        title: "Heart Rate Source",
                        value: heartRateZoneMethod.rawValue,
                        symbol: "heart.text.square.fill",
                        tint: .black
                    )
                }
            }
            .buttonStyle(.plain)
            .performanceCardSurface()
        }
    }
}
