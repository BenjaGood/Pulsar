//
//  StrainCalendarSummary.swift
//  Pulsar
//

import SwiftUI

struct StrainCalendarSummary: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let date: Date
    let record: DailyStrainRecord?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            summaryHeaderLayout {
                Text(date.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer(minLength: 10)

                HStack(spacing: 12) {
                    StrainCalendarRing(
                        score: record?.strainScore ?? 0,
                        size: 60,
                        progressLineWidth: 4.5
                    )

                    VStack(alignment: .leading, spacing: 0) {
                        Text(strainValue)
                            .font(.largeTitle)
                            .bold()
                            .monospacedDigit()
                        Text("Strain")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            LazyVGrid(columns: columns, spacing: 10) {
                StrainCalendarMetricTile(
                    title: "Sleep",
                    value: sleepValue,
                    systemImage: "moon.fill",
                    tint: Color(red: 0.45, green: 0.40, blue: 0.82)
                )
                StrainCalendarMetricTile(
                    title: "Recovery",
                    value: scoreValue(record?.recoveryScore),
                    systemImage: "leaf.fill",
                    tint: Color(red: 0.32, green: 0.68, blue: 0.28)
                )
                StrainCalendarMetricTile(
                    title: "Strain",
                    value: strainValue,
                    systemImage: "figure.run",
                    tint: StrainCalendarDesign.strainOrange
                )
                StrainCalendarMetricTile(
                    title: "Stress",
                    value: scoreValue(record?.stressScore),
                    systemImage: "circle.hexagongrid.fill",
                    tint: Color(red: 0.22, green: 0.65, blue: 0.58)
                )
                StrainCalendarMetricTile(
                    title: "Workout",
                    value: workoutValue,
                    systemImage: "dumbbell.fill",
                    tint: StrainCalendarDesign.strainOrange
                )
                StrainCalendarMetricTile(
                    title: "Steps",
                    value: stepsValue,
                    systemImage: "shoeprints.fill",
                    tint: .secondary
                )
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .padding(18)
        .strainCalendarSurface(cornerRadius: StrainCalendarDesign.cardCornerRadius)
        .animation(.smooth(duration: 0.24), value: date)
    }

    private var summaryHeaderLayout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            return AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
        }
        return AnyLayout(HStackLayout(alignment: .center, spacing: 16))
    }

    private var strainValue: String {
        guard let record, record.strainScore > 0 else { return "--" }
        return record.strainScore.formatted()
    }

    private var sleepValue: String {
        guard let minutes = record?.sleepMinutes else { return "--" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours == 0 { return "\(remainingMinutes)m" }
        if remainingMinutes == 0 { return "\(hours)h" }
        return "\(hours)h \(remainingMinutes)m"
    }

    private var workoutValue: String {
        guard let minutes = record?.workoutMinutes, minutes > 0 else { return "--" }
        return "\(minutes)m"
    }

    private var stepsValue: String {
        guard let steps = record?.steps, steps > 0 else { return "--" }
        return steps.formatted()
    }

    private func scoreValue(_ score: Int?) -> String {
        score.map { $0.formatted() } ?? "--"
    }
}
