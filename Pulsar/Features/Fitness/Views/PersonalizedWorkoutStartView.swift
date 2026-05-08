//
//  PersonalizedWorkoutStartView.swift
//  Pulsar
//

import SwiftUI
import UIKit

struct PersonalizedWorkoutStartView: View {
    enum CompletionBehavior {
        case showStartButton
        case continueAutomatically
    }

    let workout: PersonalizedWorkoutKind
    let completionBehavior: CompletionBehavior
    let onIntroCompleted: (() -> Void)?
    let onStart: (() -> Void)?
    let onCancel: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var hapticsManager = HeartbeatHapticsManager()
    @State private var hasStartedIntro = false
    @State private var backgroundOpacity = 0.0
    @State private var logoScale = 0.85
    @State private var drawProgress: CGFloat = 0
    @State private var spikeGlow = false
    @State private var titleOpacity = 0.0
    @State private var showsStartButton = false

    init(
        workout: PersonalizedWorkoutKind,
        completionBehavior: CompletionBehavior = .showStartButton,
        onIntroCompleted: (() -> Void)? = nil,
        onStart: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.workout = workout
        self.completionBehavior = completionBehavior
        self.onIntroCompleted = onIntroCompleted
        self.onStart = onStart
        self.onCancel = onCancel
    }

    var body: some View {
        ZStack {
            HeartbeatIntroBackground(opacity: backgroundOpacity)

            VStack(spacing: 28) {
                Spacer(minLength: 34)

                ECGHeartbeatView(drawProgress: drawProgress, spikeGlow: spikeGlow)
                    .scaleEffect(logoScale)
                    .opacity(backgroundOpacity)

                VStack(spacing: 7) {
                    Text(workout.title)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Personalized Training")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.70))
                }
                .opacity(titleOpacity)

                Spacer(minLength: 22)

                if showsStartButton {
                    startButton
                        .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.94)))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)

            cancelButton
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 20)
                .padding(.top, 18)
        }
        .task {
            await runIntroIfNeeded()
        }
    }

    private var cancelButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if let onCancel {
                onCancel()
            } else {
                dismiss()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                Text("Cancel")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(.white.opacity(0.78))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cancel workout")
    }

    private var startButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onStart?()
        } label: {
            HStack(spacing: 10) {
                Text("Start Workout")
                    .font(.headline.weight(.bold))
                Image(systemName: "arrow.right")
                    .font(.headline.weight(.bold))
            }
            .foregroundStyle(Color(red: 0.36, green: 0.02, blue: 0.04))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.98),
                        Color(red: 1.0, green: 0.82, blue: 0.78)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule(style: .continuous)
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.72), lineWidth: 1)
            }
            .shadow(color: Color(red: 1.0, green: 0.20, blue: 0.22).opacity(0.32), radius: 22, y: 10)
        }
        .buttonStyle(WorkoutStartButtonStyle())
        .accessibilityHint("Begins the selected personalized workout")
    }

    private func runIntroIfNeeded() async {
        guard !hasStartedIntro else { return }
        hasStartedIntro = true
        hapticsManager.prepare()

        withAnimation(.easeOut(duration: 0.42)) {
            backgroundOpacity = 1
            titleOpacity = 1
        }

        withAnimation(.spring(response: 0.72, dampingFraction: 0.74)) {
            logoScale = 1
        }

        try? await Task.sleep(nanoseconds: 220_000_000)

        withAnimation(.easeInOut(duration: 1.08)) {
            drawProgress = 1
        }

        try? await Task.sleep(nanoseconds: 540_000_000)

        hapticsManager.playHeartbeat()

        withAnimation(.spring(response: 0.20, dampingFraction: 0.52)) {
            spikeGlow = true
            logoScale = 1.035
        }

        try? await Task.sleep(nanoseconds: 210_000_000)

        withAnimation(.easeOut(duration: 0.32)) {
            spikeGlow = false
            logoScale = 1
        }

        switch completionBehavior {
        case .showStartButton:
            try? await Task.sleep(nanoseconds: 390_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.52, dampingFraction: 0.82)) {
                showsStartButton = true
            }
        case .continueAutomatically:
            try? await Task.sleep(nanoseconds: 520_000_000)
            guard !Task.isCancelled else { return }
            onIntroCompleted?()
        }
    }
}

private struct HeartbeatIntroBackground: View {
    var opacity: Double

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.42, green: 0.02, blue: 0.05),
                    Color(red: 0.18, green: 0.01, blue: 0.03),
                    Color(red: 0.04, green: 0.00, blue: 0.01)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(red: 1.0, green: 0.16, blue: 0.18).opacity(0.42),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 360
            )

            RadialGradient(
                colors: [
                    Color(red: 1.0, green: 0.40, blue: 0.28).opacity(0.24),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 8,
                endRadius: 330
            )

            VStack(spacing: 18) {
                ForEach(0..<9, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(.white.opacity(index.isMultiple(of: 2) ? 0.035 : 0.020))
                        .frame(height: 1)
                        .offset(x: index.isMultiple(of: 2) ? -34 : 42)
                }
            }
            .rotationEffect(.degrees(-9))
            .blendMode(.screen)
        }
        .opacity(opacity)
        .ignoresSafeArea()
        .background(Color(red: 0.04, green: 0.00, blue: 0.01).ignoresSafeArea())
    }
}

private struct WorkoutStartButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .brightness(configuration.isPressed ? 0.04 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.74), value: configuration.isPressed)
    }
}

#Preview {
    PersonalizedWorkoutStartView(workout: .running)
}
