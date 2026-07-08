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
    @State private var lastCameraUpdateAt = Date.distantPast
    @State private var lastCameraCenter: CLLocationCoordinate2D?
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
            title: activeWorkoutKind.isOutdoorDistanceWorkout ? activeWorkoutKind.displayName : activeWorkoutKind.nonGPSDashboardTitle,
            subtitle: activeWorkoutKind.isOutdoorDistanceWorkout ? activeWorkoutKind.outdoorTitle : activeWorkoutKind.nonGPSDashboardSubtitle,
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
            insightTitle: activeWorkoutKind.nonGPSInsightTitle,
            intensityTitle: phase == .paused ? "Paused" : zone?.title ?? fallbackIntensityTitle,
            intensitySubtitle: phase == .paused ? "Metrics held" : zone?.detail ?? fallbackIntensitySubtitle,
            nowPlaying: musicManager.track,
            metrics: dashboardMetrics(zone: zone),
            banners: dashboardBanners,
            controlsDisabled: coordinator.snapshot.phase == .finishing ||
                coordinator.snapshot.phase == .connectingToWatch ||
                isQuiescingMap,
            musicControlsDisabled: !musicManager.track.isAvailable,
            presentationStyle: activeWorkoutKind.isOutdoorDistanceWorkout ? .classic : .premiumNonGPS
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
        guard activeWorkoutKind.isOutdoorDistanceWorkout else {
            return nonGPSDashboardMetrics(zone: zone)
        }

        return [
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

    private func nonGPSDashboardMetrics(zone: PulsarHeartRateZone?) -> [PulsarLiveWorkoutMetric] {
        var metrics: [PulsarLiveWorkoutMetric] = [
            PulsarLiveWorkoutMetric(
                title: "Time",
                value: PulsarRunFormatters.duration(coordinator.snapshot.elapsedTime),
                unit: "Elapsed",
                symbolName: "timer",
                tint: .green
            ),
            PulsarLiveWorkoutMetric(
                title: "Calories",
                value: coordinator.snapshot.activeEnergyKilocalories.map(PulsarRunFormatters.calories) ?? "--",
                unit: "kcal",
                symbolName: "flame.fill",
                tint: .orange
            ),
            PulsarLiveWorkoutMetric(
                title: "Heart Rate",
                value: coordinator.snapshot.currentHeartRate.map { "\(Int($0.rounded()))" } ?? "--",
                unit: "bpm",
                symbolName: "heart.fill",
                tint: zone?.color ?? .gray
            ),
            PulsarLiveWorkoutMetric(
                title: "Average HR",
                value: coordinator.snapshot.averageHeartRate.map { "\(Int($0.rounded()))" } ?? "--",
                unit: "bpm",
                symbolName: "heart.text.square.fill",
                tint: coordinator.snapshot.averageHeartRate == nil ? .gray : .pink
            ),
            PulsarLiveWorkoutMetric(
                title: "Zone",
                value: zone.map { "Z\($0.number)" } ?? "--",
                unit: zone?.title,
                symbolName: "gauge.with.dots.needle.67percent",
                tint: zone?.color ?? .gray
            )
        ]

        if let stepCount = coordinator.snapshot.stepCount, activeWorkoutKind.shouldShowStepsMetric {
            metrics.append(
                PulsarLiveWorkoutMetric(
                    title: "Steps",
                    value: "\(stepCount)",
                    unit: "steps",
                    symbolName: "shoeprints.fill",
                    tint: .mint
                )
            )
        }

        if let cadence = coordinator.snapshot.cadenceStepsPerMinute, activeWorkoutKind.shouldShowCadenceMetric {
            metrics.append(
                PulsarLiveWorkoutMetric(
                    title: "Cadence",
                    value: PulsarRunFormatters.cadence(cadence),
                    unit: "spm",
                    symbolName: "metronome.fill",
                    tint: .cyan
                )
            )
        }

        return metrics
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
        let route = coordinator.snapshot.route
        let maxDisplayPoints = 700
        guard route.count > maxDisplayPoints else {
            return route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        }

        let stride = max(1, route.count / maxDisplayPoints)
        var coordinates = route.enumerated().compactMap { index, point -> CLLocationCoordinate2D? in
            guard index.isMultiple(of: stride) else { return nil }
            return CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
        }
        if let last = route.last {
            let lastCoordinate = CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude)
            if coordinates.last.map({ $0.latitude != lastCoordinate.latitude || $0.longitude != lastCoordinate.longitude }) ?? true {
                coordinates.append(lastCoordinate)
            }
        }
        return coordinates
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

    private var fallbackIntensityTitle: String {
        activeWorkoutKind.isOutdoorDistanceWorkout ? "Waiting for Data" : activeWorkoutKind.defaultNonGPSIntensityTitle
    }

    private var fallbackIntensitySubtitle: String {
        activeWorkoutKind.isOutdoorDistanceWorkout ? "No Heart Rate Available" : activeWorkoutKind.defaultNonGPSIntensitySubtitle
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
        guard let lastPoint = coordinator.snapshot.route.last else { return }
        let last = CLLocationCoordinate2D(latitude: lastPoint.latitude, longitude: lastPoint.longitude)
        let now = Date()
        if let lastCameraCenter {
            let previousLocation = CLLocation(latitude: lastCameraCenter.latitude, longitude: lastCameraCenter.longitude)
            let nextLocation = CLLocation(latitude: last.latitude, longitude: last.longitude)
            let movedMeters = nextLocation.distance(from: previousLocation)
            guard movedMeters >= 35 || now.timeIntervalSince(lastCameraUpdateAt) >= 4 else { return }
        }
        lastCameraCenter = last
        lastCameraUpdateAt = now
        withAnimation(.smooth(duration: 0.45)) {
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

private extension PulsarOutdoorWorkoutKind {
    var nonGPSDashboardTitle: String {
        switch self {
        case .indoorRunning:
            "Indoor Running"
        case .strength:
            "Strength Training"
        case .hiit:
            "HIIT"
        case .yoga:
            "Yoga"
        case .pilates:
            "Pilates"
        case .stretching:
            "Stretching"
        case .core:
            "Core"
        case .mobility:
            "Mobility"
        case .boxing:
            "Boxing"
        case .dance:
            "Dance"
        case .rowing:
            "Rowing"
        case .swimming:
            "Swimming"
        case .elliptical:
            "Elliptical"
        case .stairClimber:
            "Stair Climber"
        case .cooldown:
            "Cooldown"
        case .other:
            "Workout"
        case .running, .walking, .hiking, .cycling:
            displayName
        }
    }

    var nonGPSDashboardSubtitle: String {
        switch self {
        case .indoorRunning:
            "Treadmill"
        case .strength:
            "Functional Strength"
        case .hiit:
            "Intervals"
        case .yoga, .pilates, .stretching, .mobility, .cooldown:
            "Recovery"
        case .core:
            "Core Training"
        case .boxing:
            "Conditioning"
        case .dance:
            "Rhythm"
        case .rowing, .elliptical, .stairClimber:
            "Indoor Cardio"
        case .swimming:
            "Pool"
        case .other:
            "Custom"
        case .running, .walking, .hiking, .cycling:
            outdoorTitle
        }
    }

    var nonGPSInsightTitle: String {
        switch self {
        case .strength:
            "Workout Load"
        case .yoga, .pilates, .stretching, .mobility, .cooldown:
            "Recovery Load"
        default:
            "Workout Intensity"
        }
    }

    var defaultNonGPSIntensityTitle: String {
        switch self {
        case .strength:
            "Moderate"
        case .yoga, .pilates, .stretching, .mobility, .cooldown:
            "Steady"
        default:
            "Moderate"
        }
    }

    var defaultNonGPSIntensitySubtitle: String {
        switch self {
        case .strength:
            "Good training stimulus."
        case .yoga, .pilates, .stretching, .mobility, .cooldown:
            "Smooth effort. Keep breathing."
        case .hiit, .boxing:
            "Controlled intensity. Keep it sharp."
        default:
            "Great pace. Keep it up."
        }
    }

    var shouldShowStepsMetric: Bool {
        switch self {
        case .hiit, .dance, .boxing, .elliptical, .stairClimber:
            true
        default:
            false
        }
    }

    var shouldShowCadenceMetric: Bool {
        switch self {
        case .hiit, .dance, .elliptical, .stairClimber:
            true
        default:
            false
        }
    }
}
