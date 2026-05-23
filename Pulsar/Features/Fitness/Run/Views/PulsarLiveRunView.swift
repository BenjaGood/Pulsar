//
//  PulsarLiveRunView.swift
//  Pulsar
//

import MapKit
import SwiftUI
import UIKit

struct PulsarLiveRunView: View {
    @ObservedObject var coordinator: PulsarRunCoordinator
    var workoutKind: PulsarOutdoorWorkoutKind = .running
    var isPreparingForRemoval = false
    var onClose: () -> Void

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showingFinishConfirmation = false
    @State private var mapFirst = true
    @State private var isPreparingToClose = false

    var body: some View {
        ZStack(alignment: .bottom) {
            liveMap
                .ignoresSafeArea()
                .opacity(isQuiescingMap ? 0.001 : 1)

            VStack(spacing: 12) {
                topBar
                Spacer()
                metricsDeck
                controls
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 18)
            .opacity(isQuiescingMap ? 0.92 : 1)
        }
        .persistentSystemOverlays(.hidden)
        .onChange(of: coordinator.snapshot.route.count) { _, _ in
            updateCamera()
        }
        .confirmationDialog("Finish this \(activeWorkoutKind.actionName)?", isPresented: $showingFinishConfirmation, titleVisibility: .visible) {
            Button("Finish \(activeWorkoutKind.shortName)", role: .destructive) {
                coordinator.finish()
            }
            Button("Keep \(activeWorkoutKind.displayName)", role: .cancel) {}
        }
    }

