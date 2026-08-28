import SwiftUI

struct GymSavedRoutineCard: View {
    var routine: PulsarRoutine
    var lastPerformed: Date?
    var onStart: () -> Void
    var onEdit: () -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GymSavedRoutineCardHeader(
                routine: routine,
                subtitle: routineSubtitle,
                onEdit: onEdit,
                onDuplicate: onDuplicate,
                onDelete: onDelete
            )

            GymSavedRoutineMetadataRow(
                exerciseCount: routine.exerciseCountText,
                estimatedDuration: estimatedDurationText,
                lastPerformed: lastPerformed
            )

            Divider()
                .overlay(PulsarFitnessMonochromeDesign.hairline.opacity(0.65))

            GymSavedRoutineActions(
                onEdit: onEdit,
                onStart: onStart
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pulsarFitnessMonochromeSurface(
            cornerRadius: 28,
            shadowOpacity: 0.03
        )
    }

    private var routineSubtitle: String {
        let muscles = routine.mainMuscleGroupNames
        return muscles.isEmpty ? "Custom gym routine" : muscles.joined(separator: " / ")
    }

    private var estimatedDurationText: String {
        let minutes = max(1, Int((Double(routine.estimatedDurationSeconds) / 60).rounded()))
        return "~\(minutes) min"
    }
}

private struct GymSavedRoutineCardHeader: View {
    var routine: PulsarRoutine
    var subtitle: String
    var onEdit: () -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(routine.emoji)
                .font(.system(.title2, design: .default))
                .frame(width: 52, height: 52)
                .background(
                    PulsarCircularGlassSurface(
                        cornerRadius: 17,
                        tint: .white,
                        opacity: 0.48
                    )
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(routine.name)
                    .pulsarTextStyle(.cardTitle)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)

                Text(subtitle)
                    .pulsarTextStyle(.metadata)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
            }
            .layoutPriority(1)

            Spacer(minLength: 0)

            Menu {
                Button("Edit", systemImage: "pencil", action: onEdit)
                Button("Duplicate", systemImage: "plus.square.on.square", action: onDuplicate)
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Label("Routine options", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
                    .font(.headline)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
                    .background(
                        PulsarCircularGlassSurface(
                            cornerRadius: 22,
                            tint: .white,
                            opacity: 0.36
                        )
                    )
            }
            .accessibilityLabel("Options for \(routine.name)")
        }
    }
}

private struct GymSavedRoutineMetadataRow: View {
    var exerciseCount: String
    var estimatedDuration: String
    var lastPerformed: Date?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) {
                GymSavedRoutineMetadataItem(
                    title: exerciseCount,
                    systemImage: "figure.strengthtraining.traditional"
                )

                metadataSeparator

                GymSavedRoutineMetadataItem(
                    title: estimatedDuration,
                    systemImage: "clock"
                )

                if let lastPerformed {
                    metadataSeparator

                    GymSavedRoutineMetadataItem(
                        title: "Last \(lastPerformed.formatted(.dateTime.day().month(.abbreviated).year()))",
                        systemImage: "calendar"
                    )
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                GymSavedRoutineMetadataItem(
                    title: exerciseCount,
                    systemImage: "figure.strengthtraining.traditional"
                )
                GymSavedRoutineMetadataItem(
                    title: estimatedDuration,
                    systemImage: "clock"
                )
                if let lastPerformed {
                    GymSavedRoutineMetadataItem(
                        title: "Last \(lastPerformed.formatted(.dateTime.day().month(.abbreviated).year()))",
                        systemImage: "calendar"
                    )
                }
            }
        }
    }

    private var metadataSeparator: some View {
        Rectangle()
            .fill(PulsarFitnessMonochromeDesign.hairline)
            .frame(width: 1, height: 16)
            .accessibilityHidden(true)
    }
}

private struct GymSavedRoutineMetadataItem: View {
    var title: String
    var systemImage: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: dynamicTypeSize.isAccessibilitySize ? 8 : 4) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 12)

            Text(title)
                .pulsarTextStyle(.caption)
        }
            .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

private struct GymSavedRoutineActions: View {
    var onEdit: () -> Void
    var onStart: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                editButton
                startButton
            }

            VStack(spacing: 10) {
                startButton
                editButton
            }
        }
    }

    private var editButton: some View {
        Button(action: onEdit) {
            Label("Edit", systemImage: "pencil")
                .pulsarTextStyle(.buttonTitle)
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(.capsule)
                .background(
                    PulsarCircularGlassSurface(
                        cornerRadius: 24,
                        tint: .white,
                        opacity: 0.42
                    )
                )
        }
        .buttonStyle(GymRoutinePressButtonStyle())
    }

    private var startButton: some View {
        Button(action: onStart) {
            Label("Start", systemImage: "arrow.right")
                .labelStyle(GymStartRoutineLabelStyle())
                .pulsarTextStyle(.buttonTitle)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(.capsule)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.18, green: 0.19, blue: 0.21),
                            Color(red: 0.045, green: 0.05, blue: 0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.13), lineWidth: 0.7)
                }
                .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
        }
        .buttonStyle(GymRoutinePressButtonStyle())
    }
}

private struct GymStartRoutineLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.title
            configuration.icon
        }
    }
}
