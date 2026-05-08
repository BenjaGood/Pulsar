//
//  PulsarLiveRunView.swift
//  Pulsar
//

import MapKit
import SwiftUI
import UIKit

struct PulsarLiveRunView: View {
    @ObservedObject var coordinator: PulsarRunCoordinator
    var onClose: () -> Void

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showingFinishConfirmation = false
    @State private var mapFirst = true

    var body: some View {
        ZStack(alignment: .bottom) {
            liveMap
                .ignoresSafeArea()

            VStack(spacing: 12) {
                topBar
                Spacer()
                metricsDeck
                controls
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 18)
        }
        .persistentSystemOverlays(.hidden)
        .onChange(of: coordinator.snapshot.route.count) { _, _ in
            updateCamera()
        }
        .confirmationDialog("Finish this run?", isPresented: $showingFinishConfirmation, titleVisibility: .visible) {
            Button("Finish Run", role: .destructive) {
                coordinator.finish()
            }
            Button("Keep Running", role: .cancel) {}
        }
    }

    private var liveMap: some View {
        Map(position: $cameraPosition) {
            UserAnnotation()
            if routeCoordinates.count > 1 {
                MapPolyline(coordinates: routeCoordinates)
                    .stroke(.green, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: routeCoordinates)
                    .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Label(coordinator.snapshot.source.label, systemImage: coordinator.snapshot.source == .appleWatch ? "applewatch" : "iphone")
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            Button {
                mapFirst.toggle()
            } label: {
                Image(systemName: mapFirst ? "rectangle.grid.2x2.fill" : "map.fill")
                    .font(.headline.weight(.bold))
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
        }
    }

    private var metricsDeck: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DISTANCE")
                        .font(.caption2.weight(.black))
                        .tracking(1.1)
                        .foregroundStyle(.secondary)
                    Text(PulsarRunFormatters.compactDistance(coordinator.snapshot.distanceMeters))
                        .font(.system(size: 56, weight: .black, design: .rounded).monospacedDigit())
                    Text("kilometers")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                phasePill
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                RunMetricTile(title: "Elapsed", value: PulsarRunFormatters.duration(coordinator.snapshot.elapsedTime), symbol: "timer")
                RunMetricTile(title: "Moving", value: PulsarRunFormatters.duration(coordinator.snapshot.movingTime), symbol: "figure.run")
                RunMetricTile(title: "Pace", value: PulsarRunFormatters.pace(coordinator.snapshot.currentPaceSecondsPerKilometer), symbol: "speedometer")
                RunMetricTile(title: "Avg Pace", value: PulsarRunFormatters.pace(coordinator.snapshot.averagePaceSecondsPerKilometer), symbol: "chart.line.uptrend.xyaxis")
                RunMetricTile(title: "Split", value: PulsarRunFormatters.pace(coordinator.snapshot.splitPaceSecondsPerKilometer), symbol: "\(coordinator.snapshot.activeSplitIndex).circle")
                RunMetricTile(title: "Heart", value: PulsarRunFormatters.heartRate(coordinator.snapshot.currentHeartRate), unit: "bpm", symbol: "heart.fill", tint: .red)
                RunMetricTile(title: "Calories", value: PulsarRunFormatters.calories(coordinator.snapshot.activeEnergyKilocalories), unit: "cal", symbol: "flame.fill", tint: .orange)
                RunMetricTile(title: "Gain", value: PulsarRunFormatters.elevation(coordinator.snapshot.elevationGainMeters), symbol: "mountain.2.fill", tint: .green)
                RunMetricTile(title: "Cadence", value: PulsarRunFormatters.cadence(coordinator.snapshot.cadenceStepsPerMinute), symbol: "shoeprints.fill", tint: .cyan)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
    }

    private var phasePill: some View {
        Text(phaseText)
            .font(.caption.weight(.black))
            .foregroundStyle(coordinator.snapshot.phase == .paused ? .orange : .green)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background((coordinator.snapshot.phase == .paused ? Color.orange : Color.green).opacity(0.14), in: Capsule())
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                if coordinator.snapshot.phase == .paused {
                    coordinator.resume()
                } else {
                    coordinator.pause()
                }
            } label: {
                Label(coordinator.snapshot.phase == .paused ? "Resume" : "Pause", systemImage: coordinator.snapshot.phase == .paused ? "play.fill" : "pause.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(RunControlButtonStyle(tint: coordinator.snapshot.phase == .paused ? .green : .orange))

            Button {
                showingFinishConfirmation = true
            } label: {
                Label("Finish", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(RunControlButtonStyle(tint: .red))
        }
        .disabled(coordinator.snapshot.phase == .finishing || coordinator.snapshot.phase == .connectingToWatch)
    }

    private var phaseText: String {
        switch coordinator.snapshot.phase {
        case .connectingToWatch: "WATCH"
        case .paused: "PAUSED"
        case .finishing: "SAVING"
        default: "LIVE"
        }
    }

    private var routeCoordinates: [CLLocationCoordinate2D] {
        coordinator.snapshot.route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private func updateCamera() {
        guard let last = routeCoordinates.last else { return }
        withAnimation(.smooth(duration: 0.6)) {
            cameraPosition = .region(MKCoordinateRegion(center: last, latitudinalMeters: 520, longitudinalMeters: 520))
        }
    }
}

private struct RunMetricTile: View {
    var title: String
    var value: String
    var unit: String? = nil
    var symbol: String
    var tint: Color = .green

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
            }
            Text(value)
                .font(.system(size: 18, weight: .black, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.62)
            HStack(spacing: 4) {
                Text(title)
                if let unit { Text(unit) }
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(minHeight: 92, alignment: .leading)
        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct RunControlButtonStyle: ButtonStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .padding(.vertical, 16)
            .background(tint.gradient, in: Capsule(style: .continuous))
            .shadow(color: tint.opacity(configuration.isPressed ? 0.18 : 0.34), radius: configuration.isPressed ? 8 : 18, y: 9)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
