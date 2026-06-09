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
    var profile: UserProfile = .empty
    var isPreparingForRemoval = false
    var onClose: () -> Void

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var mapFirst = true
    @State private var isPreparingToClose = false
    @StateObject private var musicManager = PulsarNowPlayingMusicManager()

    var body: some View {
        PulsarLiveWorkoutDashboardView(
            state: dashboardState,
            closeSymbolName: "chevron.down",
            closeAccessibilityLabel: "Minimize workout",
            secondaryActionSymbolName: mapFirst ? "rectangle.grid.2x2.fill" : "map.fill",
            secondaryActionAccessibilityLabel: mapFirst ? "Show metrics background" : "Show map background",
            onClose: beginSafeClose,
            onSecondaryAction: toggleMapBackground,
            onTogglePause: togglePause,
            onEnd: {
                coordinator.finish()
            },
            onOpenNowPlaying: openNowPlaying,
            onToggleMusicPlayback: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                musicManager.playPause()
            },
            onNextTrack: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                musicManager.nextTrack()
            },
            onPreviousTrack: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                musicManager.previousTrack()
            }
        ) {
            liveBackground
        }
        .task {
            await musicManager.start()
        }
        .onChange(of: coordinator.snapshot.route.count) { _, _ in
            updateCamera()
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: coordinator.heartRateSourceBanner)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: coordinator.adaptiveWorkoutCoaching?.id)
    }

    @ViewBuilder
    private var liveBackground: some View {
        if mapFirst, !isQuiescingMap {
            liveMap
                .ignoresSafeArea()
        } else {
            PulsarLiveWorkoutAmbientBackground(
                tint: activeWorkoutKind.accentColor,
                glowColor: activeWorkoutKind.glowColor
            )
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

    private var dashboardState: PulsarLiveWorkoutDashboardState {
        let zoneProfile = PulsarHeartRateZoneProfile(profile: profile)
        let zone = zoneProfile.zone(for: coordinator.snapshot.currentHeartRate)
        let phase = dashboardPhase

        return PulsarLiveWorkoutDashboardState(
            title: activeWorkoutKind.displayName,
            subtitle: activeWorkoutKind.outdoorTitle,
            symbolName: activeWorkoutKind.systemImageName,
            tint: activeWorkoutKind.accentColor,
            glowColor: activeWorkoutKind.glowColor,
            phase: phase,
            statusText: dashboardStatusText,
            recorderStatusText: recorderStatusText,
            recorderStatusSymbolName: recorderStatusSymbol,
            primaryMetricTitle: primaryMetricTitle,
            primaryMetricValue: primaryMetricValue,
            primaryMetricSubtitle: primaryMetricSubtitle,
            elapsedTime: coordinator.snapshot.elapsedTime,
            currentHeartRate: coordinator.snapshot.currentHeartRate,
            heartRateZone: zone,
            zoneProfile: zoneProfile,
            intensityTitle: phase == .paused ? "Paused" : zone?.title ?? "Waiting for Data",
            intensitySubtitle: phase == .paused ? "Metrics held" : zone?.detail ?? "No Heart Rate Available",
            nowPlaying: musicManager.track,
            metrics: dashboardMetrics(zone: zone),
            banners: dashboardBanners,
            controlsDisabled: coordinator.snapshot.phase == .finishing ||
                coordinator.snapshot.phase == .connectingToWatch ||
                isQuiescingMap,
            musicControlsDisabled: !musicManager.track.isAvailable
        )
    }

    private var dashboardPhase: PulsarLiveWorkoutDashboardPhase {
        switch coordinator.snapshot.phase {
        case .connectingToWatch, .requestingPermissions, .countingDown:
            .preparing
        case .paused:
            .paused
        case .finishing:
            .finishing
        case .finished:
            .finished
        case .idle, .failed:
            .finished
        case .running:
            .running
        }
    }

    private var dashboardStatusText: String {
        switch coordinator.snapshot.phase {
        case .connectingToWatch:
            "WATCH"
        case .failed:
            "CHECK"
        default:
            dashboardPhase.statusText
        }
    }

    private var dashboardBanners: [PulsarLiveWorkoutBanner] {
        var banners: [PulsarLiveWorkoutBanner] = []

        if let message = coordinator.heartRateSourceBanner {
            banners.append(
                PulsarLiveWorkoutBanner(
                    id: "heart-source",
                    title: message,
                    message: nil,
                    symbolName: "heart.text.square.fill",
                    tint: .red
                )
            )
        }

        if let coaching = coordinator.adaptiveWorkoutCoaching {
            banners.append(
                PulsarLiveWorkoutBanner(
                    id: coaching.id,
                    title: coaching.title,
                    message: coaching.message,
                    symbolName: coachingSymbol(for: coaching),
                    tint: coachingTint(for: coaching)
                )
            )
        }

        return banners
    }

    private func dashboardMetrics(zone: PulsarHeartRateZone?) -> [PulsarLiveWorkoutMetric] {
        [
            PulsarLiveWorkoutMetric(
                title: "Elapsed",
                value: PulsarRunFormatters.duration(coordinator.snapshot.elapsedTime),
                symbolName: "timer",
                tint: activeWorkoutKind.accentColor
            ),
            PulsarLiveWorkoutMetric(
                title: "Calories",
                value: coordinator.snapshot.activeEnergyKilocalories.map(PulsarRunFormatters.calories) ?? "Calories Unavailable",
                unit: coordinator.snapshot.activeEnergyKilocalories == nil ? nil : "cal",
                symbolName: "flame.fill",
                tint: .orange
            ),
            PulsarLiveWorkoutMetric(
                title: activeWorkoutKind.isOutdoorDistanceWorkout ? "Distance" : "Moving",
                value: activeWorkoutKind.isOutdoorDistanceWorkout
                    ? PulsarRunFormatters.distance(coordinator.snapshot.distanceMeters)
                    : PulsarRunFormatters.duration(coordinator.snapshot.movingTime),
                symbolName: activeWorkoutKind.systemImageName,
                tint: activeWorkoutKind.accentColor
            ),
            PulsarLiveWorkoutMetric(
                title: liveEffortTitle,
                value: currentEffortValue,
                symbolName: "speedometer",
                tint: .cyan
            ),
            PulsarLiveWorkoutMetric(
                title: "Heart",
                value: coordinator.snapshot.currentHeartRate.map { "\(Int($0.rounded()))" } ?? "No Heart Rate Available",
                unit: coordinator.snapshot.currentHeartRate == nil ? nil : "bpm",
                symbolName: "heart.fill",
                tint: zone?.color ?? .red
            ),
            PulsarLiveWorkoutMetric(
                title: "Cadence",
                value: coordinator.snapshot.cadenceStepsPerMinute.map(PulsarRunFormatters.cadence) ?? "Cadence Unavailable",
                symbolName: "shoeprints.fill",
                tint: .mint
            )
        ]
    }

    private var recorderStatusText: String {
        switch coordinator.snapshot.phase {
        case .connectingToWatch:
            coordinator.snapshot.statusMessage ?? "Opening on Apple Watch..."
        case .paused:
            coordinator.snapshot.source == .appleWatch ? "Paused on Apple Watch" : "Paused on iPhone"
        case .finishing:
            coordinator.snapshot.statusMessage ?? "Finishing workout..."
        default:
            if let heartRateSourceMessage = coordinator.heartRateSourceStatus?.message {
                heartRateSourceMessage
            } else {
                coordinator.snapshot.source == .appleWatch ? "Apple Watch recording" : "iPhone recording"
            }
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

    private var currentEffortValue: String {
        let value = PulsarRunFormatters.paceOrSpeed(
            workoutKind: activeWorkoutKind,
            paceSecondsPerKilometer: coordinator.snapshot.currentPaceSecondsPerKilometer,
            speedMetersPerSecond: currentSpeedMetersPerSecond
        )
        guard value != "--" else {
            return activeWorkoutKind == .cycling ? "Speed Unavailable" : "Pace Unavailable"
        }
        return value
    }

    private var currentSpeedMetersPerSecond: Double? {
        guard activeWorkoutKind == .cycling else { return nil }
        return coordinator.snapshot.currentPaceSecondsPerKilometer.map { 1_000 / $0 }
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

    private func togglePause() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if coordinator.snapshot.phase == .paused {
            coordinator.resume()
        } else {
            coordinator.pause()
        }
    }

    private func toggleMapBackground() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.smooth(duration: 0.28)) {
            mapFirst.toggle()
        }
    }

    private func coachingTint(for coaching: AdaptiveWorkoutCoaching) -> Color {
        switch coaching.severity {
        case .informational:
            .cyan
        case .caution, .protective:
            .orange
        }
    }

    private func coachingSymbol(for coaching: AdaptiveWorkoutCoaching) -> String {
        switch coaching.severity {
        case .informational:
            "sparkles"
        case .caution:
            "heart.text.square.fill"
        case .protective:
            "shield.lefthalf.filled"
        }
    }

    private func openNowPlaying() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let urls = ["music://nowplaying", "music://"].compactMap(URL.init(string:))
        guard let url = urls.first else { return }
        UIApplication.shared.open(url)
    }
}
