//
//  WatchRunViews.swift
//  Pulsar Watch App Watch App
//

import SwiftUI
import WatchKit

struct WatchWorkoutHeartbeatIntroView: View {
    var title: String
    var tint: Color = Color(red: 0.72, green: 0.66, blue: 1.00)
    var completionDelayNanoseconds: UInt64 = 380_000_000
    var onCompletion: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentOpacity = 0.0
    @State private var contentOffset: CGFloat = 8
    @State private var drawProgress: CGFloat = 0
    @State private var glowAmount = 0.0
    @State private var isDrifting = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    tint.opacity(0.70),
                    tint.opacity(0.28),
                    .black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(tint.opacity(0.32 + glowAmount * 0.16))
                .blur(radius: 24)
                .frame(width: 132, height: 132)
                .offset(x: isDrifting ? 42 : -18, y: isDrifting ? -54 : -22)
                .scaleEffect(isDrifting ? 1.08 : 0.96)

            Circle()
                .fill(.white.opacity(0.10))
                .blur(radius: 22)
                .frame(width: 112, height: 112)
                .offset(x: isDrifting ? -48 : -24, y: isDrifting ? 62 : 42)

            VStack(spacing: 7) {
                WatchWorkoutPulseLine(drawProgress: drawProgress, glowAmount: glowAmount, tint: tint)
                    .frame(height: 36)
                    .padding(.horizontal, -4)

                Text(title)
                    .pulsarTextStyle(.watchTitle)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.74)

                Text("Personalized Training")
                    .pulsarTextStyle(.watchSubtitle)
                    .foregroundStyle(.white.opacity(0.62))
            }
            .padding(.horizontal, 10)
            .opacity(contentOpacity)
            .offset(y: contentOffset)
        }
        .task {
            await playIntro()
        }
    }

    private func playIntro() async {
        if !reduceMotion {
            withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) {
                isDrifting = true
            }
        }

        withAnimation(.easeOut(duration: 0.28)) {
            contentOpacity = 1
            contentOffset = 0
        }

        try? await Task.sleep(nanoseconds: 150_000_000)
        guard !Task.isCancelled else { return }

        WKInterfaceDevice.current().play(.click)
        withAnimation(.easeInOut(duration: 0.82)) {
            drawProgress = 1
        }

        try? await Task.sleep(nanoseconds: 540_000_000)
        guard !Task.isCancelled else { return }

        WKInterfaceDevice.current().play(.directionUp)
        withAnimation(.easeOut(duration: 0.24)) {
            glowAmount = 1
        }

        try? await Task.sleep(nanoseconds: 180_000_000)
        guard !Task.isCancelled else { return }

        withAnimation(.easeOut(duration: 0.34)) {
            glowAmount = 0
        }

        try? await Task.sleep(nanoseconds: completionDelayNanoseconds)
        guard !Task.isCancelled else { return }
        onCompletion()
    }
}

private struct WatchWorkoutPulseLine: View {
    var drawProgress: CGFloat
    var glowAmount: Double
    var tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var energyProgress: CGFloat = 0.0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                WatchWorkoutPulseLineShape()
                    .trim(from: 0, to: 1)
                    .stroke(
                        .white.opacity(0.08),
                        style: StrokeStyle(lineWidth: 0.9, lineCap: .round, lineJoin: .round)
                    )

                WatchWorkoutPulseLineShape()
                    .trim(from: 0, to: clampedProgress)
                    .stroke(
                        tint.opacity(0.40 + glowAmount * 0.22),
                        style: StrokeStyle(lineWidth: 13, lineCap: .round, lineJoin: .round)
                    )
                    .blur(radius: 9)