    private var liveMap: some View {
        GeometryReader { proxy in
            if proxy.size.width > 1, proxy.size.height > 1 {
                Map(position: $cameraPosition) {
                    UserAnnotation()
                    if routeCoordinates.count > 1 {
                        MapPolyline(coordinates: routeCoordinates)
                            .stroke(activeWorkoutKind.accentColor, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                        MapPolyline(coordinates: routeCoordinates)
                            .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    }
                }
                .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
                .frame(
                    width: max(proxy.size.width, 1),
                    height: max(proxy.size.height, 1)
                )
            } else {
                Color.clear
                    .frame(minWidth: 1, minHeight: 1)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            PulsarWorkoutToolbarIconButton(
                systemImage: "music.note",
                accessibilityLabel: "Now Playing"
            ) {
                openNowPlaying()
            }

            Label(recorderStatusText, systemImage: recorderStatusSymbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            PulsarWorkoutToolbarIconButton(
                systemImage: "chevron.down",
                accessibilityLabel: "Minimize workout"
            ) {
                beginSafeClose()
            }
            .disabled(isQuiescingMap)

            PulsarWorkoutToolbarIconButton(
                systemImage: mapFirst ? "rectangle.grid.2x2.fill" : "map.fill",
                accessibilityLabel: mapFirst ? "Show metrics first" : "Show map first"
            ) {
                mapFirst.toggle()
            }
            .disabled(isQuiescingMap)
        }
    }

    private var metricsDeck: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(primaryMetricTitle)
                        .font(.caption2.weight(.black))
                        .tracking(1.1)
                        .foregroundStyle(.secondary)
                    Text(primaryMetricValue)
                        .font(.system(size: 56, weight: .black, design: .rounded).monospacedDigit())
                    Text(primaryMetricSubtitle)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                phasePill
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                RunMetricTile(title: "Elapsed", value: PulsarRunFormatters.duration(coordinator.snapshot.elapsedTime), symbol: "timer")
                RunMetricTile(title: "Moving", value: PulsarRunFormatters.duration(coordinator.snapshot.movingTime), symbol: activeWorkoutKind.systemImageName, tint: activeWorkoutKind.accentColor)
                RunMetricTile(title: liveEffortTitle, value: currentEffortValue, symbol: "speedometer")
                RunMetricTile(title: averageEffortTitle, value: averageEffortValue, symbol: "chart.line.uptrend.xyaxis")
                RunMetricTile(title: "Split", value: PulsarRunFormatters.pace(coordinator.snapshot.splitPaceSecondsPerKilometer), symbol: "\(coordinator.snapshot.activeSplitIndex).circle")
                RunMetricTile(title: "Heart", value: PulsarRunFormatters.heartRate(coordinator.snapshot.currentHeartRate), unit: "bpm", symbol: "heart.fill", tint: .red)
                RunMetricTile(title: "Calories", value: PulsarRunFormatters.calories(coordinator.snapshot.activeEnergyKilocalories), unit: "cal", symbol: "flame.fill", tint: .orange)
                RunMetricTile(title: "Gain", value: PulsarRunFormatters.elevation(coordinator.snapshot.elevationGainMeters), symbol: "mountain.2.fill", tint: activeWorkoutKind.accentColor)
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
            .foregroundStyle(coordinator.snapshot.phase == .paused ? .orange : activeWorkoutKind.accentColor)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background((coordinator.snapshot.phase == .paused ? Color.orange : activeWorkoutKind.accentColor).opacity(0.14), in: Capsule())
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
            .buttonStyle(RunControlButtonStyle(tint: coordinator.snapshot.phase == .paused ? activeWorkoutKind.accentColor : .orange))

            Button {
                showingFinishConfirmation = true
            } label: {
                Label("Finish", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(RunControlButtonStyle(tint: .red))
        }
        .disabled(coordinator.snapshot.phase == .finishing || coordinator.snapshot.phase == .connectingToWatch)
        .disabled(isQuiescingMap)
    }

    private var phaseText: String {
        switch coordinator.snapshot.phase {
        case .connectingToWatch: "WATCH"
        case .paused: "PAUSED"
        case .finishing: "SAVING"
        default: "LIVE"
        }
    }

    private var recorderStatusText: String {
        switch coordinator.snapshot.phase {
        case .connectingToWatch:
            coordinator.snapshot.statusMessage ?? "Opening on Apple Watch..."
        case .paused:
            coordinator.snapshot.source == .appleWatch ? "Paused on Apple Watch" : "Paused on iPhone"
        case .finishing:
            "Saving workout"
        default:
            coordinator.snapshot.source == .appleWatch ? "Apple Watch recording" : "iPhone recording"
        }
    }

    private var recorderStatusSymbol: String {
        coordinator.snapshot.source == .appleWatch ? "applewatch" : "iphone"
    }

    private var routeCoordinates: [CLLocationCoordinate2D] {
        coordinator.snapshot.route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private var activeWorkoutKind: PulsarOutdoorWorkoutKind {
        coordinator.snapshot.phase == .idle ? workoutKind : coordinator.snapshot.workoutKind
    }

    private var isQuiescingMap: Bool {
        isPreparingToClose || isPreparingForRemoval
    }

    private var primaryMetricTitle: String {
        activeWorkoutKind.isOutdoorDistanceWorkout ? "DISTANCE" : activeWorkoutKind.displayName.uppercased()
    }

    private var primaryMetricValue: String {
        activeWorkoutKind.isOutdoorDistanceWorkout
            ? PulsarRunFormatters.compactDistance(coordinator.snapshot.distanceMeters)
            : PulsarRunFormatters.duration(coordinator.snapshot.elapsedTime)
    }

    private var primaryMetricSubtitle: String {
        activeWorkoutKind.isOutdoorDistanceWorkout ? "kilometers" : "elapsed time"
    }

    private var liveEffortTitle: String {
        PulsarRunFormatters.paceOrSpeedTitle(for: activeWorkoutKind)
    }

    private var averageEffortTitle: String {
        PulsarRunFormatters.paceOrSpeedTitle(for: activeWorkoutKind, average: true)
    }

    private var currentEffortValue: String {
        PulsarRunFormatters.paceOrSpeed(
            workoutKind: activeWorkoutKind,
            paceSecondsPerKilometer: coordinator.snapshot.currentPaceSecondsPerKilometer,
            speedMetersPerSecond: currentSpeedMetersPerSecond
        )
    }

    private var averageEffortValue: String {
        PulsarRunFormatters.paceOrSpeed(
            workoutKind: activeWorkoutKind,
            paceSecondsPerKilometer: coordinator.snapshot.averagePaceSecondsPerKilometer,
            speedMetersPerSecond: averageSpeedMetersPerSecond
        )
    }

    private var currentSpeedMetersPerSecond: Double? {
        guard activeWorkoutKind == .cycling else { return nil }
        return coordinator.snapshot.currentPaceSecondsPerKilometer.map { 1_000 / $0 }
    }

    private var averageSpeedMetersPerSecond: Double? {
        guard activeWorkoutKind == .cycling,
              coordinator.snapshot.movingTime > 0,
              coordinator.snapshot.distanceMeters > 0 else { return nil }
        return coordinator.snapshot.distanceMeters / coordinator.snapshot.movingTime
    }

    private func updateCamera() {
        guard !isQuiescingMap else { return }
        guard let last = routeCoordinates.last else { return }
        withAnimation(.smooth(duration: 0.6)) {
            cameraPosition = .region(MKCoordinateRegion(center: last, latitudinalMeters: 520, longitudinalMeters: 520))
        }
    }

    private func beginSafeClose() {
        guard !isPreparingToClose else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withTransaction(Transaction(animation: .easeOut(duration: 0.12))) {
            isPreparingToClose = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            onClose()
        }
    }

    private func openNowPlaying() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let urls = ["music://nowplaying", "music://"].compactMap(URL.init(string:))
        guard let url = urls.first else { return }
        UIApplication.shared.open(url)
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
