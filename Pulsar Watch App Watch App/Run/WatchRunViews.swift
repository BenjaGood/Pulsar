//
//  WatchRunViews.swift
//  Pulsar Watch App Watch App
//

import SwiftUI
import WatchKit

struct WatchRunEntryView: View {
    @EnvironmentObject private var runManager: WatchRunSessionManager
    @State private var isShowingOptions = false
    @State private var introOpacity = 0.0
    @State private var pulseScale = 0.82
    @State private var glowOpacity = 0.0

    var body: some View {
        ZStack {
            if isShowingOptions {
                WatchRunStartView()
                    .environmentObject(runManager)
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            } else {
                watchHeartbeatIntro
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.smooth(duration: 0.34), value: isShowingOptions)
        .task {
            await playIntro()
        }
    }

    private var watchHeartbeatIntro: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.42, green: 0.02, blue: 0.05),
                    Color(red: 0.10, green: 0.00, blue: 0.02),
                    .black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.red.opacity(glowOpacity))
                .blur(radius: 18)
                .frame(width: 92, height: 92)

            VStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 46, weight: .black))
                    .foregroundStyle(.white)
                    .shadow(color: .red.opacity(glowOpacity + 0.24), radius: 16)
                    .scaleEffect(pulseScale)

                Text("Run")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)

                Text("Pulsar")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.62))
            }
            .opacity(introOpacity)
        }
    }

    private func playIntro() async {
        withAnimation(.easeOut(duration: 0.24)) {
            introOpacity = 1
        }
        withAnimation(.spring(response: 0.52, dampingFraction: 0.72)) {
            pulseScale = 1
        }

        try? await Task.sleep(nanoseconds: 430_000_000)
        WKInterfaceDevice.current().play(.click)
        withAnimation(.spring(response: 0.18, dampingFraction: 0.48)) {
            pulseScale = 1.12
            glowOpacity = 0.42
        }

        try? await Task.sleep(nanoseconds: 150_000_000)
        WKInterfaceDevice.current().play(.directionUp)
        withAnimation(.easeOut(duration: 0.30)) {
            pulseScale = 1
            glowOpacity = 0.12
        }

        try? await Task.sleep(nanoseconds: 380_000_000)
        guard !Task.isCancelled else { return }
        withAnimation(.smooth(duration: 0.34)) {
            isShowingOptions = true
        }
    }
}

struct WatchRunStartView: View {
    @EnvironmentObject private var runManager: WatchRunSessionManager
    @State private var autoPause = true
    @State private var hapticCues = true
    @State private var countdown: Int?

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Run")
                        .font(.title2.weight(.bold))
                    Text("Start an outdoor run with HealthKit recording and iPhone mirroring.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    WatchGlassCard {
                        VStack(spacing: 8) {
                            Toggle("Auto-pause", isOn: $autoPause)
                            Toggle("Haptic cues", isOn: $hapticCues)
                        }
                        .font(.caption.weight(.semibold))
                    }

                    Button {
                        Task { await startCountdown() }
                    } label: {
                        Label("Start Run", systemImage: "figure.run")
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    if let message = runManager.message {
                        Text(message)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }

            if let countdown {
                Text("\(countdown)")
                    .font(.system(size: 74, weight: .black, design: .rounded))
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
        await runManager.startRunFromWatch(options: PulsarRunOptions(prefersWatchRecorder: true, autoPauseEnabled: autoPause, audioCuesEnabled: hapticCues))
    }
}

struct WatchLiveRunView: View {
    @EnvironmentObject private var runManager: WatchRunSessionManager
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            metricsPage
                .tag(0)
            controlsPage
                .tag(1)
        }
        .tabViewStyle(.verticalPage)
        .navigationBarBackButtonHidden(true)
    }

    private var metricsPage: some View {
        VStack(spacing: 8) {
            HStack {
                Text(PulsarRunFormatters.compactDistance(runManager.snapshot.distanceMeters))
                    .font(.system(size: 34, weight: .black, design: .rounded).monospacedDigit())
                Text("km")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                WatchRunMetric(title: "Time", value: PulsarRunFormatters.duration(runManager.snapshot.elapsedTime))
                WatchRunMetric(title: "Pace", value: PulsarRunFormatters.pace(runManager.snapshot.currentPaceSecondsPerKilometer).replacingOccurrences(of: " /km", with: ""))
                WatchRunMetric(title: "HR", value: PulsarRunFormatters.heartRate(runManager.snapshot.currentHeartRate), unit: "bpm", tint: .red)
                WatchRunMetric(title: "Gain", value: PulsarRunFormatters.elevation(runManager.snapshot.elevationGainMeters), tint: .green)
            }

            Text(runManager.snapshot.phase == .paused ? "Paused" : "Recording")
                .font(.caption2.weight(.black))
                .foregroundStyle(runManager.snapshot.phase == .paused ? .orange : .green)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background((runManager.snapshot.phase == .paused ? Color.orange : Color.green).opacity(0.14), in: Capsule())
        }
        .padding(.horizontal, 8)
    }

    private var controlsPage: some View {
        VStack(spacing: 8) {
            Button(runManager.snapshot.phase == .paused ? "Resume" : "Pause") {
                runManager.snapshot.phase == .paused ? runManager.resume() : runManager.pause()
            }
            .buttonStyle(.borderedProminent)
            .tint(runManager.snapshot.phase == .paused ? .green : .orange)

            Button("Finish", role: .destructive) {
                runManager.finish()
            }
            .buttonStyle(.borderedProminent)

            if runManager.snapshot.phase == .finishing {
                ProgressView("Saving")
                    .font(.caption2)
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
                .font(.system(size: 8, weight: .black, design: .rounded))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .black, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                if let unit {
                    Text(unit)
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
