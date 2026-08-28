import Charts
import SwiftUI

struct HeartLoadChart: View {
    var chart: StrainHeartLoadChartModel

    var body: some View {
        Group {
            if chart.hasHeartRate {
                Chart {
                    ForEach(chart.heartRatePoints) { point in
                        AreaMark(
                            x: .value("Time", point.date),
                            yStart: .value("Baseline", displayYAxisMin),
                            yEnd: .value("Heart rate", point.bpm)
                        )
                        .interpolationMethod(.linear)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    StrainDetailsDesign.strainOrange.opacity(0.18),
                                    StrainDetailsDesign.strainRed.opacity(0.015)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Time", point.date),
                            y: .value("Heart rate", point.bpm)
                        )
                        .interpolationMethod(.linear)
                        .lineStyle(
                            StrokeStyle(
                                lineWidth: 1.7,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    StrainDetailsDesign.strainOrange,
                                    StrainDetailsDesign.strainRed
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    }

                    if let peakPoint {
                        PointMark(
                            x: .value("Peak time", peakPoint.date),
                            y: .value("Peak heart rate", peakPoint.bpm)
                        )
                        .foregroundStyle(StrainDetailsDesign.strainRed)
                        .symbolSize(54)
                        .annotation(position: .top, spacing: 8) {
                            Text("\(Int(peakPoint.bpm.rounded())) bpm")
                            .font(.caption)
                                .bold()
                                .monospacedDigit()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.background.opacity(0.94), in: Capsule())
                                .shadow(
                                    color: .black.opacity(0.07),
                                    radius: 8,
                                    y: 4
                                )
                        }
                    }
                }
                .chartLegend(.hidden)
                .chartXScale(
                    domain: chart.range.start...chart.range.end,
                    range: .plotDimension(startPadding: 8, endPadding: 8)
                )
                .chartYScale(domain: displayYAxisMin...displayYAxisMax)
                .chartXAxis {
                    AxisMarks(values: xAxisDates) { value in
                        AxisGridLine()
                            .foregroundStyle(.clear)
                        AxisTick()
                            .foregroundStyle(.clear)
                        AxisValueLabel(
                            anchor: value.index == 0
                                ? .topLeading
                                : value.index == xAxisDates.count - 1
                                    ? .topTrailing
                                    : .top,
                            collisionResolution: .disabled
                        ) {
                            if let date = value.as(Date.self) {
                                Text(xAxisLabel(for: date))
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(Color.gray.opacity(0.78))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: yAxisValues) { value in
                        AxisGridLine(
                            stroke: StrokeStyle(lineWidth: 0.6)
                        )
                        .foregroundStyle(Color.gray.opacity(0.12))
                        AxisTick()
                            .foregroundStyle(.clear)
                        AxisValueLabel()
                            .font(.caption)
                            .foregroundStyle(Color.gray.opacity(0.78))
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(.clear)
                }
                .frame(height: 116)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Heart rate throughout the day")
                .accessibilityValue(chartSummary)
                .environment(\.timeZone, chart.timeZone)
            } else {
                ContentUnavailableView(
                    "No Heart Rate Samples",
                    systemImage: "waveform.path.ecg",
                    description: Text(
                        "Heart load will appear when HealthKit provides heart-rate samples."
                    )
                )
                .frame(maxWidth: .infinity, minHeight: 116)
                .accessibilityLabel(
                    "Heart rate chart unavailable because there are no heart-rate samples"
                )
            }
        }
    }

    private var peakPoint: HeartRatePoint? {
        chart.heartRatePoints.max { $0.bpm < $1.bpm }
    }

    private var xAxisDates: [Date] {
        chart.markers.reduce(into: []) { dates, marker in
            guard dates.last != marker.date else { return }
            dates.append(marker.date)
        }
    }

    private func xAxisLabel(for date: Date) -> String {
        chart.markers.first {
            abs($0.date.timeIntervalSince(date)) < 1
        }?.label ?? ""
    }

    private var yAxisValues: [Double] {
        let first = ceil(displayYAxisMin / 50) * 50
        let last = floor(displayYAxisMax / 50) * 50
        guard first <= last else { return [chart.yAxisMin, chart.yAxisMax] }
        return Array(stride(from: first, through: last, by: 50))
    }

    private var displayYAxisMin: Double {
        min(50, chart.yAxisMin)
    }

    private var displayYAxisMax: Double {
        max(200, chart.yAxisMax)
    }

    private var chartSummary: String {
        guard
            let minimum = chart.heartRatePoints.map(\.bpm).min(),
            let maximum = chart.heartRatePoints.map(\.bpm).max()
        else {
            return "No heart-rate samples"
        }

        return "Heart rate ranged from \(Int(minimum.rounded())) to \(Int(maximum.rounded())) beats per minute"
    }
}
