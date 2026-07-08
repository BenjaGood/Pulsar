//
//  WorkoutPickerSheet.swift
//  Pulsar
//

import SwiftUI
import UIKit

private enum WorkoutPickerGlassTokens {
    static let cornerRadius: CGFloat = 36
    static let panelTint = Color(red: 0.68, green: 0.80, blue: 0.92)
    static let panelTintOpacity = 0.04
}

struct WorkoutPickerSheet: View {
    var onSelectPersonalizedWorkout: (WorkoutOption) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var searchText = ""

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ZStack(alignment: .top) {
            WorkoutPickerGlassBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    WorkoutSearchBar(text: $searchText)

                    VStack(alignment: .leading, spacing: 20) {
                        if !filteredPersonalizedWorkouts.isEmpty {
                            workoutSection(title: "Personalized Trainings", workouts: filteredPersonalizedWorkouts)
                        }

                        if !filteredGeneralWorkouts.isEmpty {
                            workoutSection(title: "Explore Workouts", workouts: filteredGeneralWorkouts)
                        }

                        if filteredPersonalizedWorkouts.isEmpty && filteredGeneralWorkouts.isEmpty {
                            emptyState
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .safeAreaPadding(.bottom, 16)
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) {
            dismiss()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Choose training")
                .pulsarTextStyle(.sectionTitle)
                .foregroundStyle(primaryText)

            Text("Quick-start a personalized workout or explore more movement modes.")
                .pulsarTextStyle(.screenSubtitle)
                .foregroundStyle(secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func workoutSection(title: String, workouts: [WorkoutOption]) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title)
                .pulsarTextStyle(.cardTitle)
                .foregroundStyle(primaryText)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(workouts) { workout in
                    WorkoutOptionCard(workout: workout, usesPickerGlass: true) {
                        handleSelection(workout)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            ZStack {
                PulsarCircularGlassSurface(cornerRadius: 31)
                    .frame(width: 62, height: 62)

                Image(systemName: "sparkle.magnifyingglass")
                    .pulsarTextStyle(.title)
                    .foregroundStyle(.secondary)
            }

            Text("No workouts found")
                .pulsarTextStyle(.cardTitle)
                .foregroundStyle(primaryText)

            Text("Try another search")
                .pulsarTextStyle(.label)
                .foregroundStyle(secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func handleSelection(_ workout: WorkoutOption) {
        UIImpactFeedbackGenerator(style: workout.isPersonalized ? .medium : .light).impactOccurred()

        guard workout.isPersonalized || workout.outdoorWorkoutKind != nil else { return }

        onSelectPersonalizedWorkout(workout)
        dismiss()
    }

    private var filteredPersonalizedWorkouts: [WorkoutOption] {
        filtered(WorkoutOption.personalized)
    }

    private var filteredGeneralWorkouts: [WorkoutOption] {
        filtered(WorkoutOption.general)
    }

    private func filtered(_ workouts: [WorkoutOption]) -> [WorkoutOption] {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearchText.isEmpty else { return workouts }

        return workouts.filter { workout in
            workout.name.localizedCaseInsensitiveContains(trimmedSearchText)
        }
    }

    private var primaryText: Color {
        PulsarTheme.fitnessPrimaryText(for: colorScheme)
    }

    private var secondaryText: Color {
        PulsarTheme.fitnessSecondaryText(for: colorScheme)
    }
}

private struct WorkoutPickerGlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WorkoutPickerGlassTokens.cornerRadius, style: .continuous)

        Rectangle()
            .fill(panelFill)
            .pulsarLiquidGlass(
                cornerRadius: 0,
                tint: WorkoutPickerGlassTokens.panelTint.opacity(reduceTransparency ? 0 : WorkoutPickerGlassTokens.panelTintOpacity),
                isClear: !reduceTransparency
            )
            .overlay {
                shape
                    .stroke(borderHighlight, lineWidth: reduceTransparency ? 0.85 : 0.65)
                    .blendMode(.plusLighter)
            }
            .overlay(alignment: .top) {
                specularHighlight
            }
            .ignoresSafeArea()
    }

    private var panelFill: some ShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(
                colorScheme == .dark
                    ? Color(red: 0.04, green: 0.055, blue: 0.09).opacity(0.88)
                    : Color.white.opacity(0.92)
            )
        }

        return AnyShapeStyle(
            colorScheme == .dark
                ? Color.white.opacity(0.03)
                : Color.white.opacity(0.08)
        )
    }

    private var borderHighlight: LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(colorScheme == .dark ? 0.30 : 0.72),
                .white.opacity(colorScheme == .dark ? 0.11 : 0.28),
                .white.opacity(colorScheme == .dark ? 0.04 : 0.12)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var specularHighlight: some View {
        LinearGradient(
            colors: [
                .clear,
                .white.opacity(colorScheme == .dark ? 0.46 : 0.72),
                .white.opacity(colorScheme == .dark ? 0.18 : 0.34),
                .clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1.2)
        .padding(.horizontal, 28)
        .padding(.top, 1.8)
        .clipShape(Capsule())
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}

#Preview {
    WorkoutPickerSheet { _ in }
        .background(FitnessWeeklyBackground())
}