                WatchWorkoutPulseLineShape()
                    .trim(from: 0, to: clampedProgress)
                    .stroke(
                        .white.opacity(0.88),
                        style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round)
                    )
                    .shadow(color: .white.opacity(0.14 + glowAmount * 0.20), radius: 5 + glowAmount * 4)

                WatchWorkoutPulseLineShape()
                    .trim(from: highlightStart, to: highlightEnd)
                    .stroke(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.32), .white, tint.opacity(0.78), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round)
                    )
                    .shadow(color: .white.opacity(0.24), radius: 7)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .drawingGroup()
        .onAppear {
            guard !reduceMotion else { return }
            energyProgress = 0.0
            withAnimation(.linear(duration: 1.32).repeatForever(autoreverses: false)) {
                energyProgress = 1.18
            }
        }
    }

    private var clampedProgress: CGFloat {
        max(0, min(drawProgress, 1))
    }

    private var highlightStart: CGFloat {
        guard !reduceMotion else { return max(0, clampedProgress - 0.18) }
        return max(0, min(clampedProgress, energyProgress - 0.18))
    }

    private var highlightEnd: CGFloat {
        guard !reduceMotion else { return clampedProgress }
        return max(highlightStart, min(clampedProgress, energyProgress + 0.04))
    }
}

private struct WatchWorkoutPulseLineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let baseline = rect.minY + rect.height * 0.56

        path.move(to: CGPoint(x: rect.minX, y: baseline))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.22, y: baseline),
            control1: CGPoint(x: rect.minX + rect.width * 0.07, y: baseline - rect.height * 0.03),
            control2: CGPoint(x: rect.minX + rect.width * 0.14, y: baseline + rect.height * 0.03)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.34, y: baseline - rect.height * 0.12),
            control1: CGPoint(x: rect.minX + rect.width * 0.26, y: baseline),
            control2: CGPoint(x: rect.minX + rect.width * 0.28, y: baseline - rect.height * 0.13)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.42, y: baseline),
            control1: CGPoint(x: rect.minX + rect.width * 0.38, y: baseline - rect.height * 0.11),
            control2: CGPoint(x: rect.minX + rect.width * 0.39, y: baseline)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.47, y: baseline + rect.height * 0.20),
            control1: CGPoint(x: rect.minX + rect.width * 0.44, y: baseline + rect.height * 0.04),
            control2: CGPoint(x: rect.minX + rect.width * 0.45, y: baseline + rect.height * 0.18)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.52, y: baseline - rect.height * 0.46),
            control1: CGPoint(x: rect.minX + rect.width * 0.49, y: baseline + rect.height * 0.22),
            control2: CGPoint(x: rect.minX + rect.width * 0.50, y: baseline - rect.height * 0.45)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.58, y: baseline + rect.height * 0.24),
            control1: CGPoint(x: rect.minX + rect.width * 0.54, y: baseline - rect.height * 0.45),
            control2: CGPoint(x: rect.minX + rect.width * 0.55, y: baseline + rect.height * 0.24)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.66, y: baseline),
            control1: CGPoint(x: rect.minX + rect.width * 0.60, y: baseline + rect.height * 0.22),
            control2: CGPoint(x: rect.minX + rect.width * 0.62, y: baseline)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.80, y: baseline - rect.height * 0.15),
            control1: CGPoint(x: rect.minX + rect.width * 0.70, y: baseline - rect.height * 0.02),
            control2: CGPoint(x: rect.minX + rect.width * 0.72, y: baseline - rect.height * 0.15)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: baseline),
            control1: CGPoint(x: rect.minX + rect.width * 0.88, y: baseline - rect.height * 0.15),
            control2: CGPoint(x: rect.minX + rect.width * 0.88, y: baseline)
        )

        return path
    }
}

struct WatchRunEntryView: View {
    @EnvironmentObject private var runManager: WatchRunSessionManager
    var workoutKind: PulsarOutdoorWorkoutKind = .running
    @State private var isShowingOptions = false

