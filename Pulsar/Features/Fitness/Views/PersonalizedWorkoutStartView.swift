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

    private let workoutTitle: String
    private let workoutSubtitle: String
    private let workoutTint: Color
    let completionBehavior: CompletionBehavior
    let onIntroCompleted: (() -> Void)?
    let onStart: (() -> Void)?
    let onCancel: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var hapticsManager = HeartbeatHapticsManager()
    @State private var hasStartedIntro = false
    @State private var backgroundOpacity = 1.0
    @State private var drawProgress: CGFloat = 0.62
    @State private var lineGlow = 0.0
    @State private var lineOpacity = 0.64
    @State private var titleOpacity = 0.92
    @State private var contentOffset: CGFloat = 8
    @State private var showsStartButton = false

    init(
        workout: PersonalizedWorkoutKind,
        completionBehavior: CompletionBehavior = .showStartButton,
        onIntroCompleted: (() -> Void)? = nil,
        onStart: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.init(
            title: workout.title,
            subtitle: "Personalized Training",
            tint: workout.accent.color,
            completionBehavior: completionBehavior,
            onIntroCompleted: onIntroCompleted,
            onStart: onStart,
            onCancel: onCancel
        )
    }

    init(
        workoutKind: PulsarOutdoorWorkoutKind,
        completionBehavior: CompletionBehavior = .showStartButton,
        onIntroCompleted: (() -> Void)? = nil,
        onStart: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.init(
            title: workoutKind.displayName,
            subtitle: "Personalized Training",
            tint: workoutKind.startAnimationTint,
            completionBehavior: completionBehavior,
            onIntroCompleted: onIntroCompleted,
            onStart: onStart,
            onCancel: onCancel
        )
    }

    private init(
        title: String,
        subtitle: String,
        tint: Color,
        completionBehavior: CompletionBehavior,
        onIntroCompleted: (() -> Void)?,
        onStart: (() -> Void)?,
        onCancel: (() -> Void)?
    ) {
        self.workoutTitle = title
        self.workoutSubtitle = subtitle
        self.workoutTint = tint
        self.completionBehavior = completionBehavior
        self.onIntroCompleted = onIntroCompleted
        self.onStart = onStart
        self.onCancel = onCancel
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                WorkoutStartAmbientBackground(tint: workoutTint, opacity: backgroundOpacity, rhythmGlow: lineGlow)

                VStack(spacing: 0) {
                    Spacer(minLength: max(106, proxy.size.height * 0.18))

                    VStack(spacing: 24) {
                        WorkoutStartPulseLineView(drawProgress: drawProgress, glowAmount: lineGlow, tint: workoutTint)
                            .frame(maxWidth: 470)
                            .frame(height: 132)
                            .opacity(lineOpacity)
                            .mask(
                                LinearGradient(
                                    colors: [.clear, .black, .black, .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )

                        workoutTitleStack
                            .opacity(titleOpacity)
                            .offset(y: contentOffset)
                    }

                    Spacer(minLength: showsStartButton ? 34 : 92)

                    if showsStartButton {
                        startButton
                            .frame(maxWidth: 340)
                            .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.94)))
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, max(34, proxy.safeAreaInsets.bottom + 18))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .overlay(alignment: .topLeading) {
                cancelButton
                    .padding(.leading, max(18, proxy.safeAreaInsets.leading + 18))
                    .padding(.top, max(16, proxy.safeAreaInsets.top + 10))
            }
        }
        .task {
            await runIntroIfNeeded()
        }
    }

    private var workoutTitleStack: some View {
        VStack(spacing: 13) {
            Text(workoutTitle)
                .pulsarTextStyle(.workoutHero)
                .fontWidth(.expanded)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, .white.opacity(0.92), workoutTint.opacity(0.78)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.76)
                .shadow(color: .white.opacity(0.12), radius: 10, y: 2)
                .shadow(color: workoutTint.opacity(0.28), radius: 28, y: 14)

            Text(workoutSubtitle)
                .pulsarTextStyle(.workoutSubtitle)
                .foregroundStyle(.white.opacity(0.60))
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
                    .pulsarTextStyle(.captionEmphasis)
                Text("Cancel")
                    .pulsarTextStyle(.label)
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
                    .pulsarTextStyle(.buttonTitle)
                Image(systemName: "arrow.right")
                    .pulsarTextStyle(.cardTitle)
            }
            .foregroundStyle(.white.opacity(0.94))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(
                LinearGradient(
                    colors: [
                        .white.opacity(0.20),
                        workoutTint.opacity(0.30),
                        .white.opacity(0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule(style: .continuous)
            )
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.48), workoutTint.opacity(0.34), .white.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: workoutTint.opacity(0.26), radius: 24, y: 12)
            .shadow(color: .black.opacity(0.26), radius: 20, y: 12)
        }
        .buttonStyle(WorkoutStartButtonStyle())
        .accessibilityHint("Begins the selected personalized workout")
    }

    private func runIntroIfNeeded() async {
        guard !hasStartedIntro else { return }
        hasStartedIntro = true
        hapticsManager.prepare()

        try? await Task.sleep(nanoseconds: 80_000_000)
        guard !Task.isCancelled else { return }

        withAnimation(.smooth(duration: 0.68)) {
            lineOpacity = 1
            titleOpacity = 1
            contentOffset = 0
        }

        try? await Task.sleep(nanoseconds: 120_000_000)
        guard !Task.isCancelled else { return }

        withAnimation(.timingCurve(0.18, 0.92, 0.18, 1.0, duration: 1.08)) {
            drawProgress = 1
        }

        try? await Task.sleep(nanoseconds: 620_000_000)
        guard !Task.isCancelled else { return }

        hapticsManager.playHeartbeat()

        withAnimation(.easeOut(duration: 0.18)) {
            lineGlow = 1
        }

        try? await Task.sleep(nanoseconds: 170_000_000)
        guard !Task.isCancelled else { return }

        withAnimation(.easeOut(duration: 0.22)) {
            lineGlow = 0.28
        }

        try? await Task.sleep(nanoseconds: 170_000_000)
        guard !Task.isCancelled else { return }

        hapticsManager.playHeartbeat()

        withAnimation(.easeOut(duration: 0.16)) {
            lineGlow = 0.86
        }

        try? await Task.sleep(nanoseconds: 220_000_000)
        guard !Task.isCancelled else { return }

        withAnimation(.easeOut(duration: 0.46)) {
            lineGlow = 0.08
        }

        switch completionBehavior {
        case .showStartButton:
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.52, dampingFraction: 0.82)) {
                showsStartButton = true
            }
        case .continueAutomatically:
            try? await Task.sleep(nanoseconds: 440_000_000)
            guard !Task.isCancelled else { return }
            onIntroCompleted?()
        }
    }
}

private extension PulsarOutdoorWorkoutKind {
    var startAnimationTint: Color {
        switch self {
        case .running, .indoorRunning:
            WorkoutAccent.velocity.color
        case .walking:
            WorkoutAccent.balance.color
        case .hiking:
            WorkoutAccent.terrain.color
        case .cycling, .rowing, .elliptical, .stairClimber:
            WorkoutAccent.endurance.color
        case .hiit, .boxing:
            WorkoutAccent.fire.color
        case .strength:
            WorkoutAccent.power.color
        case .yoga, .stretching, .cooldown:
            WorkoutAccent.restore.color
        case .pilates, .core, .mobility:
            WorkoutAccent.balance.color
        case .swimming:
            WorkoutAccent.water.color
        case .dance:
            WorkoutAccent.rhythm.color
        case .other:
            WorkoutAccent.focus.color
        }
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
