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
    @State private var reflectionText = ""

    var onComplete: (PulsarMindfulnessSessionSummary) -> Void

    init(
        template: PulsarMeditationTemplate,
        onComplete: @escaping (PulsarMindfulnessSessionSummary) -> Void
    ) {
        _engine = StateObject(wrappedValue: PulsarMeditationSessionEngine(template: template))
        self.onComplete = onComplete
    }

    var body: some View {
        ZStack {
            MindfulnessSessionBackground(tint: engine.template.category.accent)
                .ignoresSafeArea()

            TimelineView(.animation) { context in
                let elapsed = engine.currentElapsed(at: context.date)
                let snapshot = engine.breathingSnapshot(at: context.date)

                VStack(spacing: 22) {
                    sessionHeader

                    Spacer(minLength: 16)

                    PulsarBreathLensView(
                        snapshot: snapshot,
                        progress: engine.template.duration > 0 ? elapsed / engine.template.duration : 0,
                        tint: engine.template.category.accent
                    )
                    .frame(width: 270, height: 270)
                    .padding(.vertical, 8)

                    VStack(spacing: 8) {
                        Text(phaseTitle(for: snapshot))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.opacity)

                        Text(remainingText(elapsed: elapsed))
                            .pulsarTextStyle(.metricMedium)
                                .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.68))
                    }

                    Spacer(minLength: 16)

                    sessionControls
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 20)
            }

            if let summary = engine.summary {
                MindfulnessSessionSummaryOverlay(
                    summary: summary,
                    reflectionText: $reflectionText,
                    onDone: {
                        var completed = summary
                        completed.reflection = trimmedReflection
                        onComplete(completed)
                        dismiss()
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .interactiveDismissDisabled(engine.phase == .running || engine.phase == .paused)
        .onAppear {
            engine.start()
        }
        .animation(.smooth(duration: 0.38), value: engine.phase)
        .animation(.smooth(duration: 0.38), value: engine.summary)
    }

    private var sessionHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                engine.cancel()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.11), in: Circle())
            }
            .accessibilityLabel("Close session")

            VStack(alignment: .leading, spacing: 5) {
                Text(engine.template.category.title)
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(.white.opacity(0.54))
                Text(engine.template.title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 0)

            Text(engine.template.durationText)
                .pulsarTextStyle(.label)
                                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.78))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.white.opacity(0.10), in: Capsule(style: .continuous))
        }
    }

    private var sessionControls: some View {
        VStack(spacing: 12) {
            if engine.phase == .paused {
                Button {
                    engine.resume()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                        .pulsarTextStyle(.cardTitle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(PulsarMindfulnessActionButtonStyle(tint: engine.template.category.accent))
            } else {
                Button {
                    if engine.phase == .running {
                        engine.pause()
                    }
                } label: {
                    Label(engine.phase == .preparing ? "Settling" : "Pause", systemImage: engine.phase == .preparing ? "sparkles" : "pause.fill")
                        .pulsarTextStyle(.cardTitle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(PulsarMindfulnessActionButtonStyle(tint: engine.template.category.accent))
                .disabled(engine.phase == .preparing)
                .opacity(engine.phase == .preparing ? 0.64 : 1)
            }

            Button {
                engine.finish()
            } label: {
                Text("End")
                    .pulsarTextStyle(.label)
                    .foregroundStyle(.white.opacity(0.76))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.white.opacity(0.10), in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(engine.phase == .completed || engine.phase == .cancelled)
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
}

private struct MindfulnessSessionBackground: View {
    var tint: Color

    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.018, green: 0.020, blue: 0.032),
                tint.opacity(0.30),
                Color(red: 0.030, green: 0.026, blue: 0.045)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            RadialGradient(
                colors: [tint.opacity(0.28), .clear],
                center: .center,
                startRadius: 40,
                endRadius: 420
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
        let breathing = breathingScale
        ZStack {
            ForEach(0..<12, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(petalGradient(index: index))
                    .frame(width: 52, height: 138)
                    .offset(y: reduceMotion ? -24 : -38 * breathing)
                    .rotationEffect(.degrees(Double(index) * 30 + rotationOffset))
                    .scaleEffect(x: 0.56 + breathing * 0.22, y: 0.86 + breathing * 0.32)
                    .opacity(0.18 + breathing * 0.18)
                    .blendMode(.screen)
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.72),
                            tint.opacity(0.36),
                            .white.opacity(0.05)
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: 118
                    )
                )
                .scaleEffect(reduceMotion ? 0.86 : 0.74 + breathing * 0.28)
                .blur(radius: 0.4)

            Circle()
                .stroke(.white.opacity(0.34), lineWidth: 1)
                .scaleEffect(0.76 + breathing * 0.25)

            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    tint.opacity(0.74),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(18)
        }
        .drawingGroup()
        .accessibilityHidden(true)
    }

    private var breathingScale: CGFloat {
        guard !reduceMotion else { return 0.5 }
        guard let snapshot else { return 0.42 }

        let progress = CGFloat(snapshot.phaseProgress)
        switch snapshot.phase.kind {
        case .inhale, .inhaleTopUp:
            return 0.34 + easeOut(progress) * 0.66
        case .holdFull:
            return 0.92 + sin(progress * .pi * 2) * 0.035
        case .exhale:
            return 1.0 - easeInOut(progress) * 0.64
        case .holdEmpty:
            return 0.34 + sin(progress * .pi * 2) * 0.025
        }
    }

    private var rotationOffset: Double {
        guard let snapshot, !reduceMotion else { return 0 }
        return snapshot.cycleProgress * 10
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

    private func petalGradient(index: Int) -> LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(index.isMultiple(of: 2) ? 0.24 : 0.14),
                tint.opacity(index.isMultiple(of: 3) ? 0.42 : 0.28),
                .clear
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct MindfulnessSessionSummaryOverlay: View {
    var summary: PulsarMindfulnessSessionSummary
    @Binding var reflectionText: String
    var onDone: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.38)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    Image(systemName: "checkmark.seal.fill")
                        .pulsarTextStyle(.title)
                        .foregroundStyle(summary.category.accent)
                        .frame(width: 46, height: 46)
                        .background(summary.category.accent.opacity(0.16), in: Circle())

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Session complete")
                            .pulsarTextStyle(.title)
                        Text(summary.title)
                            .pulsarTextStyle(.label)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                HStack(spacing: 10) {
                    MindfulnessMetricPill(title: "Duration", value: summary.durationText, symbolName: "timer", tint: summary.category.accent)
                    MindfulnessMetricPill(title: "Cycles", value: "\(summary.completedCycles)", symbolName: "repeat", tint: .blue)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Reflection")
                        .pulsarTextStyle(.cardTitle)
                    TextEditor(text: $reflectionText)
                        .frame(minHeight: 84)
                        .scrollContentBackground(.hidden)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                Button(action: onDone) {
                    Text("Done")
                        .pulsarTextStyle(.cardTitle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(PulsarMindfulnessActionButtonStyle(tint: summary.category.accent))
            }
            .padding(20)
            .frame(maxWidth: 420)
            .pulsarLiquidGlass(cornerRadius: 30)
            .padding(22)
        }
    }
}

#Preview {
    MindfulnessSessionView(template: PulsarMindfulnessContentLibrary.meditationTemplates[0]) { _ in }
}