    var body: some View {
        ZStack {
            if isShowingOptions {
                WatchRunStartView(workoutKind: workoutKind)
                    .environmentObject(runManager)
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            } else {
                WatchWorkoutHeartbeatIntroView(title: workoutKind.shortName, tint: workoutKind.watchTint) {
                    withAnimation(.smooth(duration: 0.34)) {
                        isShowingOptions = true
                    }
                }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.smooth(duration: 0.34), value: isShowingOptions)
    }
}

struct WatchRunStartView: View {
    @EnvironmentObject private var runManager: WatchRunSessionManager
    var workoutKind: PulsarOutdoorWorkoutKind = .running
    @State private var autoPause = true
    @State private var hapticCues = true
    @State private var countdown: Int?

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(workoutKind.shortName)
                        .pulsarTextStyle(.watchTitle)
                    Text("Start a \(workoutKind.actionName) with HealthKit recording and iPhone mirroring.")
                        .pulsarTextStyle(.watchSubtitle)
                        .foregroundStyle(.secondary)

                    WatchGlassCard {
                        VStack(spacing: 8) {
                            Toggle("Auto-pause", isOn: $autoPause)
                            Toggle("Haptic cues", isOn: $hapticCues)
                        }
                        .pulsarTextStyle(.watchLabel)
                    }

                    Button {
                        Task { await startCountdown() }
                    } label: {
                        Label(workoutKind.startTitle, systemImage: workoutKind.systemImageName)
                            .pulsarTextStyle(.watchButton)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(workoutKind.watchTint)

                    if let message = runManager.message {
                        Text(message)
                            .pulsarTextStyle(.watchSubtitle)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }

            if let countdown {
                Text("\(countdown)")
                    .pulsarMonospacedMetric(.watchHeroValue)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black.opacity(0.62))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .navigationDestination(isPresented: Binding(get: {
            runManager.snapshot.phase == .running || runManager.snapshot.phase == .paused || runManager.snapshot.phase == .finishing
        }, set: { _ in })) {
            WatchLiveRunView()
                .environmentObject(runManager)
        }
    }

    private func startCountdown() async {
        for value in [3, 2, 1] {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                countdown = value
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
        }
        withAnimation(.easeOut(duration: 0.18)) {
            countdown = nil
        }
        await runManager.startOutdoorWorkoutFromWatch(workoutKind, options: PulsarRunOptions(prefersWatchRecorder: true, autoPauseEnabled: autoPause, audioCuesEnabled: hapticCues))
    }
}

struct WatchLiveRunView: View {
    @EnvironmentObject private var runManager: WatchRunSessionManager
    @State private var selectedTab = 0
    @State private var isShowingNowPlaying = false

    var body: some View {
        TabView(selection: $selectedTab) {
            metricsPage
                .tag(0)
            controlsPage
                .tag(1)
        }
        .tabViewStyle(.verticalPage)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $isShowingNowPlaying) {
            NowPlayingView()
        }
    }

