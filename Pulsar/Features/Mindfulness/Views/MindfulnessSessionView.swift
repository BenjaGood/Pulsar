//
//  MindfulnessSessionView.swift
//  Pulsar
//

import SwiftUI
import UIKit

struct MindfulnessSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var engine: PulsarMeditationSessionEngine
    @StateObject private var audioManager = SoundMeditationAudioManager()
    @State private var selectedSoundscape = SoundscapeCatalog.defaultSoundscape
    @State private var reflectionText = ""

    var onComplete: (PulsarMindfulnessSessionSummary) -> Void

    init(
        template: PulsarMeditationTemplate,
        onComplete: @escaping (PulsarMindfulnessSessionSummary) -> Void
    ) {
        let hapticsLevel: PulsarBreathingHapticsLevel = template.id == "sound-meditation" ? .none : .minimal
        _engine = StateObject(wrappedValue: PulsarMeditationSessionEngine(template: template, hapticsLevel: hapticsLevel))
        self.onComplete = onComplete
    }

    var body: some View {
        ZStack {
            MindfulnessSessionBackground(tint: engine.template.category.accent)
                .ignoresSafeArea()

            GeometryReader { proxy in
                let lensMaximum: CGFloat = isSoundMeditation ? 258 : 326
                let lensMinimum: CGFloat = isSoundMeditation ? 206 : 230
                let lensSize = min(lensMaximum, max(lensMinimum, proxy.size.width - 90))

                VStack(spacing: isSoundMeditation ? 14 : 20) {
                    sessionHeader

                    if isSoundMeditation {
                        SoundMeditationSoundscapeCard(
                            soundscapes: SoundscapeCatalog.all,
                            selectedSoundscape: selectedSoundscape,
                            initialVolume: audioManager.volume,
                            playbackState: audioManager.playbackState,
                            playbackError: audioManager.playbackError,
                            onSelect: selectSoundscape,
                            onPrevious: selectPreviousSoundscape,
                            onNext: selectNextSoundscape,
                            onTogglePlayback: toggleSoundMeditationPlayback,
                            onVolumeChange: audioManager.setVolume
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }

                    if !isSoundMeditation {
                        Spacer(minLength: 10)
                    }

                    sessionVisualBlock(lensSize: lensSize)
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: .infinity, alignment: .center)

                    if !isSoundMeditation {
                        Spacer(minLength: 18)

                        sessionControls
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, isSoundMeditation ? 18 : 24)
                .padding(.bottom, isSoundMeditation ? 18 : 22)
            }

            if let summary = engine.summary {
                MindfulnessSessionSummaryOverlay(
                    summary: summary,
                    reflectionText: $reflectionText,
                    onDone: {
                        var completed = summary
                        completed.reflection = trimmedReflection
                        completed.soundscapeTitle = isSoundMeditation ? selectedSoundscape.title : nil
                        onComplete(completed)
                        dismiss()
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .interactiveDismissDisabled(engine.phase == .running || engine.phase == .paused || engine.summary != nil)
        .onAppear {
            if isSoundMeditation {
                audioManager.prepare(soundscape: selectedSoundscape)
            }
            engine.start()
        }
        .onChange(of: engine.phase) { _, phase in
            handleSessionPhaseChange(phase)
        }
        .onDisappear {
            audioManager.fadeOut(duration: 0.35)
            audioManager.stop()
        }
        .animation(.smooth(duration: 0.38), value: engine.phase)
        .animation(.smooth(duration: 0.38), value: engine.summary)
    }

    private var sessionHeader: some View {
        PulsarGlassEffectGroup(spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    engine.cancel()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 19, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.88))
                        .frame(width: 48, height: 48)
                        .background {
                            Circle()
                                .fill(Color.black.opacity(0.26))
                                .overlay {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [.white.opacity(0.11), .clear],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                }
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(.white.opacity(0.16), lineWidth: 0.9)
                        }
                        .pulsarLiquidGlass(
                            cornerRadius: 24,
                            tint: engine.template.category.accent.opacity(0.10),
                            interactive: true,
                            isClear: true
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close session")

                VStack(alignment: .leading, spacing: 5) {
                    Text(engine.template.category.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(engine.template.category.accent.opacity(0.74))
                    Text(engine.template.title)
                        .font(.system(size: isSoundMeditation ? 27 : 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.50)
                        .allowsTightening(true)
                }
                .padding(.top, 5)
                .layoutPriority(2)

                Spacer(minLength: 0)

                Text(engine.template.durationText)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background {
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.22))
                            .overlay {
                                Capsule(style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [.white.opacity(0.12), .clear],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(.white.opacity(0.15), lineWidth: 0.9)
                    }
                    .pulsarLiquidGlass(
                        cornerRadius: 28,
                        tint: engine.template.category.accent.opacity(0.10),
                        isClear: true
                    )
                    .frame(minWidth: 78)
                    .padding(.top, 5)
                    .layoutPriority(1)
            }
        }
    }

    private var sessionControls: some View {
        VStack(spacing: 12) {
            if engine.phase == .paused {
                Button {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    engine.resume()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MindfulnessSessionPrimaryGlassButtonStyle(tint: engine.template.category.accent))
            } else {
                Button {
                    if engine.phase == .running {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        engine.pause()
                    }
                } label: {
                    Label(engine.phase == .preparing ? "Settling" : "Pause", systemImage: engine.phase == .preparing ? "sparkles" : "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MindfulnessSessionPrimaryGlassButtonStyle(tint: engine.template.category.accent))
                .disabled(engine.phase == .preparing)
                .opacity(engine.phase == .preparing ? 0.64 : 1)
            }

            Button {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                engine.finish()
            } label: {
                Text("End")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(MindfulnessSessionSecondaryGlassButtonStyle())
            .disabled(engine.phase == .completed || engine.phase == .cancelled)
        }
    }

    private func sessionVisualBlock(lensSize: CGFloat) -> some View {
        TimelineView(
            .animation(
                minimumInterval: isSoundMeditation ? 1.0 / 15.0 : nil,
                paused: engine.phase == .paused || engine.phase == .completed || engine.phase == .cancelled
            )
        ) { context in
            let elapsed = engine.currentElapsed(at: context.date)
            let snapshot = engine.breathingSnapshot(at: context.date)

            VStack(spacing: isSoundMeditation ? 16 : 22) {
                PulsarBreathLensView(
                    snapshot: snapshot,
                    progress: engine.template.duration > 0 ? elapsed / engine.template.duration : 0,
                    tint: engine.template.category.accent
                )
                .frame(width: lensSize, height: lensSize)

                VStack(spacing: 8) {
                    Text(phaseTitle(for: snapshot))
                        .font(.system(size: isSoundMeditation ? 40 : 38, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.opacity)

                    Text(remainingText(elapsed: elapsed))
                        .font(.system(size: isSoundMeditation ? 29 : 27, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.52))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, isSoundMeditation ? 4 : 0)
        }
    }

    private var trimmedReflection: String? {
        let trimmed = reflectionText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func phaseTitle(for snapshot: PulsarBreathingPhaseSnapshot?) -> String {
        guard engine.phase != .preparing else { return "Settle" }
        guard engine.phase != .paused else { return "Paused" }
        return snapshot?.phase.cue ?? "Be here"
    }

    private func remainingText(elapsed: TimeInterval) -> String {
        max(0, engine.template.duration - elapsed).pulsarMindfulnessDurationText
    }

    private var isSoundMeditation: Bool {
        engine.template.id == "sound-meditation"
    }

    private func selectSoundscape(_ soundscape: Soundscape) {
        guard !soundscape.isComingSoon else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        selectedSoundscape = soundscape

        switch engine.phase {
        case .running:
            if audioManager.isPlaying {
                audioManager.switchSoundscape(to: soundscape, crossfadeDuration: 0.8)
            } else {
                audioManager.load(soundscape: soundscape)
                if audioManager.playbackError == nil {
                    audioManager.fadeIn(duration: 0.45)
                }
            }
        case .paused, .preparing:
            audioManager.prepare(soundscape: soundscape)
        case .completed, .cancelled:
            break
        }
    }

    private func selectPreviousSoundscape() {
        selectAdjacentSoundscape(offset: -1)
    }

    private func selectNextSoundscape() {
        selectAdjacentSoundscape(offset: 1)
    }

    private func selectAdjacentSoundscape(offset: Int) {
        let availableSoundscapes = SoundscapeCatalog.all.filter { !$0.isComingSoon }
        guard !availableSoundscapes.isEmpty else { return }

        guard let currentIndex = availableSoundscapes.firstIndex(where: { $0.id == selectedSoundscape.id }) else {
            selectSoundscape(availableSoundscapes[0])
            return
        }

        let nextIndex = (currentIndex + offset + availableSoundscapes.count) % availableSoundscapes.count
        selectSoundscape(availableSoundscapes[nextIndex])
    }

    private func toggleSoundMeditationPlayback() {
        guard audioManager.playbackError == nil else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()

        switch engine.phase {
        case .running:
            engine.pause()
        case .paused:
            engine.resume()
        case .preparing:
            audioManager.fadeIn(duration: 0.55)
        case .completed, .cancelled:
            break
        }
    }

    private func handleSessionPhaseChange(_ phase: PulsarMindfulnessSessionPhase) {
        guard isSoundMeditation else { return }

        switch phase {
        case .running:
            if audioManager.currentSoundscape?.id != selectedSoundscape.id {
                audioManager.load(soundscape: selectedSoundscape)
            }

            if audioManager.playbackError == nil {
                audioManager.fadeIn(duration: 0.45)
            }
        case .paused:
            audioManager.pause()
        case .completed, .cancelled:
            audioManager.fadeOut(duration: 0.8)
        case .preparing:
            audioManager.prepare(soundscape: selectedSoundscape)
        }
    }
}

private struct MindfulnessSessionBackground: View {
    var tint: Color

    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.006, green: 0.010, blue: 0.024),
                Color(red: 0.020, green: 0.070, blue: 0.130),
                Color(red: 0.010, green: 0.018, blue: 0.036)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            RadialGradient(
                colors: [
                    tint.opacity(0.34),
                    tint.opacity(0.16),
                    .clear
                ],
                center: UnitPoint(x: 0.50, y: 0.38),
                startRadius: 10,
                endRadius: 430
            )
        }
        .overlay {
            RadialGradient(
                colors: [
                    .white.opacity(0.10),
                    .clear
                ],
                center: UnitPoint(x: 0.18, y: 0.18),
                startRadius: 0,
                endRadius: 300
            )
        }
        .overlay {
            LinearGradient(
                colors: [
                    .black.opacity(0.08),
                    .clear,
                    .black.opacity(0.38)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct PulsarBreathLensView: View {
    var snapshot: PulsarBreathingPhaseSnapshot?
    var progress: Double
    var tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let safeProgress = min(max(progress, 0), 1)
            let breathing = breathingScale
            let ringInset = size * 0.075
            let ringRadius = size / 2 - ringInset
            let dotPosition = progressDotPosition(
                progress: safeProgress,
                radius: ringRadius,
                center: CGPoint(x: size / 2, y: size / 2)
            )

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                tint.opacity(0.26),
                                tint.opacity(0.09),
                                .clear
                            ],
                            center: .center,
                            startRadius: size * 0.16,
                            endRadius: size * 0.56
                        )
                    )
                    .blur(radius: size * 0.045)

                Circle()
                    .stroke(.white.opacity(0.20), lineWidth: 1.6)
                    .padding(ringInset)
                    .overlay {
                        Circle()
                            .stroke(tint.opacity(0.10), lineWidth: 12)
                            .blur(radius: 13)
                            .padding(ringInset)
                    }

                Circle()
                    .trim(from: 0, to: safeProgress)
                    .stroke(
                        tint.opacity(0.46),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .blur(radius: 8)
                    .padding(ringInset)
                    .opacity(safeProgress > 0 ? 1 : 0)

                Circle()
                    .trim(from: 0, to: safeProgress)
                    .stroke(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.62),
                                Color(red: 0.70, green: 0.88, blue: 1.00),
                                .white.opacity(0.80)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(ringInset)
                    .shadow(color: tint.opacity(0.55), radius: 10)

                if safeProgress > 0.004 {
                    Circle()
                        .fill(.white)
                        .frame(width: size * 0.052, height: size * 0.052)
                        .overlay {
                            Circle()
                                .fill(tint.opacity(0.60))
                                .blur(radius: 8)
                        }
                        .shadow(color: tint.opacity(0.92), radius: 12)
                        .shadow(color: .white.opacity(0.52), radius: 3)
                        .position(dotPosition)
                }

                LiquidBreathOrbView(
                    breathing: breathing,
                    morph: morphAmount,
                    tint: tint
                )
                .frame(width: size * 0.58, height: size * 0.58)
                .scaleEffect(reduceMotion ? 0.96 : 0.88 + breathing * 0.16)
            }
            .frame(width: size, height: size)
            .compositingGroup()
        }
        .accessibilityHidden(true)
    }

    private var breathingScale: CGFloat {
        guard !reduceMotion else { return 0.55 }
        guard let snapshot else { return 0.38 }

        let progress = CGFloat(snapshot.phaseProgress)
        switch snapshot.phase.kind {
        case .inhale, .inhaleTopUp:
            return 0.40 + easeOut(progress) * 0.60
        case .holdFull:
            return 0.92 + sin(progress * .pi * 2) * 0.035
        case .exhale:
            return 1.0 - easeInOut(progress) * 0.64
        case .holdEmpty:
            return 0.34 + sin(progress * .pi * 2) * 0.025
        }
    }

    private var morphAmount: CGFloat {
        guard let snapshot, !reduceMotion else { return 0.42 }
        return 0.5 + sin(CGFloat(snapshot.cycleProgress) * .pi * 2) * 0.5
    }

    private func easeOut(_ value: CGFloat) -> CGFloat {
        1 - pow(1 - min(max(value, 0), 1), 3)
    }

    private func easeInOut(_ value: CGFloat) -> CGFloat {
        let clamped = min(max(value, 0), 1)
        return clamped < 0.5
            ? 4 * clamped * clamped * clamped
            : 1 - pow(-2 * clamped + 2, 3) / 2
    }

    private func progressDotPosition(progress: Double, radius: CGFloat, center: CGPoint) -> CGPoint {
        let angle = CGFloat(progress * 2 * .pi) - (.pi / 2)
        return CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }
}

private struct LiquidBreathOrbView: View {
    var breathing: CGFloat
    var morph: CGFloat
    var tint: Color

    var body: some View {
        let shape = LiquidBreathOrbShape(morph: morph)

        shape
            .fill(
                LinearGradient(
                    colors: [
                        .white.opacity(0.42),
                        tint.opacity(0.52),
                        Color(red: 0.04, green: 0.14, blue: 0.32).opacity(0.84)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                shape
                    .fill(
                        RadialGradient(
                            colors: [
                                .white.opacity(0.74),
                                tint.opacity(0.22),
                                .clear
                            ],
                            center: UnitPoint(x: 0.30 + morph * 0.12, y: 0.20),
                            startRadius: 0,
                            endRadius: 145
                        )
                    )
                    .blendMode(.screen)
                    .opacity(0.82)
            }
            .overlay {
                shape
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.72),
                                tint.opacity(0.26),
                                .white.opacity(0.16)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            }
            .overlay(alignment: .bottomTrailing) {
                shape
                    .fill(
                        RadialGradient(
                            colors: [
                                tint.opacity(0.42),
                                .clear
                            ],
                            center: UnitPoint(x: 0.80, y: 0.86),
                            startRadius: 0,
                            endRadius: 115
                        )
                    )
                    .blur(radius: 8)
                    .opacity(0.70 + Double(breathing) * 0.18)
            }
            .shadow(color: tint.opacity(0.38), radius: 22, y: 8)
            .shadow(color: .white.opacity(0.18), radius: 3, x: -2, y: -3)
            .rotationEffect(.degrees(Double((morph - 0.5) * 4)))
    }
}

private struct LiquidBreathOrbShape: Shape {
    var morph: CGFloat

    func path(in rect: CGRect) -> Path {
        let m = min(max(morph, 0), 1)
        let width = rect.width
        let height = rect.height

        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * width, y: rect.minY + y * height)
        }

        var path = Path()
        path.move(to: p(0.50, 0.05 + m * 0.03))
        path.addCurve(
            to: p(0.92 - m * 0.05, 0.36 + m * 0.04),
            control1: p(0.73 + m * 0.05, 0.02),
            control2: p(0.94, 0.15 + m * 0.08)
        )
        path.addCurve(
            to: p(0.75 - m * 0.06, 0.84),
            control1: p(0.96 - m * 0.06, 0.58),
            control2: p(0.85 + m * 0.03, 0.72)
        )
        path.addCurve(
            to: p(0.31 + m * 0.04, 0.88 - m * 0.02),
            control1: p(0.62 - m * 0.06, 0.99),
            control2: p(0.42, 0.92)
        )
        path.addCurve(
            to: p(0.09 + m * 0.03, 0.49 - m * 0.04),
            control1: p(0.13, 0.83 - m * 0.06),
            control2: p(0.02 + m * 0.04, 0.68)
        )
        path.addCurve(
            to: p(0.50, 0.05 + m * 0.03),
            control1: p(0.14 - m * 0.03, 0.24 - m * 0.03),
            control2: p(0.28 + m * 0.05, 0.08)
        )
        path.closeSubpath()
        return path
    }
}

private struct MindfulnessSessionPrimaryGlassButtonStyle: ButtonStyle {
    var tint: Color

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 19, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .labelStyle(.titleAndIcon)
            .padding(.vertical, 19)
            .padding(.horizontal, 22)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(reduceTransparency ? 0.92 : 0.42),
                                Color(red: 0.11, green: 0.28, blue: 0.62).opacity(reduceTransparency ? 0.84 : 0.30),
                                Color.black.opacity(reduceTransparency ? 0.34 : 0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(configuration.isPressed ? 0.18 : 0.28),
                                        .clear,
                                        tint.opacity(0.18)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(configuration.isPressed ? 0.38 : 0.58),
                                tint.opacity(0.62),
                                .white.opacity(0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.1
                    )
            }
            .shadow(color: tint.opacity(configuration.isPressed ? 0.28 : 0.44), radius: 18, y: 8)
            .shadow(color: .white.opacity(configuration.isPressed ? 0.08 : 0.16), radius: 3, x: -1, y: -2)
            .pulsarLiquidGlass(
                cornerRadius: 31,
                tint: tint.opacity(0.24),
                interactive: true,
                isClear: true
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.34, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

private struct MindfulnessSessionSecondaryGlassButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.82))
            .padding(.vertical, 18)
            .padding(.horizontal, 22)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(reduceTransparency ? 0.12 : 0.055),
                                Color.black.opacity(reduceTransparency ? 0.58 : 0.30)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(configuration.isPressed ? 0.22 : 0.13), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.20), radius: 14, y: 8)
            .pulsarLiquidGlass(cornerRadius: 30, tint: .white.opacity(0.035), interactive: true, isClear: true)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.34, dampingFraction: 0.84), value: configuration.isPressed)
    }
}

