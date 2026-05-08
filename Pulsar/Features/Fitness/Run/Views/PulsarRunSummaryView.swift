//
//  PulsarRunSummaryView.swift
//  Pulsar
//

import Charts
import MapKit
import SwiftUI

struct PulsarRunSummaryView: View {
    var summary: PulsarRunSummary
    var onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                routeMap
                heroStats
                charts
                splits
                doneButton
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 34)
        }
        .background(summaryBackground)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Run Saved")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                Text(summary.startedAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute()))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label(summary.source.label, systemImage: summary.source == .appleWatch ? "applewatch" : "iphone")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    @ViewBuilder
    private var routeMap: some View {
        if routeCoordinates.count > 1 {
            Map {
                MapPolyline(coordinates: routeCoordinates)
                    .stroke(.green, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            .frame(height: 230)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.22), lineWidth: 1)
            }
        } else {
            PulsarRunGlassCard {
                Label("Route map will appear here when GPS points are available.", systemImage: "map")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var heroStats: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            SummaryTile(title: "Distance", value: PulsarRunFormatters.distance(summary.distanceMeters), symbol: "point.topleft.down.curvedto.point.bottomright.up")
            SummaryTile(title: "Moving Time", value: PulsarRunFormatters.duration(summary.movingTime), symbol: "figure.run")
            SummaryTile(title: "Elapsed", value: PulsarRunFormatters.duration(summary.elapsedTime), symbol: "timer")
            SummaryTile(title: "Avg Pace", value: PulsarRunFormatters.pace(summary.averagePaceSecondsPerKilometer), symbol: "speedometer")
            SummaryTile(title: "Calories", value: PulsarRunFormatters.calories(summary.activeEnergyKilocalories), symbol: "flame.fill", tint: .orange)
            SummaryTile(title: "Elevation", value: PulsarRunFormatters.elevation(summary.elevationGainMeters), symbol: "mountain.2.fill", tint: .green)
            SummaryTile(title: "Avg HR", value: PulsarRunFormatters.heartRate(summary.averageHeartRate), unit: "bpm", symbol: "heart.fill", tint: .red)
            SummaryTile(title: "Max HR", value: PulsarRunFormatters.heartRate(summary.maxHeartRate), unit: "bpm", symbol: "bolt.heart.fill", tint: .red)
        }
    }

    private var charts: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !summary.splits.isEmpty {
                chartCard(title: "Pace by Split", symbol: "chart.bar.fill") {
                    Chart(summary.splits) { split in
                        BarMark(
                            x: .value("Split", split.index),
                            y: .value("Pace", split.paceSecondsPerKilometer ?? 0)
                        )
                        .foregroundStyle(.green.gradient)
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisValueLabel {
                                if let seconds = value.as(Double.self) {
                                    Text(PulsarRunFormatters.pace(seconds).replacingOccurrences(of: " /km", with: ""))
                                }
                            }
                        }
                    }
                    .frame(height: 170)
                }
            }

            if routeAltitudeSamples.count > 1 {
                chartCard(title: "Elevation", symbol: "mountain.2.fill") {
                    Chart(routeAltitudeSamples) { sample in
                        LineMark(
                            x: .value("Point", sample.index),
                            y: .value("Elevation", sample.altitude)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(.green)
                        AreaMark(
                            x: .value("Point", sample.index),
                            y: .value("Elevation", sample.altitude)
                        )
                        .foregroundStyle(.green.opacity(0.16))
                    }
                    .frame(height: 170)
                }
            }
        }
    }

    private func chartCard<Content: View>(title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        PulsarRunGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: symbol)
                    .font(.headline.weight(.bold))
                content()
            }
        }
    }

    @ViewBuilder
    private var splits: some View {
        if !summary.splits.isEmpty {
            PulsarRunGlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Splits")
                        .font(.headline.weight(.bold))
                    ForEach(summary.splits) { split in
                        HStack {
                            Text("\(split.index)")
                                .font(.headline.weight(.black).monospacedDigit())
                                .frame(width: 30, alignment: .leading)
                            Text(PulsarRunFormatters.distance(split.distanceMeters))
                            Spacer()
                            Text(PulsarRunFormatters.pace(split.paceSecondsPerKilometer))
                                .font(.headline.weight(.bold).monospacedDigit())
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
    }

    private var doneButton: some View {
        Button(action: onDone) {
            Text("Done")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(.green.gradient, in: Capsule(style: .continuous))
        }
        .buttonStyle(PulsarRunPressStyle())
    }

    private var summaryBackground: some View {
        LinearGradient(
            colors: [Color(.systemBackground), Color.green.opacity(0.10), Color(.secondarySystemBackground)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var routeCoordinates: [CLLocationCoordinate2D] {
        summary.route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private var routeAltitudeSamples: [AltitudeSample] {
        summary.route.enumerated().compactMap { index, point in
            guard let altitude = point.altitude else { return nil }
            return AltitudeSample(index: index, altitude: altitude)
        }
    }
}

private struct AltitudeSample: Identifiable {
    var id: Int { index }
    var index: Int
    var altitude: Double
}

private struct SummaryTile: View {
    var title: String
    var value: String
    var unit: String? = nil
    var symbol: String
    var tint: Color = .green

    var body: some View {
        PulsarRunGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(tint)
                Text(value)
                    .font(.system(size: 24, weight: .black, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                HStack(spacing: 4) {
                    Text(title)
                    if let unit { Text(unit) }
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    PulsarRunSummaryView(
        summary: PulsarRunSummary(
            id: UUID(),
            workoutUUID: nil,
            startedAt: Date().addingTimeInterval(-2_800),
            endedAt: Date(),
            source: .appleWatch,
            distanceMeters: 6_240,
            elapsedTime: 2_812,
            movingTime: 2_640,
            activeEnergyKilocalories: 530,
            elevationGainMeters: 76,
            averageHeartRate: 152,
            maxHeartRate: 178,
            steps: 7_820,
            averageCadenceStepsPerMinute: 168,
            route: [],
            splits: [
                PulsarRunSplit(index: 1, distanceMeters: 1_000, movingTime: 310, elevationGainMeters: 6, averageHeartRate: 145),
                PulsarRunSplit(index: 2, distanceMeters: 1_000, movingTime: 298, elevationGainMeters: 4, averageHeartRate: 151)
            ]
        ),
        onDone: {}
    )
}