    private var metricsPage: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    WKInterfaceDevice.current().play(.click)
                    isShowingNowPlaying = true
                } label: {
                    Image(systemName: "music.note")
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(.thinMaterial, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.16), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Now Playing")

                Spacer()
            }

            HStack {
                Text(primaryMetricValue)
                    .pulsarMonospacedMetric(.watchHeroValue)
                Text(primaryMetricUnit)
                    .pulsarTextStyle(.watchLabel)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                WatchRunMetric(title: "Time", value: PulsarRunFormatters.duration(runManager.snapshot.elapsedTime))
                WatchRunMetric(title: "Calories", value: PulsarRunFormatters.calories(runManager.snapshot.activeEnergyKilocalories), unit: "cal", tint: .orange)
                WatchRunMetric(title: "HR", value: PulsarRunFormatters.heartRate(runManager.snapshot.currentHeartRate), unit: "bpm", tint: .red)
                WatchRunMetric(title: secondaryMetricTitle, value: secondaryMetricValue, tint: runManager.snapshot.workoutKind.watchTint)
            }

            Text(runManager.snapshot.phase == .paused ? "Paused" : "Recording")
                .pulsarTextStyle(.watchLabel)
                .foregroundStyle(runManager.snapshot.phase == .paused ? .orange : runManager.snapshot.workoutKind.watchTint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background((runManager.snapshot.phase == .paused ? Color.orange : runManager.snapshot.workoutKind.watchTint).opacity(0.14), in: Capsule())
        }
        .padding(.horizontal, 8)
    }

    private var primaryMetricValue: String {
        runManager.snapshot.workoutKind.isOutdoorDistanceWorkout
            ? PulsarRunFormatters.compactDistance(runManager.snapshot.distanceMeters)
            : PulsarRunFormatters.duration(runManager.snapshot.elapsedTime)
    }

    private var primaryMetricUnit: String {
        runManager.snapshot.workoutKind.isOutdoorDistanceWorkout ? "km" : runManager.snapshot.workoutKind.shortName
    }

    private var secondaryMetricTitle: String {
        runManager.snapshot.workoutKind.isOutdoorDistanceWorkout
            ? PulsarRunFormatters.paceOrSpeedTitle(for: runManager.snapshot.workoutKind)
            : "State"
    }

    private var secondaryMetricValue: String {
        runManager.snapshot.workoutKind.isOutdoorDistanceWorkout
            ? PulsarRunFormatters.paceOrSpeed(
                workoutKind: runManager.snapshot.workoutKind,
                paceSecondsPerKilometer: runManager.snapshot.currentPaceSecondsPerKilometer,
                speedMetersPerSecond: currentSpeedMetersPerSecond
            ).replacingOccurrences(of: " /km", with: "")
            : (runManager.snapshot.phase == .paused ? "Paused" : "Live")
    }

    private var currentSpeedMetersPerSecond: Double? {
        guard runManager.snapshot.workoutKind == .cycling else { return nil }
        return runManager.snapshot.currentPaceSecondsPerKilometer.map { 1_000 / $0 }
    }

    private var controlsPage: some View {
        VStack(spacing: 8) {
            Button(runManager.snapshot.phase == .paused ? "Resume" : "Pause") {
                runManager.snapshot.phase == .paused ? runManager.resume() : runManager.pause()
            }
            .buttonStyle(.borderedProminent)
            .tint(runManager.snapshot.phase == .paused ? runManager.snapshot.workoutKind.watchTint : .orange)

            Button("Finish", role: .destructive) {
                runManager.finish()
            }
            .buttonStyle(.borderedProminent)

            if runManager.snapshot.phase == .finishing {
                ProgressView("Saving")
                    .pulsarTextStyle(.watchSubtitle)
            }
        }
        .padding(.horizontal, 8)
    }
}

private struct WatchRunMetric: View {
    var title: String
    var value: String
    var unit: String? = nil
    var tint: Color = .cyan

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .pulsarTextStyle(.watchLabel)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .pulsarMonospacedMetric(.watchMetric)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                if let unit {
                    Text(unit)
                        .pulsarTextStyle(.watchLabel)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private extension PulsarOutdoorWorkoutKind {
    var watchTint: Color {
        switch self {
        case .running: .green
        case .walking: Color(red: 0.44, green: 0.72, blue: 1.00)
        case .hiking: Color(red: 0.34, green: 0.82, blue: 0.58)
        case .cycling: Color(red: 0.25, green: 0.78, blue: 0.86)
        case .hiit: Color(red: 1.00, green: 0.61, blue: 0.25)
        case .strength: Color(red: 0.72, green: 0.66, blue: 1.00)
        case .yoga, .stretching, .cooldown: Color(red: 0.72, green: 0.82, blue: 0.46)
        case .pilates, .core, .mobility: Color(red: 0.44, green: 0.72, blue: 1.00)
        case .swimming: Color(red: 0.34, green: 0.68, blue: 1.00)
        case .rowing, .elliptical, .stairClimber: Color(red: 0.25, green: 0.78, blue: 0.86)
        case .dance: Color(red: 1.00, green: 0.44, blue: 0.68)
        case .boxing: Color(red: 1.00, green: 0.46, blue: 0.34)
        case .other: Color(red: 0.68, green: 0.74, blue: 0.84)
        }
    }
}