private struct SoundMeditationSoundscapeCard: View {
    var soundscapes: [Soundscape]
    var selectedSoundscape: Soundscape
    var initialVolume: Double
    var playbackState: SoundPlaybackState
    var playbackError: SoundPlaybackError?
    var onSelect: (Soundscape) -> Void
    var onPrevious: () -> Void
    var onNext: () -> Void
    var onTogglePlayback: () -> Void
    var onVolumeChange: (Double) -> Void

    @State private var volume = 0.82
    private let soundscapeColumns = Array(repeating: GridItem(.flexible(minimum: 68), spacing: 6), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: selectedSoundscape.category.symbolName)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(selectedSoundscape.category == .fire ? .orange : .cyan)
                    .frame(width: 34, height: 34)
                    .background {
                        Circle()
                            .fill(Color.white.opacity(0.075))
                            .overlay {
                                Circle()
                                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.8)
                            }
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedSoundscape.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text("\(selectedSoundscape.category.title) • \(selectedSoundscape.durationText)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                }

                Spacer(minLength: 0)

                Text(selectedSoundscape.isComingSoon ? "Soon" : playbackState.statusTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(statusColor.opacity(0.12), in: Capsule(style: .continuous))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(statusColor.opacity(0.16), lineWidth: 0.8)
                    }
            }

