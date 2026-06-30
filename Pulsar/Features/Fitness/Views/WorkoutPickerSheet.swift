//
//  WorkoutPickerSheet.swift
//  Pulsar
//

import SwiftUI
import UIKit

struct WorkoutPickerSheet: View {
    @Binding var isPresented: Bool
    var onSelectPersonalizedWorkout: (WorkoutOption) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var searchText = ""
    @State private var sheetIsVisible = false

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                dimmedBackdrop
                    .opacity(sheetIsVisible ? 1 : 0)
                    .onTapGesture {
                        dismiss()
                    }

                sheetCard
                    .frame(maxHeight: min(proxy.size.height * 0.82, 690))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .offset(y: sheetIsVisible ? 0 : 90)
                    .opacity(sheetIsVisible ? 1 : 0.35)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
        }
        .onAppear {
            withAnimation(.spring(response: 0.50, dampingFraction: 0.82)) {
                sheetIsVisible = true
            }
        }
    }

    private var dimmedBackdrop: some View {
        Color.black
            .opacity(colorScheme == .dark ? 0.36 : 0.22)
            .background(.ultraThinMaterial)
            .ignoresSafeArea()
    }

    private var sheetCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule(style: .continuous)
                .fill(.secondary.opacity(0.34))
                .frame(width: 42, height: 5)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 2)

            header

            WorkoutSearchBar(text: $searchText)

            ScrollView(showsIndicators: false) {
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
                .padding(.bottom, 8)
            }
        }
        .padding(18)
        .background(sheetBackground)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .overlay(sheetBorder)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.36 : 0.16), radius: 28, y: 16)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Choose training")
                    .pulsarTextStyle(.sectionTitle)
                    .foregroundStyle(primaryText)

                Text("Quick-start a personalized workout or explore more movement modes.")
                    .pulsarTextStyle(.screenSubtitle)
                    .foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(secondaryText)
                    .frame(width: 32, height: 32)
                    .background(closeButtonBackground, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close workout picker")
        }
    }

    private func workoutSection(title: String, workouts: [WorkoutOption]) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title)
                .pulsarTextStyle(.cardTitle)
                .foregroundStyle(primaryText)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(workouts) { workout in
                    WorkoutOptionCard(workout: workout) {
                        handleSelection(workout)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
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

        dismiss {
            onSelectPersonalizedWorkout(workout)
        }
    }

    private func dismiss(completion: (() -> Void)? = nil) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            sheetIsVisible = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            isPresented = false
            completion?()
        }
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
        colorScheme == .dark ? .white.opacity(0.97) : Color(red: 0.08, green: 0.10, blue: 0.15)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.62) : Color(red: 0.34, green: 0.38, blue: 0.46)
    }

    private var closeButtonBackground: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.white.opacity(0.10), Color.white.opacity(0.04)]
                : [Color.white.opacity(0.84), Color(red: 0.94, green: 0.97, blue: 1.00).opacity(0.58)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var sheetBackground: some View {
        RoundedRectangle(cornerRadius: 34, style: .continuous)
            .fill(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [
                            Color(red: 0.11, green: 0.13, blue: 0.21).opacity(0.88),
                            Color(red: 0.05, green: 0.07, blue: 0.12).opacity(0.94),
                            Color.accentColor.opacity(0.10)
                        ]
                        : [
                            Color.white.opacity(0.92),
                            Color(red: 0.95, green: 0.97, blue: 1.00).opacity(0.88),
                            Color.accentColor.opacity(0.08)
                        ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
    }

    private var sheetBorder: some View {
        RoundedRectangle(cornerRadius: 34, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        .white.opacity(colorScheme == .dark ? 0.22 : 0.92),
                        Color.accentColor.opacity(colorScheme == .dark ? 0.15 : 0.20),
                        .black.opacity(colorScheme == .dark ? 0.22 : 0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
}

#Preview {
    WorkoutPickerSheet(isPresented: .constant(true)) { _ in }
        .background(PulsarSectionBackground())
}
