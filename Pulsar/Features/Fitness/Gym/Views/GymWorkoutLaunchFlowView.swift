//
//  GymWorkoutLaunchFlowView.swift
//  Pulsar
//

import SwiftUI
import UIKit

struct GymWorkoutLaunchFlowView: View {
    private enum Step: Hashable {
        case intro
        case routineChoice
        case routineBuilder
        case workoutSession(PulsarRoutine)
    }

    @Environment(\.dismiss) private var dismiss
    @StateObject private var routineStore = PulsarRoutineStore()
    @State private var step: Step = .intro

    var body: some View {
        ZStack {
            switch step {
            case .intro:
                PersonalizedWorkoutStartView(
                    workout: .gym,
                    onStart: showRoutineChoice,
                    onCancel: { dismiss() }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.985)))

            case .routineChoice:
                GymRoutineChoiceView(
                    onCreateRoutine: showRoutineBuilder,
                    onStartEmptyWorkout: startEmptyWorkout,
                    onCancel: { dismiss() }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))

            case .routineBuilder:
                GymRoutineBuilderFlowView(
                    routineStore: routineStore,
                    onCancel: { showRoutineChoice() },
                    onStartWorkout: startWorkout(from:)
                )
                .transition(.opacity.combined(with: .scale(scale: 1.01)))

            case .workoutSession(let routine):
                GymWorkoutSessionView(routine: routine) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    dismiss()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.99)))
            }
        }
        .background(GymGlassBackground().ignoresSafeArea())
        .animation(.smooth(duration: 0.36), value: step)
    }

    private func showRoutineChoice() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        step = .routineChoice
    }

    private func showRoutineBuilder() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        step = .routineBuilder
    }

    private func startEmptyWorkout() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        step = .workoutSession(.emptyGymWorkout())
    }

    private func startWorkout(from routine: PulsarRoutine) {
        step = .workoutSession(routine)
    }
}

struct GymRoutineChoiceView: View {
    var onCreateRoutine: () -> Void
    var onStartEmptyWorkout: () -> Void
    var onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 54)

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(colorScheme == .dark ? 0.08 : 0.70))
                        .frame(width: 72, height: 72)
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(colorScheme == .dark ? 0.18 : 0.88), lineWidth: 1)
                        }

                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white, Color(red: 0.76, green: 0.69, blue: 1.0))
                }

                Text("Do you want to create a routine?")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Build a guided lift plan now, or jump straight into an open gym session.")
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)

            VStack(spacing: 12) {
                GymChoiceActionButton(
                    title: "Create Routine",
                    subtitle: "Choose exercises from the wger catalog",
                    symbolName: "sparkles",
                    prominence: .primary,
                    action: onCreateRoutine
                )

                GymChoiceActionButton(
                    title: "Start Empty Workout",
                    subtitle: "Track a freestyle gym session",
                    symbolName: "timer",
                    prominence: .secondary,
                    action: onStartEmptyWorkout
                )

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onCancel()
                } label: {
                    Text("Cancel")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.white.opacity(0.055), in: Capsule(style: .continuous))
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(.white.opacity(0.10), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 54)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct GymChoiceActionButton: View {
    enum Prominence {
        case primary
        case secondary
    }

    var title: String
    var subtitle: String
    var symbolName: String
    var prominence: Prominence
    var action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: prominence == .primary ? .medium : .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbolName)
                    .font(.headline.weight(.bold))
                    .frame(width: 42, height: 42)
                    .background(iconBackground, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)

                    Text(subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(subtitleColor)
                        .lineLimit(2)
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(chevronColor)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(background, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(border, lineWidth: 1)
            }
            .shadow(color: shadowColor, radius: prominence == .primary ? 24 : 14, y: 12)
        }
        .buttonStyle(PulsarGymPressButtonStyle())
    }

    private var background: LinearGradient {
        switch prominence {
        case .primary:
            LinearGradient(
                colors: [
                    Color.white.opacity(0.96),
                    Color(red: 0.84, green: 0.78, blue: 1.0).opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .secondary:
            LinearGradient(
                colors: [
                    Color.white.opacity(0.14),
                    Color.white.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var border: LinearGradient {
        LinearGradient(
            colors: prominence == .primary
                ? [.white.opacity(0.86), Color(red: 0.70, green: 0.62, blue: 1.0).opacity(0.32)]
                : [.white.opacity(0.18), .white.opacity(0.08)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var iconBackground: Color {
        prominence == .primary
            ? Color(red: 0.18, green: 0.14, blue: 0.30).opacity(0.10)
            : Color(red: 0.74, green: 0.66, blue: 1.0).opacity(0.16)
    }

    private var titleColor: Color {
        prominence == .primary
            ? Color(red: 0.12, green: 0.08, blue: 0.20)
            : .white.opacity(0.94)
    }

    private var subtitleColor: Color {
        prominence == .primary
            ? Color(red: 0.32, green: 0.26, blue: 0.42)
            : .white.opacity(0.60)
    }

    private var chevronColor: Color {
        prominence == .primary
            ? Color(red: 0.22, green: 0.14, blue: 0.34).opacity(0.62)
            : .white.opacity(0.44)
    }

    private var shadowColor: Color {
        prominence == .primary
            ? Color(red: 0.72, green: 0.62, blue: 1.0).opacity(0.34)
            : .black.opacity(0.18)
    }
}

struct GymGlassBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.04, blue: 0.09),
                    Color(red: 0.13, green: 0.06, blue: 0.17),
                    Color(red: 0.02, green: 0.02, blue: 0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 20) {
                ForEach(0..<12, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(.white.opacity(index.isMultiple(of: 3) ? 0.035 : 0.018))
                        .frame(height: 1)
                        .offset(x: index.isMultiple(of: 2) ? -26 : 34)
                }
            }
            .rotationEffect(.degrees(-11))
            .blendMode(.screen)
            .padding(.horizontal, -40)
        }
    }
}

struct PulsarGymPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.972 : 1)
            .brightness(configuration.isPressed ? 0.035 : 0)
            .animation(.spring(response: 0.26, dampingFraction: 0.76), value: configuration.isPressed)
    }
}

#Preview {
    GymWorkoutLaunchFlowView()
}