            LazyVGrid(
                columns: soundscapeColumns,
                spacing: 6
            ) {
                ForEach(soundscapes) { soundscape in
                    SoundscapeOptionButton(
                        soundscape: soundscape,
                        isSelected: selectedSoundscape.id == soundscape.id,
                        action: { onSelect(soundscape) }
                    )
                }
            }

            VStack(spacing: 6) {
                HStack {
                    Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                        .frame(width: 18)

                    Text("\(Int((volume * 100).rounded()))%")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.56))
                        .frame(width: 38, alignment: .trailing)

                    Slider(value: $volume, in: 0...1)
                        .tint(.cyan)
                }

                HStack(spacing: 18) {
                    Button(action: onPrevious) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(SoundMeditationMiniControlButtonStyle(tint: .white.opacity(0.42), isProminent: false))

                    Button(action: onTogglePlayback) {
                        Image(systemName: playbackState == .playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(SoundMeditationMiniControlButtonStyle(tint: .cyan, isProminent: true))
                    .disabled(playbackError != nil || selectedSoundscape.isComingSoon)
                    .opacity(playbackError == nil && !selectedSoundscape.isComingSoon ? 1 : 0.42)

                    Button(action: onNext) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(SoundMeditationMiniControlButtonStyle(tint: .white.opacity(0.42), isProminent: false))
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 2)

            if let playbackError {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.yellow.opacity(0.86))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(playbackError.userFacingTitle)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.78))
                        Text(playbackError.userFacingMessage)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.54))
                            .lineLimit(1)
                        #if DEBUG
                        Text("Fix asset metadata")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.38))
                        #endif
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(9)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.18),
                            Color(red: 0.05, green: 0.10, blue: 0.21).opacity(0.30)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.10), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 0.9)
        }
        .pulsarLiquidGlass(cornerRadius: 24, tint: .cyan.opacity(0.048), isClear: true)
        .accessibilityElement(children: .contain)
        .onAppear {
            volume = min(max(initialVolume, 0), 1)
        }
        .onChange(of: volume) { _, newVolume in
            onVolumeChange(newVolume)
        }
    }

    private var statusColor: Color {
        if selectedSoundscape.isComingSoon { return .white.opacity(0.48) }
        if playbackError != nil { return .yellow.opacity(0.86) }
        return playbackState == .playing ? .cyan : .white.opacity(0.62)
    }
}

