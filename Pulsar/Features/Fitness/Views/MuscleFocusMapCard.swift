//
//  MuscleFocusMapCard.swift
//  Pulsar
//

import SwiftUI

struct MuscleFocusMapCard: View {
    var isCurrentWeek: Bool
    var presentation: MuscleFocusMapPresentation?
    var isDestinationUseful = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var hasAppeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MuscleFocusMapHeader(isCurrentWeek: isCurrentWeek)
            if let presentation {
                MuscleFocusMapMainContent(
                    presentation: presentation,
                    hasAppeared: hasAppeared,
                    isRenderingEnabled: isDestinationUseful
                )
            } else {
                MuscleFocusMapPreparationPlaceholder()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .modifier(
            FitnessGlassSurfaceModifier(
                cornerRadius: 32,
                borderOpacity: 0.95
            )
        )
        .onAppear {
            if isDestinationUseful {
                reveal()
            }
        }
        .onChange(of: isDestinationUseful) { _, isUseful in
            if isUseful {
                reveal()
            }
        }
    }

    private func reveal() {
        guard !hasAppeared else { return }
        if reduceMotion {
            hasAppeared = true
        } else {
            withAnimation(.smooth(duration: 0.5)) {
                hasAppeared = true
            }
        }
    }
}

private struct MuscleFocusMapPreparationPlaceholder: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)

            Text("Preparing your training highlights")
                .font(.caption)
                .foregroundStyle(PulsarTheme.fitnessSecondaryText(for: colorScheme))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 348)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preparing muscle focus map")
    }
}

private struct MuscleFocusMapHeader: View {
    var isCurrentWeek: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text("Muscle Focus Map")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(PulsarTheme.fitnessPrimaryText(for: colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Image(systemName: "info.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PulsarTheme.fitnessSecondaryText(for: colorScheme))
                        .accessibilityHidden(true)
                }

                Text("Your training highlights")
                    .font(.subheadline)
                    .foregroundStyle(PulsarTheme.fitnessSecondaryText(for: colorScheme))
            }

            Spacer(minLength: 8)

            MuscleFocusMapStatusPill(isCurrentWeek: isCurrentWeek)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isCurrentWeek ? "Muscle Focus Map, active week" : "Muscle Focus Map, archived week")
    }
}

private struct MuscleFocusMapStatusPill: View {
    var isCurrentWeek: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isCurrentWeek ? PulsarFitnessMonochromeDesign.active : PulsarTheme.fitnessTertiaryText(for: colorScheme))
                .frame(width: 7, height: 7)

            Text(isCurrentWeek ? "Active" : "Archived")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(isCurrentWeek ? PulsarFitnessMonochromeDesign.primaryText : PulsarTheme.fitnessSecondaryText(for: colorScheme))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.58), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.black.opacity(0.07), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.045), radius: 12, y: 6)
        .accessibilityElement(children: .combine)
    }
}

private struct MuscleFocusMapMainContent: View {
    var presentation: MuscleFocusMapPresentation
    var hasAppeared: Bool
    var isRenderingEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MuscleBodyAssetMapView(
                presentation: presentation,
                hasAppeared: hasAppeared,
                isRenderingEnabled: isRenderingEnabled
            )
            .frame(maxWidth: .infinity)

            MuscleFocusMapPrimaryFocus(presentation: presentation)
        }
    }
}

private struct MuscleFocusMapPrimaryFocus: View {
    var presentation: MuscleFocusMapPresentation

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("PRIMARY FOCUS TODAY")
                .font(.caption.weight(.semibold))
                .tracking(1.1)
                .foregroundStyle(PulsarTheme.fitnessTertiaryText(for: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.70)

            HStack(spacing: 12) {
                Image(systemName: focusSymbol)
                    .font(.headline)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                    .frame(width: 42, height: 42)
                    .background(FitnessCircularGlassSurface(cornerRadius: 21))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(focusTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PulsarTheme.fitnessPrimaryText(for: colorScheme))
                        .lineLimit(1)

                    Text(focusSubtitle)
                        .font(.caption)
                        .foregroundStyle(PulsarTheme.fitnessSecondaryText(for: colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 6)

                Label(presentation.hasTrainingData ? presentation.overallIntensity.title : "Ready", systemImage: "flame.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PulsarTheme.fitnessPrimaryText(for: colorScheme))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.62), in: Capsule())
                    .overlay {
                        Capsule().stroke(.black.opacity(0.06), lineWidth: 0.7)
                    }
            }
            .padding(10)
            .background(.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 24))
            .pulsarFitnessMonochromeSurface(cornerRadius: 24, shadowOpacity: 0.035)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(focusTitle). \(focusSubtitle). \(presentation.overallIntensity.title) stimulus.")
        }
    }

    private var primaryEntry: MuscleFocusMapPresentation.Entry? {
        presentation.primaryFocus.first
    }

    private var focusTitle: String {
        guard let primaryEntry else { return "Ready for your next workout" }
        return "\(primaryEntry.displayName) Focus"
    }

    private var focusSubtitle: String {
        guard !presentation.primaryFocus.isEmpty else {
            return "Log a workout to reveal your focus"
        }
        return presentation.primaryFocus
            .prefix(3)
            .map(\.compactName)
            .joined(separator: ", ")
    }

    private var focusSymbol: String {
        primaryEntry?.muscleGroup == .cardio ? "waveform.path.ecg" : "dumbbell.fill"
    }
}

private struct MuscleFocusMapEmptyFocus: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Label("Log a workout to reveal your focus", systemImage: "figure.strengthtraining.traditional")
            .font(.caption)
            .foregroundStyle(PulsarTheme.fitnessSecondaryText(for: colorScheme))
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(colorScheme == .dark ? 0.045 : 0.48), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.white.opacity(colorScheme == .dark ? 0.10 : 0.46), lineWidth: 1)
            }
    }
}

#if DEBUG
#Preview("Muscle Focus Map - Upper Body") {
    muscleFocusMapPreview(viewModel: .previewUpperBody)
}

#Preview("Muscle Focus Map - Lower Body") {
    muscleFocusMapPreview(viewModel: .previewLowerBody)
}

#Preview("Muscle Focus Map - Full Body") {
    muscleFocusMapPreview(viewModel: .previewFullBody)
}

#Preview("Muscle Focus Map - Cardio Active") {
    muscleFocusMapPreview(viewModel: .previewCardioActive)
}

#Preview("Muscle Focus Map - Empty") {
    muscleFocusMapPreview(viewModel: .previewNoMuscles)
}

private func muscleFocusMapPreview(viewModel: MuscleMatrixViewModel) -> some View {
    ZStack {
        FitnessWeeklyBackground()
        ScrollView {
            MuscleFocusMapCard(
                isCurrentWeek: viewModel.week.isCurrentWeek,
                presentation: MuscleFocusMapPresentation(viewModel: viewModel)
            )
            .padding(22)
        }
    }
    .pulsarFitnessMonochromeAppearance()
}
#endif
