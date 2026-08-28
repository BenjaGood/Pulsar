//
//  GymMirroredWorkoutHeader.swift
//  Pulsar
//

import SwiftUI

struct GymMirroredWorkoutHeader: View {
    let state: ActiveGymWorkoutState
    let statusMessage: String
    let canShowRoutine: Bool
    let onOpenAudio: () -> Void
    let onMinimize: () -> Void
    let onShowRoutine: () -> Void

    var body: some View {
        VStack(spacing: 13) {
            PulsarGlassEffectGroup(spacing: 10) {
                HStack(spacing: 8) {
                    PulsarWorkoutToolbarIconButton(
                        systemImage: "music.note",
                        accessibilityLabel: "Workout audio",
                        size: 42,
                        font: .body,
                        foregroundStyle: PulsarFitnessMonochromeDesign.primaryText,
                        action: onOpenAudio
                    )

                    PulsarWorkoutToolbarIconButton(
                        systemImage: "chevron.down",
                        accessibilityLabel: "Minimize workout",
                        size: 42,
                        font: .body.bold(),
                        foregroundStyle: PulsarFitnessMonochromeDesign.primaryText,
                        action: onMinimize
                    )

                    Spacer(minLength: 2)

                    HStack(spacing: 5) {
                        Text(state.routineEmoji ?? "💪")
                            .accessibilityHidden(true)
                        Text("Apple Watch Gym")
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .font(.caption)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                    .accessibilityElement(children: .combine)

                    Spacer(minLength: 2)

                    Button(action: onShowRoutine) {
                        HStack(spacing: 5) {
                            Text("View All Routine")
                            Image(systemName: "chevron.right")
                                .accessibilityHidden(true)
                        }
                        .font(.caption.bold())
                        .foregroundStyle(Color.black)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 42)
                        .pulsarLiquidGlass(cornerRadius: 21, interactive: true, isClear: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canShowRoutine)
                    .opacity(canShowRoutine ? 1 : 0.42)
                    .accessibilityLabel("View all routine exercises")
                }
            }

            VStack(spacing: 9) {
                Text(state.routineName)
                    .font(.largeTitle.scaled(by: 1.12).bold())
                    .fontDesign(.default)
                    .foregroundStyle(Color.black)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)

                Text(statusMessage)
                    .font(.body)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)

                        Text(PulsarGymFormatters.duration(elapsedSeconds(at: timeline.date)))
                            .font(.title2.bold().monospacedDigit())
                    }
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .pulsarLiquidGlass(cornerRadius: 22, isClear: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Workout duration")
                }
            }
        }
    }

    private func elapsedSeconds(at date: Date) -> Int {
        guard !state.isFinished else { return state.elapsedSeconds }
        return max(state.elapsedSeconds, Int(date.timeIntervalSince(state.startedAt)))
    }
}