private struct SoundscapeOptionButton: View {
    var soundscape: Soundscape
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: soundscape.isComingSoon ? "lock.fill" : soundscape.category.symbolName)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(iconColor)
                    .frame(width: 21, height: 21)
                    .background(.white.opacity(isSelected ? 0.13 : 0.07), in: Circle())

                VStack(spacing: 1) {
                    Text(soundscape.title)
                        .font(.system(size: 8.7, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(soundscape.isComingSoon ? 0.42 : 0.90))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.66)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .center)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(isSelected ? 0.115 : soundscape.isComingSoon ? 0.035 : 0.055))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.cyan.opacity(0.58) : Color.white.opacity(soundscape.isComingSoon ? 0.045 : 0.08),
                        lineWidth: isSelected ? 1.1 : 0.8
                    )
            }
            .shadow(color: isSelected ? Color.cyan.opacity(0.16) : .clear, radius: 8, y: 2)
            .scaleEffect(isSelected ? 1.015 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(soundscape.isComingSoon)
        .opacity(soundscape.isComingSoon ? 0.72 : 1)
        .accessibilityLabel(soundscape.title)
        .accessibilityValue(soundscape.isComingSoon ? "Coming soon" : soundscape.category.title)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isSelected)
    }

    private var iconColor: Color {
        if soundscape.isComingSoon { return .white.opacity(0.38) }
        return isSelected ? .cyan : .white.opacity(0.70)
    }
}

