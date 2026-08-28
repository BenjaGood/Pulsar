//
//  GymFreeWorkoutHeader.swift
//  Pulsar
//

import SwiftUI

struct GymFreeWorkoutHeader: View {
    let state: ActiveGymWorkoutState
    let onOpenAudio: () -> Void
    let onMinimize: () -> Void

    private let toolbarButtonSize: CGFloat = 42

    var body: some View {
        VStack(spacing: 22) {
            PulsarGlassEffectGroup(spacing: 10) {
                HStack(spacing: 8) {
                    PulsarWorkoutToolbarIconButton(
                        systemImage: "music.note",
                        accessibilityLabel: "Workout audio",
                        size: toolbarButtonSize,
                        font: .body,
                        foregroundStyle: PulsarFitnessMonochromeDesign.primaryText,
                        action: onOpenAudio
                    )

                    PulsarWorkoutToolbarIconButton(
                        systemImage: "chevron.down",
                        accessibilityLabel: "Minimize workout",
                        size: toolbarButtonSize,
                        font: .body.bold(),
                        foregroundStyle: PulsarFitnessMonochromeDesign.primaryText,
                        action: onMinimize
                    )

                    Spacer(minLength: 8)
                }
                .overlay {
                    HStack(spacing: 6) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.caption.weight(.semibold))
                            .accessibilityHidden(true)
                        Text("Apple Watch Gym")
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .font(.caption)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                    .padding(.horizontal, toolbarButtonSize * 2 + 16)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Apple Watch Gym")
                    .allowsHitTesting(false)
                }
            }

            VStack(spacing: 8) {
                Text(GymFreeWorkoutTelemetry.title)
                    .font(.largeTitle.scaled(by: 1.08).bold())
                    .fontDesign(.default)
                    .foregroundStyle(Color.black)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .accessibilityAddTraits(.isHeader)

                Text(GymFreeWorkoutTelemetry.mirroredSubtitle)
                    .font(.body)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)

                        Text(
                            PulsarGymFormatters.duration(
                                GymFreeWorkoutTelemetry.elapsedSeconds(for: state, at: timeline.date)
                            )
                        )
                        .font(.title3.weight(.semibold).monospacedDigit())
                    }
                    .foregroundStyle(Color.black)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Live workout duration")
                    .accessibilityValue(
                        PulsarGymFormatters.duration(
                            GymFreeWorkoutTelemetry.elapsedSeconds(for: state, at: timeline.date)
                        )
                    )
                }
            }
        }
    }
}
