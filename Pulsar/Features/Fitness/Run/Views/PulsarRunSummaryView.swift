//
//  PulsarRunSummaryView.swift
//  Pulsar
//

import Charts
import MapKit
import SwiftUI

struct PulsarRunSummaryView: View {
    var summary: PulsarRunSummary
    var onDone: (() -> Void)? = nil
    @State private var isShowingShareComposer = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                routeMap
                heroStats
                heartRateSourceCard
                charts
                splits
                actionButtons
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 34)
        }
        .background(summaryBackground)
        .sheet(isPresented: $isShowingShareComposer) {
            PulsarWorkoutShareComposerView(summary: summary)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(summary.workoutKind.outdoorTitle)
                    .pulsarTextStyle(.screenTitle)
                Text(summary.startedAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute()))
                    .pulsarTextStyle(.screenSubtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label(summary.source.label, systemImage: summary.source == .appleWatch ? "applewatch" : "iphone")
                .pulsarTextStyle(.metricLabel)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    @ViewBuilder
    private var routeMap: some View {
        if routeCoordinates.count > 1 {
            VStack(alignment: .leading, spacing: 12) {
                Label("Route", systemImage: "map.fill")
                    .pulsarTextStyle(.cardTitle)
                    .padding(.horizontal, 4)
                Map(initialPosition: routeMapPosition) {
                    MapPolyline(coordinates: routeCoordinates)
                        .stroke(summary.workoutKind.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                    if let startCoordinate = routeCoordinates.first {
                        Marker("Start", systemImage: "record.circle", coordinate: startCoordinate)
                            .tint(.green)
                    }
                    if let endCoordinate = routeCoordinates.last {
                        Marker("Finish", systemImage: "flag.checkered", coordinate: endCoordinate)
                            .tint(summary.workoutKind.accentColor)
                    }
                }
                .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
                .frame(height: 270)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .padding(12)
            .pulsarLiquidGlass(cornerRadius: 30)
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(.white.opacity(0.22), lineWidth: 1)
            }
        } else if shouldShowDistanceMetrics {
            PulsarRunGlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Route", systemImage: "map")
                        .pulsarTextStyle(.cardTitle)
                    Text("Route map will appear here when GPS points are available.")
                        .pulsarTextStyle(.screenSubtitle)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var heroStats: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            SummaryTile(title: "Duration", value: PulsarRunFormatters.duration(summary.elapsedTime), symbol: "timer")

            if shouldShowDistanceMetrics {
                SummaryTile(title: "Distance", value: PulsarRunFormatters.distance(summary.distanceMeters), symbol: "point.topleft.down.curvedto.point.bottomright.up")
                SummaryTile(title: PulsarRunFormatters.paceOrSpeedTitle(for: summary.workoutKind, average: true), value: PulsarRunFormatters.paceOrSpeed(workoutKind: summary.workoutKind, paceSecondsPerKilometer: summary.averagePaceSecondsPerKilometer, speedMetersPerSecond: summary.averageSpeedMetersPerSecond), symbol: "speedometer")
            }

            if summary.movingTime > 0, abs(summary.elapsedTime - summary.movingTime) > 1 {
                SummaryTile(title: "Moving Time", value: PulsarRunFormatters.duration(summary.movingTime), symbol: summary.workoutKind.systemImageName, tint: summary.workoutKind.accentColor)
            }

            if summary.stoppedTime > 1 {
                SummaryTile(title: "Stopped", value: PulsarRunFormatters.duration(summary.stoppedTime), symbol: "pause.circle.fill", tint: .orange)
            }

            SummaryTile(title: "Calories", value: PulsarRunFormatters.calories(summary.activeEnergyKilocalories), symbol: "flame.fill", tint: .orange)

            if shouldShowDistanceMetrics, summary.effectiveElevationGainMeters > 0 {
                SummaryTile(title: "Gain", value: PulsarRunFormatters.elevation(summary.effectiveElevationGainMeters), symbol: "mountain.2.fill", tint: summary.workoutKind.accentColor)
            }

            if shouldShowDistanceMetrics, summary.effectiveElevationLossMeters > 0 {
                SummaryTile(title: "Loss", value: PulsarRunFormatters.elevation(summary.effectiveElevationLossMeters), symbol: "arrow.down.to.line.compact", tint: .blue)
            }

            if summary.averageHeartRate != nil {
                SummaryTile(title: "Avg HR", value: PulsarRunFormatters.heartRate(summary.averageHeartRate), unit: "bpm", symbol: "heart.fill", tint: .red)
            }

            if summary.maxHeartRate != nil {
                SummaryTile(title: "Max HR", value: PulsarRunFormatters.heartRate(summary.maxHeartRate), unit: "bpm", symbol: "bolt.heart.fill", tint: .red)
            }

            if let steps = summary.steps, steps > 0 {
                SummaryTile(title: "Steps", value: steps.formatted(), symbol: "shoeprints.fill", tint: summary.workoutKind.accentColor)
            }

            SummaryTile(title: "Source", value: summary.sourceDeviceName, symbol: summary.source == .appleWatch ? "applewatch" : "iphone", tint: summary.workoutKind.accentColor)
        }
    }

    @ViewBuilder
    private var heartRateSourceCard: some View {
        if let sourceText = summary.heartRateSourceSummaryText {
            Label(sourceText, systemImage: "heart.text.square.fill")
                .pulsarTextStyle(.label)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .pulsarLiquidGlass(cornerRadius: 20)
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
                        .foregroundStyle(summary.workoutKind.accentColor.gradient)
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
                            x: .value("Distance", sample.distanceMeters / 1_000),
                            y: .value("Elevation", sample.elevationMeters)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(summary.workoutKind.accentColor)
                        AreaMark(
                            x: .value("Distance", sample.distanceMeters / 1_000),
                            y: .value("Elevation", sample.elevationMeters)
                        )
                        .foregroundStyle(summary.workoutKind.accentColor.opacity(0.16))
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
                    .pulsarTextStyle(.cardTitle)
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
                        .pulsarTextStyle(.cardTitle)
                    ForEach(summary.splits) { split in
                        HStack {
                            Text("\(split.index)")
                                .pulsarTextStyle(.cardTitle)
                                .monospacedDigit()
                                .frame(width: 30, alignment: .leading)
                            Text(PulsarRunFormatters.distance(split.distanceMeters))
                            Spacer()
                            Text(PulsarRunFormatters.pace(split.paceSecondsPerKilometer))
                                .pulsarTextStyle(.cardTitle)
                                .monospacedDigit()
                        }
                        .pulsarTextStyle(.label)
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                isShowingShareComposer = true
            } label: {
                Label(shareActionTitle, systemImage: "square.and.arrow.up")
                    .pulsarTextStyle(.buttonTitle)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(summary.workoutKind.accentColor.gradient, in: Capsule(style: .continuous))
            }
            .buttonStyle(PulsarRunPressStyle())

            if let onDone {
                Button(action: onDone) {
                    Text("Done")
                        .pulsarTextStyle(.buttonTitle)
                        .foregroundStyle(summary.workoutKind.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(summary.workoutKind.accentColor.opacity(0.12), in: Capsule(style: .continuous))
                }
                .buttonStyle(PulsarRunPressStyle())
            }
        }
    }

    private var summaryBackground: some View {
        LinearGradient(
            colors: [Color(.systemBackground), summary.workoutKind.accentColor.opacity(0.10), Color(.secondarySystemBackground)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var routeCoordinates: [CLLocationCoordinate2D] {
        summary.route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private var routeMapPosition: MapCameraPosition {
        guard let bounds = summary.gpsRoute.bounds else { return .automatic }
        return .region(
            MKCoordinateRegion(
                center: bounds.center,
                span: MKCoordinateSpan(latitudeDelta: bounds.latitudeDelta, longitudeDelta: bounds.longitudeDelta)
            )
        )
    }

    private var shouldShowDistanceMetrics: Bool {
        summary.workoutKind.isOutdoorDistanceWorkout || summary.distanceMeters > 10 || routeCoordinates.count > 1
    }

    private var shareActionTitle: String {
        shouldShowDistanceMetrics ? "Share Route" : "Share"
    }

    private var routeAltitudeSamples: [ElevationSample] {
        shouldShowDistanceMetrics ? summary.gpsRoute.elevationSamples : []
    }
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
                    .pulsarTextStyle(.cardTitle)
                    .foregroundStyle(tint)
                Text(value)
                    .pulsarMonospacedMetric(.metricValue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                HStack(spacing: 4) {
                    Text(title)
                    if let unit { Text(unit) }
                }
                .pulsarTextStyle(.metricLabel)
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