private struct SoundMeditationMiniControlButtonStyle: ButtonStyle {
    var tint: Color
    var isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isProminent ? .white : .white.opacity(0.66))
            .background {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(isProminent ? 0.36 : 0.11),
                                Color.black.opacity(isProminent ? 0.20 : 0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                Circle()
                    .strokeBorder(
                        isProminent ? tint.opacity(0.42) : Color.white.opacity(0.10),
                        lineWidth: isProminent ? 1.1 : 0.8
                    )
            }
            .shadow(color: isProminent ? tint.opacity(0.26) : .clear, radius: 12, y: 4)
            .pulsarLiquidGlass(
                cornerRadius: isProminent ? 24 : 17,
                tint: tint.opacity(isProminent ? 0.12 : 0.04),
                interactive: true,
                isClear: true
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.76), value: configuration.isPressed)
    }
}

private struct MindfulnessSessionSummaryOverlay: View {
    var summary: PulsarMindfulnessSessionSummary
    @Binding var reflectionText: String
    var onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var didAppear = false
    @State private var selectedMood: MindfulnessCompletionMood?

    var body: some View {
        ZStack {
            Color.black.opacity(0.48)
                .ignoresSafeArea()
                .overlay {
                    RadialGradient(
                        colors: [
                            summary.category.accent.opacity(0.30),
                            summary.category.accent.opacity(0.08),
                            .clear
                        ],
                        center: UnitPoint(x: 0.50, y: 0.40),
                        startRadius: 0,
                        endRadius: 430
                    )
                    .ignoresSafeArea()
                }

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    completionHeader

                    HStack(spacing: 14) {
                        MindfulnessCompletionStatCard(
                            title: "Duration",
                            value: summary.durationText,
                            symbolName: "timer",
                            tint: summary.category.accent
                        )
                        .offset(y: reduceMotion || didAppear ? 0 : 10)
                        .opacity(didAppear ? 1 : 0)
                        .animation(entranceAnimation.delay(0.08), value: didAppear)

                        MindfulnessCompletionStatCard(
                            title: "Cycles",
                            value: "\(summary.completedCycles)",
                            symbolName: "arrow.triangle.2.circlepath",
                            tint: summary.category.accent
                        )
                        .offset(y: reduceMotion || didAppear ? 0 : 10)
                        .opacity(didAppear ? 1 : 0)
                        .animation(entranceAnimation.delay(0.14), value: didAppear)
                    }

                    Text("Reflection")
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.top, 2)

                    MindfulnessCompletionReflectionCard(
                        selectedMood: selectedMood,
                        tint: summary.category.accent,
                        onSelect: selectMood
                    )
                    .scaleEffect(reduceMotion || didAppear ? 1 : 0.97)
                    .opacity(didAppear ? 1 : 0)
                    .animation(entranceAnimation.delay(0.20), value: didAppear)

                    Button(action: onDone) {
                        Text("Done")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MindfulnessSessionPrimaryGlassButtonStyle(tint: summary.category.accent))
                    .padding(.top, 2)
                }
                .padding(24)
                .frame(maxWidth: 420)
                .background {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.04, green: 0.12, blue: 0.22).opacity(0.72),
                                    Color.black.opacity(0.42)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 34, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(0.12),
                                            .clear,
                                            summary.category.accent.opacity(0.08)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.24),
                                    summary.category.accent.opacity(0.40),
                                    .white.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: summary.category.accent.opacity(0.20), radius: 28, y: 10)
                .shadow(color: .black.opacity(0.42), radius: 24, y: 16)
                .pulsarLiquidGlass(
                    cornerRadius: 34,
                    tint: summary.category.accent.opacity(0.08),
                    isClear: true
                )
                .padding(.horizontal, 22)
                .padding(.vertical, 26)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear {
            guard !didAppear else { return }
            withAnimation(entranceAnimation) {
                didAppear = true
            }
        }
    }

    private var completionHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            MindfulnessCompletionSuccessIcon(tint: summary.category.accent)
                .scaleEffect(reduceMotion || didAppear ? 1 : 0.76)
                .opacity(didAppear ? 1 : 0)
                .animation(entranceAnimation, value: didAppear)

            VStack(alignment: .leading, spacing: 5) {
                Text("Session complete")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(summary.title)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(summary.category.accent.opacity(0.78))

                if let soundscapeTitle = summary.soundscapeTitle {
                    Label(soundscapeTitle, systemImage: "speaker.wave.2.fill")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.56))
                        .labelStyle(.titleAndIcon)
                        .padding(.top, 2)
                }
            }
            .padding(.top, 5)

            Spacer(minLength: 8)

            ShareLink(item: shareText) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 19, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.86))
                    .frame(width: 50, height: 50)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.black.opacity(0.24))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [.white.opacity(0.13), .clear],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.14), lineWidth: 0.9)
                    }
                    .pulsarLiquidGlass(
                        cornerRadius: 16,
                        tint: summary.category.accent.opacity(0.08),
                        interactive: true,
                        isClear: true
                    )
            }
            .accessibilityLabel("Share session")
        }
    }

    private var shareText: String {
        let soundscape = summary.soundscapeTitle.map { " with \($0)" } ?? ""
        return "I completed \(summary.title)\(soundscape) in Pulsar: \(summary.durationText), \(summary.completedCycles) cycles."
    }

    private var entranceAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.46, dampingFraction: 0.84)
    }

    private func selectMood(_ mood: MindfulnessCompletionMood) {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.76)) {
            selectedMood = mood
            reflectionText = "Mood after session: \(mood.title)"
        }
    }
}

