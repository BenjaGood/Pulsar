//
//  PulsarRunSetupView.swift
//  Pulsar
//

import SwiftUI
import UIKit

struct PulsarRunSetupView: View {
    @ObservedObject var coordinator: PulsarRunCoordinator
    var workoutKind: PulsarOutdoorWorkoutKind = .running
    var onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var options = PulsarRunOptions.default
    @State private var countdown: Int?
    @State private var isShowingHistory = false
    @State private var watchFallbackPrompt: PulsarWatchRecorderFallbackPrompt?
    @State private var isStartingWorkout = false

    var body: some View {
        ZStack {
            PulsarRunSetupBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    sourceCard
                    routeCard
                    optionsCard
                    permissionCard
                    startButton
                    historyButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 34)
            }

            if let countdown {
                countdownOverlay(countdown)
                    .transition(.scale(scale: 0.72).combined(with: .opacity))
            }
        }
        .onAppear {
            coordinator.refreshAvailability()
            OutdoorWorkoutAudioCueSettings.applyPersistedPreference(to: &options)
            if coordinator.isWatchAvailable {
                options.prefersWatchRecorder = coordinator.preferredSource == .appleWatch
            }
        }
        .onChange(of: options.audioCuesEnabled) { _, newValue in
            OutdoorWorkoutAudioCueSettings.audioCuesEnabled = newValue
        }
        .sheet(isPresented: $isShowingHistory) {
            PulsarRunHistoryView(coordinator: coordinator, workoutKind: workoutKind)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert(item: $watchFallbackPrompt) { prompt in
            Alert(
                title: Text(prompt.title),
                message: Text(prompt.message),
                primaryButton: .default(Text("Try Again")) {
                    retryAppleWatchStart()
                },
                secondaryButton: .default(Text("Use iPhone")) {
                    startUsingIPhone()
                }
            )
        }
        .pulsarFitnessMonochromeAppearance()
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                Text(workoutKind.outdoorTitle)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(primaryText)
                Text("GPS route, live pace, splits, heart rate, and HealthKit workout saving.")
                    .pulsarTextStyle(.label)
                    .foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(secondaryText)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(colorScheme == .dark ? 0.16 : 0.72), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var sourceCard: some View {
        PulsarRunGlassCard {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(sourceTint.opacity(0.16))
                    Image(systemName: options.prefersWatchRecorder ? "applewatch.radiowaves.left.and.right" : "iphone.gen3.radiowaves.left.and.right")
                        .pulsarTextStyle(.sectionHeader)
                        .foregroundStyle(sourceTint)
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 4) {
                    Text(sourceTitle)
                        .pulsarTextStyle(.cardTitle)
                        .foregroundStyle(primaryText)
                    Text(sourceSubtitle)
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var routeCard: some View {
        PulsarRunGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Route", systemImage: "map.fill")
                        .pulsarTextStyle(.cardTitle)
                        .foregroundStyle(primaryText)
                    Spacer()
                    Text("Open")
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(PulsarFitnessMonochromeDesign.active)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(PulsarFitnessMonochromeDesign.active.opacity(0.12), in: Capsule())
                }

                Text("Free \(workoutKind.actionName) today. Route planning and saved routes are a good next layer once recording is battle-tested.")
                    .pulsarTextStyle(.label)
                    .foregroundStyle(secondaryText)
            }
        }
    }

    private var optionsCard: some View {
        PulsarRunGlassCard {
            VStack(spacing: 10) {
                Toggle(isOn: $options.autoPauseEnabled) {
                    Label("Auto-pause", systemImage: "pause.circle.fill")
                        .pulsarTextStyle(.cardTitle)
                }

                Toggle(isOn: $options.audioCuesEnabled) {
                    Label("Audio cues", systemImage: "speaker.wave.2.fill")
                        .pulsarTextStyle(.cardTitle)
                }

                Toggle(isOn: $options.prefersWatchRecorder) {
                    Label("Prefer Apple Watch", systemImage: "applewatch")
                        .pulsarTextStyle(.cardTitle)
                }
            }
            .tint(workoutKind.accentColor)
            .foregroundStyle(primaryText)
        }
    }

    @ViewBuilder
    private var permissionCard: some View {
        if let message = coordinator.authorizationMessage {
            PulsarRunGlassCard {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .pulsarTextStyle(.label)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            PulsarRunGlassCard {
                Label("HealthKit and Location are used only to record this \(workoutKind.actionName), route, and summary.", systemImage: "checkmark.shield.fill")
                    .pulsarTextStyle(.label)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.active)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var startButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task { await beginCountdownAndStart() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: workoutKind.systemImageName)
                    .pulsarTextStyle(.sectionHeader)
                Text(workoutKind.startTitle)
                    .pulsarTextStyle(.sectionHeader)
            }
            .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                LinearGradient(
                    colors: [workoutKind.accentColor.opacity(0.96), workoutKind.glowColor],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule(style: .continuous)
            )
            .overlay(Capsule().stroke(.white.opacity(0.56), lineWidth: 1))
            .shadow(color: workoutKind.accentColor.opacity(0.28), radius: 22, y: 12)
        }
        .buttonStyle(PulsarRunPressStyle())
        .disabled(isStartingWorkout || countdown != nil)
    }

    private var historyButton: some View {
        Button {
            isShowingHistory = true
        } label: {
            Label("Training Log", systemImage: "calendar.badge.clock")
                .pulsarTextStyle(.cardTitle)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(primaryText)
    }

    private func countdownOverlay(_ value: Int) -> some View {
        ZStack {
            Color.black.opacity(0.34)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Text("\(value)")
                    .font(.system(size: 104, weight: .semibold, design: .rounded))
                    .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                    .contentTransition(.numericText())
                Text("Ready")
                    .pulsarTextStyle(.sectionHeader)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
            }
        }
    }

    private func beginCountdownAndStart() async {
        guard !isStartingWorkout else { return }
        isStartingWorkout = true
        defer { isStartingWorkout = false }

        if options.prefersWatchRecorder {
            let availability = await coordinator.watchRecorderAvailability(for: workoutKind)
            guard availability.canAttemptWatchAppLaunch else {
                watchFallbackPrompt = availability.fallbackPrompt(workoutName: workoutKind.displayName)
                return
            }
        }

        await coordinator.requestPermissions(for: workoutKind)
        guard coordinator.authorizationMessage == nil else { return }

        for value in [3, 2, 1] {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
                countdown = value
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            try? await Task.sleep(nanoseconds: 850_000_000)
        }

        withAnimation(.easeOut(duration: 0.18)) {
            countdown = nil
        }
        let result = await coordinator.startOutdoorWorkout(workoutKind, options: options)
        if case .needsFallback(let prompt) = result {
            watchFallbackPrompt = prompt
        }
    }

    private func retryAppleWatchStart() {
        Task { @MainActor in
            options.prefersWatchRecorder = true
            await beginCountdownAndStart()
        }
    }

    private func startUsingIPhone() {
        Task { @MainActor in
            options.prefersWatchRecorder = false
            await coordinator.requestPermissions(for: workoutKind)
            guard coordinator.authorizationMessage == nil else { return }
            let result = await coordinator.startOutdoorWorkout(
                workoutKind,
                options: options,
                startMode: .iPhoneOnly
            )
            if case .needsFallback(let prompt) = result {
                watchFallbackPrompt = prompt
            }
        }
    }

    private var sourceTint: Color {
        if options.prefersWatchRecorder {
            return coordinator.isWatchAvailable ? workoutKind.accentColor : PulsarFitnessMonochromeDesign.primaryText
        }
        return PulsarFitnessMonochromeDesign.primaryText
    }

    private var sourceTitle: String {
        if options.prefersWatchRecorder {
            return coordinator.isWatchAvailable ? "Watch-first recording" : "Apple Watch not connected"
        }
        return "iPhone recording"
    }

    private var sourceSubtitle: String {
        if options.prefersWatchRecorder {
            return coordinator.isWatchAvailable
                ? "Pulsar will launch Apple Watch and mirror live stats back here."
                : "Open Pulsar on Apple Watch to connect, or use iPhone."
        }
        return "Pulsar will record GPS from iPhone."
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.97) : Color(red: 0.08, green: 0.10, blue: 0.15)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.64) : Color(red: 0.35, green: 0.39, blue: 0.47)
    }
}

struct PulsarRunGlassCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pulsarFitnessMonochromeSurface(cornerRadius: 26, shadowOpacity: 0.055)
    }
}

private struct PulsarRunSetupBackground: View {
    var body: some View {
        PulsarFitnessMonochromeBackground()
    }
}

struct PulsarRunPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .brightness(configuration.isPressed ? 0.04 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.74), value: configuration.isPressed)
    }
}

extension PulsarOutdoorWorkoutKind {
    var accentColor: Color {
        PulsarFitnessMonochromeDesign.primaryText
    }

    var glowColor: Color {
        PulsarFitnessMonochromeDesign.secondaryText
    }
}