private struct MindfulnessCompletionSuccessIcon: View {
    var tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index == 0 ? Color.white.opacity(0.54) : tint.opacity(0.70))
                    .frame(width: index == 0 ? 3.5 : 2.5, height: index == 0 ? 3.5 : 2.5)
                    .blur(radius: 0.4)
                    .offset(
                        x: [32, -30, 24][index],
                        y: [-26, 24, 30][index]
                    )
                    .opacity(isBreathing && !reduceMotion ? 0.75 : 0.25)
            }

            Circle()
                .fill(tint.opacity(0.18))
                .blur(radius: 10)
                .scaleEffect(isBreathing && !reduceMotion ? 1.12 : 0.94)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.72),
                            tint.opacity(0.90),
                            Color(red: 0.12, green: 0.36, blue: 0.96).opacity(0.86)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.40), lineWidth: 1)
                }
                .shadow(color: tint.opacity(0.60), radius: 16, y: 7)

            Image(systemName: "checkmark")
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        }
        .frame(width: 66, height: 66)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }
}

private struct MindfulnessCompletionStatCard: View {
    var title: String
    var value: String
    var symbolName: String
    var tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .frame(width: 43, height: 43)
                .background {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    tint.opacity(0.30),
                                    Color(red: 0.08, green: 0.18, blue: 0.38).opacity(0.68)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.14), lineWidth: 0.8)
                }
                .shadow(color: tint.opacity(0.22), radius: 9, y: 4)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                Text(title)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, minHeight: 78)
        .background {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(0.16),
                            Color(red: 0.05, green: 0.14, blue: 0.26).opacity(0.54),
                            Color.black.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 23, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.13), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 0.9)
        }
        .shadow(color: tint.opacity(0.12), radius: 12, y: 6)
        .pulsarLiquidGlass(cornerRadius: 23, tint: tint.opacity(0.08), isClear: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

private struct MindfulnessCompletionReflectionCard: View {
    var selectedMood: MindfulnessCompletionMood?
    var tint: Color
    var onSelect: (MindfulnessCompletionMood) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 18) {
            TimelineView(.animation) { context in
                let phase = reduceMotion ? 0.42 : floatingPhase(at: context.date)
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    tint.opacity(0.30),
                                    tint.opacity(0.10),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 150
                            )
                        )
                        .blur(radius: 14)
                        .scaleEffect(1.05 + phase * 0.06)

                    LiquidBreathOrbView(
                        breathing: 0.58 + phase * 0.22,
                        morph: phase,
                        tint: tint
                    )
                    .frame(width: 142, height: 142)
                    .scaleEffect(0.96 + phase * 0.045)
                }
                .frame(height: 176)
            }
            .accessibilityHidden(true)

            VStack(spacing: 7) {
                Text("How do you feel?")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Take a moment to reflect on your mind and body.")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.66))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                ForEach(MindfulnessCompletionMood.allCases) { mood in
                    MindfulnessCompletionMoodButton(
                        mood: mood,
                        isSelected: selectedMood == mood,
                        action: { onSelect(mood) }
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(0.14),
                            Color(red: 0.03, green: 0.11, blue: 0.22).opacity(0.76),
                            Color.black.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [
                                    tint.opacity(0.20),
                                    .clear
                                ],
                                center: UnitPoint(x: 0.50, y: 0.22),
                                startRadius: 0,
                                endRadius: 260
                            )
                        )
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.9)
        }
        .shadow(color: tint.opacity(0.14), radius: 18, y: 8)
        .pulsarLiquidGlass(cornerRadius: 30, tint: tint.opacity(0.06), isClear: true)
    }

    private func floatingPhase(at date: Date) -> CGFloat {
        CGFloat((sin(date.timeIntervalSinceReferenceDate * 0.85) + 1) / 2)
    }
}

private enum MindfulnessCompletionMood: String, CaseIterable, Identifiable {
    case veryCalm
    case calm
    case neutral
    case anxious
    case stressed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .veryCalm: "Very calm"
        case .calm: "Calm"
        case .neutral: "Neutral"
        case .anxious: "Anxious"
        case .stressed: "Stressed"
        }
    }

    var colors: [Color] {
        switch self {
        case .veryCalm: [Color(red: 0.54, green: 0.38, blue: 1.00), Color(red: 0.18, green: 0.38, blue: 0.96)]
        case .calm: [Color(red: 0.44, green: 0.70, blue: 1.00), Color(red: 0.16, green: 0.30, blue: 0.96)]
        case .neutral: [Color(red: 0.40, green: 0.86, blue: 0.78), Color(red: 0.24, green: 0.58, blue: 0.58)]
        case .anxious: [Color(red: 1.00, green: 0.78, blue: 0.32), Color(red: 0.88, green: 0.48, blue: 0.14)]
        case .stressed: [Color(red: 1.00, green: 0.44, blue: 0.46), Color(red: 0.76, green: 0.16, blue: 0.24)]
        }
    }

    var mouthControlY: CGFloat {
        switch self {
        case .veryCalm: 0.78
        case .calm: 0.72
        case .neutral: 0.60
        case .anxious: 0.46
        case .stressed: 0.38
        }
    }

    var eyeOffset: CGFloat {
        self == .veryCalm ? 0.03 : 0
    }
}

private struct MindfulnessCompletionMoodButton: View {
    var mood: MindfulnessCompletionMood
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(isSelected ? 0.16 : 0.08),
                                    Color.black.opacity(isSelected ? 0.08 : 0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(isSelected ? Color.white.opacity(0.45) : Color.white.opacity(0.10), lineWidth: isSelected ? 1.2 : 0.8)
                        }
                        .shadow(color: mood.colors.last?.opacity(isSelected ? 0.38 : 0.08) ?? .clear, radius: isSelected ? 12 : 5)

                    MindfulnessCompletionMoodIcon(mood: mood)
                        .frame(width: 38, height: 38)
                }
                .frame(height: 62)
                .pulsarLiquidGlass(
                    cornerRadius: 18,
                    tint: (mood.colors.last ?? .blue).opacity(isSelected ? 0.18 : 0.05),
                    interactive: true,
                    isClear: true
                )

                Text(mood.title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(isSelected ? 0.92 : 0.68))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.75)
            }
            .scaleEffect(isSelected ? 1.045 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mood.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.spring(response: 0.34, dampingFraction: 0.76), value: isSelected)
    }
}

private struct MindfulnessCompletionMoodIcon: View {
    var mood: MindfulnessCompletionMood

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let lineWidth = max(1.5, size * 0.055)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: mood.colors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [.white.opacity(0.45), .clear],
                                    center: UnitPoint(x: 0.30, y: 0.20),
                                    startRadius: 0,
                                    endRadius: size * 0.70
                                )
                            )
                    }
                    .shadow(color: (mood.colors.last ?? .blue).opacity(0.36), radius: 8, y: 4)

                HStack(spacing: size * 0.18) {
                    if mood == .veryCalm {
                        closedEye(size: size)
                        closedEye(size: size)
                    } else {
                        Circle()
                            .fill(Color(red: 0.04, green: 0.08, blue: 0.18).opacity(0.72))
                            .frame(width: size * 0.085, height: size * 0.085)
                        Circle()
                            .fill(Color(red: 0.04, green: 0.08, blue: 0.18).opacity(0.72))
                            .frame(width: size * 0.085, height: size * 0.085)
                    }
                }
                .offset(y: -size * (0.11 - mood.eyeOffset))

                Path { path in
                    path.move(to: CGPoint(x: size * 0.30, y: size * 0.62))
                    path.addQuadCurve(
                        to: CGPoint(x: size * 0.70, y: size * 0.62),
                        control: CGPoint(x: size * 0.50, y: size * mood.mouthControlY)
                    )
                }
                .stroke(
                    Color(red: 0.04, green: 0.08, blue: 0.18).opacity(0.72),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            }
            .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }

    private func closedEye(size: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: size * 0.03))
            path.addQuadCurve(
                to: CGPoint(x: size * 0.13, y: size * 0.03),
                control: CGPoint(x: size * 0.065, y: size * 0.08)
            )
        }
        .stroke(
            Color(red: 0.04, green: 0.08, blue: 0.18).opacity(0.72),
            style: StrokeStyle(lineWidth: max(1.4, size * 0.045), lineCap: .round)
        )
        .frame(width: size * 0.13, height: size * 0.10)
    }
}

#Preview {
    MindfulnessSessionView(template: PulsarMindfulnessContentLibrary.meditationTemplates[0]) { _ in }
}

#Preview("Sound Meditation") {
    if let template = PulsarMindfulnessContentLibrary.template(id: "sound-meditation") {
        MindfulnessSessionView(template: template) { _ in }
    }
}
