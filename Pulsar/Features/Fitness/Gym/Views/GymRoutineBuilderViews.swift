//
//  GymRoutineBuilderViews.swift
//  Pulsar
//

import SwiftUI
import UIKit

struct GymRoutineBuilderFlowView: View {
    private enum Route: Hashable {
        case routineDetails
    }

    @ObservedObject var routineStore: PulsarRoutineStore
    var onCancel: () -> Void
    var onStartWorkout: (PulsarRoutine) -> Void

    @StateObject private var catalogStore = ExerciseCatalogStore()
    @StateObject private var viewModel = RoutineBuilderViewModel()
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            GymExercisePickerView(
                catalogStore: catalogStore,
                viewModel: viewModel,
                onCancel: onCancel,
                onContinue: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    path.append(.routineDetails)
                }
            )
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .routineDetails:
                    GymRoutineCreationView(
                        routineStore: routineStore,
                        viewModel: viewModel,
                        onStartWorkout: onStartWorkout
                    )
                }
            }
        }
        .tint(.white)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .background(GymGlassBackground().ignoresSafeArea())
    }
}

private struct GymExercisePickerView: View {
    @ObservedObject var catalogStore: ExerciseCatalogStore
    @ObservedObject var viewModel: RoutineBuilderViewModel
    var onCancel: () -> Void
    var onContinue: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                GymExerciseSearchBar(text: $viewModel.searchText)
                    .padding(.top, 8)

                GymMuscleGroupChips(
                    groups: catalogStore.availableMuscleGroups,
                    selection: $viewModel.selectedMuscleGroup
                )

                catalogContent
            }
            .padding(.horizontal, 18)
            .padding(.bottom, viewModel.canContinue ? 112 : 30)
        }
        .background(GymGlassBackground().ignoresSafeArea())
        .navigationTitle("Choose Exercises")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onCancel()
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white.opacity(0.78))
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    Task { await catalogStore.refreshCatalog() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.bold))
                }
                .disabled(catalogStore.isLoading)
                .accessibilityLabel("Refresh exercise catalog")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.canContinue {
                GymContinueButton(
                    title: "Continue",
                    count: viewModel.selectedExercises.count,
                    action: onContinue
                )
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            await catalogStore.loadCatalogIfNeeded()
        }
    }

    @ViewBuilder
    private var catalogContent: some View {
        if catalogStore.isLoading && !catalogStore.hasExercises {
            GymCatalogStateView(
                symbolName: "dumbbell.fill",
                title: "Loading exercises",
                message: "Syncing the wger catalog into Pulsar."
            )
            .padding(.top, 38)
        } else if !catalogStore.hasExercises {
            GymCatalogStateView(
                symbolName: "exclamationmark.triangle.fill",
                title: "Catalog unavailable",
                message: catalogStore.errorMessage ?? "Try refreshing when the network is available."
            )
            .padding(.top, 38)
        } else {
            let sections = viewModel.groupedExercises(from: catalogStore.exercises)
            if sections.isEmpty {
                GymCatalogStateView(
                    symbolName: "magnifyingglass",
                    title: "No exercises found",
                    message: "Try another name or muscle group."
                )
                .padding(.top, 38)
            } else {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(sections, id: \.group) { section in
                        GymExerciseSectionView(
                            group: section.group,
                            exercises: section.exercises,
                            viewModel: viewModel
                        )
                    }
                }
            }
        }
    }
}

private struct GymExerciseSectionView: View {
    var group: PulsarMuscleGroup
    var exercises: [PulsarExercise]
    @ObservedObject var viewModel: RoutineBuilderViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(group.displayName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)

                Text("\(exercises.count)")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white.opacity(0.56))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.08), in: Capsule(style: .continuous))

                Spacer(minLength: 0)
            }

            LazyVStack(spacing: 10) {
                ForEach(exercises) { exercise in
                    GymExerciseCard(
                        exercise: exercise,
                        isSelected: viewModel.isSelected(exercise)
                    ) {
                        UIImpactFeedbackGenerator(style: viewModel.isSelected(exercise) ? .light : .medium).impactOccurred()
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                            viewModel.toggleExercise(exercise)
                        }
                    }
                }
            }
        }
    }
}

private struct GymExerciseCard: View {
    var exercise: PulsarExercise
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                GymExerciseThumbnail(urlString: exercise.thumbnailURL, isSelected: isSelected)

                VStack(alignment: .leading, spacing: 8) {
                    Text(exercise.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.86)

                    HStack(spacing: 8) {
                        GymExerciseTag(text: exercise.primaryMuscleGroup.displayName, color: Color(red: 0.74, green: 0.66, blue: 1.0))
                        GymExerciseTag(text: exercise.equipment.first?.name ?? "Bodyweight", color: Color(red: 0.54, green: 0.82, blue: 1.0))
                    }
                }

                Spacer(minLength: 4)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.title3.weight(.bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? Color(red: 0.68, green: 1.0, blue: 0.74) : .white.opacity(0.68))
                    .frame(width: 30, height: 30)
            }
            .padding(12)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(cardBorder, lineWidth: isSelected ? 1.4 : 1)
            }
            .shadow(color: isSelected ? Color(red: 0.72, green: 0.66, blue: 1.0).opacity(0.22) : .black.opacity(0.10), radius: 14, y: 8)
        }
        .buttonStyle(PulsarGymPressButtonStyle())
        .accessibilityLabel("\(exercise.name), \(exercise.primaryMuscleGroup.displayName)")
    }

    private var cardBackground: LinearGradient {
        LinearGradient(
            colors: isSelected
                ? [Color.white.opacity(0.16), Color(red: 0.60, green: 0.52, blue: 1.0).opacity(0.16)]
                : [Color.white.opacity(0.095), Color.white.opacity(0.045)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBorder: LinearGradient {
        LinearGradient(
            colors: isSelected
                ? [Color(red: 0.75, green: 1.0, blue: 0.84).opacity(0.56), Color(red: 0.74, green: 0.66, blue: 1.0).opacity(0.36)]
                : [.white.opacity(0.14), .white.opacity(0.07)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct GymExerciseThumbnail: View {
    var urlString: String?
    var isSelected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(isSelected ? 0.15 : 0.09))

            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        fallbackIcon
                    case .empty:
                        ProgressView()
                            .tint(.white.opacity(0.72))
                    @unknown default:
                        fallbackIcon
                    }
                }
            } else {
                fallbackIcon
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: "figure.strengthtraining.traditional")
            .font(.title3.weight(.semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.white.opacity(0.74))
    }
}

private struct GymExerciseTag: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.black))
            .lineLimit(1)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule(style: .continuous))
    }
}

private struct GymMuscleGroupChips: View {
    var groups: [PulsarMuscleGroup]
    @Binding var selection: PulsarMuscleGroup?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                GymMuscleGroupChip(title: "All", isSelected: selection == nil) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                        selection = nil
                    }
                }

                ForEach(groups) { group in
                    GymMuscleGroupChip(title: group.displayName, isSelected: selection == group) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                            selection = group
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct GymMuscleGroupChip: View {
    var title: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.black))
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color(red: 0.14, green: 0.09, blue: 0.22) : .white.opacity(0.74))
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(background, in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(isSelected ? 0.42 : 0.10), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private var background: LinearGradient {
        LinearGradient(
            colors: isSelected
                ? [.white.opacity(0.96), Color(red: 0.84, green: 0.79, blue: 1.0).opacity(0.90)]
                : [.white.opacity(0.10), .white.opacity(0.045)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct GymExerciseSearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.58))

            TextField("Search exercises", text: $text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        text = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.58))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(.white.opacity(0.085), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct GymCatalogStateView: View {
    var symbolName: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 34, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.72))

            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)

            Text(message)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(26)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }
}

private struct GymContinueButton: View {
    var title: String
    var count: Int
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.headline.weight(.bold))

                Text("\(count)")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Color(red: 0.22, green: 0.16, blue: 0.32).opacity(0.92), in: Circle())

                Image(systemName: "arrow.right")
                    .font(.headline.weight(.bold))
            }
            .foregroundStyle(Color(red: 0.14, green: 0.09, blue: 0.22))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(
                LinearGradient(
                    colors: [.white.opacity(0.98), Color(red: 0.84, green: 0.78, blue: 1.0)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule(style: .continuous)
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.60), lineWidth: 1)
            }
            .shadow(color: Color(red: 0.72, green: 0.66, blue: 1.0).opacity(0.30), radius: 22, y: 10)
        }
        .buttonStyle(PulsarGymPressButtonStyle())
    }
}

private struct GymRoutineCreationView: View {
    @ObservedObject var routineStore: PulsarRoutineStore
    @ObservedObject var viewModel: RoutineBuilderViewModel
    var onStartWorkout: (PulsarRoutine) -> Void

    @State private var didSave = false
    @State private var expandedExerciseIDs: Set<UUID> = []

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                routineNameSection
                planningSection
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 126)
        }
        .background(GymGlassBackground().ignoresSafeArea())
        .navigationTitle("Create Routine")
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom) {
            actionBar
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
        }
        .onChange(of: viewModel.routineExercises) { _, _ in
            didSave = false
            if viewModel.routineExercises.count == 1, let firstID = viewModel.routineExercises.first?.id {
                expandedExerciseIDs = [firstID]
            }
        }
        .onChange(of: viewModel.routineName) { _, _ in
            didSave = false
        }
        .onAppear {
            if viewModel.routineExercises.count == 1, let firstID = viewModel.routineExercises.first?.id {
                expandedExerciseIDs = [firstID]
            }
        }
    }

    private var routineNameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Routine Name")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)

            TextField("Gym Routine", text: $viewModel.routineName)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .padding(16)
                .background(.white.opacity(0.085), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
        }
    }

    private var planningSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Planning")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)

                Text("\(viewModel.routineExercises.count)")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white.opacity(0.56))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.08), in: Capsule(style: .continuous))

                Spacer(minLength: 0)
            }

            VStack(spacing: 10) {
                ForEach(viewModel.routineExercises.sorted { $0.order < $1.order }) { routineExercise in
                    GymRoutineExercisePlanningCard(
                        routineExercise: routineExercise,
                        viewModel: viewModel,
                        isExpanded: isExpanded(routineExercise),
                        canCollapse: viewModel.routineExercises.count > 1,
                        onToggleExpanded: {
                            toggleExpanded(routineExercise)
                        },
                        onRemove: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                                viewModel.removeRoutineExercise(routineExercise)
                            }
                        },
                        onEdit: {
                            didSave = false
                        }
                    )
                }
            }
        }
    }

    private func isExpanded(_ routineExercise: PulsarRoutineExercise) -> Bool {
        viewModel.routineExercises.count == 1 || expandedExerciseIDs.contains(routineExercise.id)
    }

    private func toggleExpanded(_ routineExercise: PulsarRoutineExercise) {
        guard viewModel.routineExercises.count > 1 else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
            if expandedExerciseIDs.contains(routineExercise.id) {
                expandedExerciseIDs.remove(routineExercise.id)
            } else {
                expandedExerciseIDs.insert(routineExercise.id)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                _ = viewModel.save(using: routineStore)
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    didSave = true
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: didSave ? "checkmark" : "tray.and.arrow.down.fill")
                    Text(didSave ? "Saved" : "Save Routine")
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white.opacity(0.88))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(.white.opacity(0.10), in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.13), lineWidth: 1)
                }
            }
            .buttonStyle(PulsarGymPressButtonStyle())
            .disabled(!viewModel.canContinue)

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                let routine = viewModel.save(using: routineStore)
                onStartWorkout(routine)
            } label: {
                HStack(spacing: 8) {
                    Text("Start Workout")
                    Image(systemName: "arrow.right")
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color(red: 0.14, green: 0.09, blue: 0.22))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    LinearGradient(
                        colors: [.white.opacity(0.98), Color(red: 0.84, green: 0.78, blue: 1.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Capsule(style: .continuous)
                )
            }
            .buttonStyle(PulsarGymPressButtonStyle())
            .disabled(!viewModel.canContinue)
        }
    }
}

private struct GymRoutineExercisePlanningCard: View {
    var routineExercise: PulsarRoutineExercise
    @ObservedObject var viewModel: RoutineBuilderViewModel
    var isExpanded: Bool
    var canCollapse: Bool
    var onToggleExpanded: () -> Void
    var onRemove: () -> Void
    var onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                Text("\(routineExercise.order + 1)")
                    .font(.caption.weight(.black))
                    .foregroundStyle(Color(red: 0.18, green: 0.14, blue: 0.28))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.92), in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(routineExercise.exerciseName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text(routineExercise.planSummary)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(2)
                }

                Spacer(minLength: 4)

                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3.weight(.bold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color(red: 1.0, green: 0.58, blue: 0.58))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(routineExercise.exerciseName)")

                if canCollapse {
                    Button(action: onToggleExpanded) {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.white.opacity(0.70))
                            .frame(width: 28, height: 28)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .background(.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isExpanded ? "Collapse exercise plan" : "Expand exercise plan")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onToggleExpanded()
            }

            if isExpanded {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        GymPlanIntegerField(
                            title: "Sets",
                            value: Binding(
                                get: { routineExercise.plannedSets },
                                set: { newValue in
                                    viewModel.updatePlan(for: routineExercise.id, plannedSets: newValue)
                                    onEdit()
                                }
                            )
                        )

                        GymPlanIntegerField(
                            title: "Reps",
                            value: Binding(
                                get: { routineExercise.plannedReps },
                                set: { newValue in
                                    viewModel.updatePlan(for: routineExercise.id, plannedReps: newValue)
                                    onEdit()
                                }
                            )
                        )

                        GymPlanDecimalField(
                            title: "Weight",
                            unit: routineExercise.weightUnit.displayName,
                            value: Binding(
                                get: { routineExercise.plannedWeight },
                                set: { newValue in
                                    viewModel.updatePlan(for: routineExercise.id, plannedWeight: newValue)
                                    onEdit()
                                }
                            )
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            ForEach([30, 60, 90, 120], id: \.self) { seconds in
                                GymRestPresetButton(
                                    title: restPresetTitle(seconds),
                                    isSelected: routineExercise.plannedRestSeconds == seconds
                                ) {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    viewModel.updatePlan(for: routineExercise.id, plannedRestSeconds: seconds)
                                    onEdit()
                                }
                            }
                        }

                        GymPlanIntegerField(
                            title: "Custom Rest",
                            unit: "sec",
                            value: Binding(
                                get: { routineExercise.plannedRestSeconds },
                                set: { newValue in
                                    viewModel.updatePlan(for: routineExercise.id, plannedRestSeconds: newValue)
                                    onEdit()
                                }
                            )
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.white.opacity(0.52))

                        TextField(
                            "Add coaching notes",
                            text: Binding(
                                get: { routineExercise.notes ?? "" },
                                set: { newValue in
                                    viewModel.updatePlan(for: routineExercise.id, notes: newValue)
                                    onEdit()
                                }
                            ),
                            axis: .vertical
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2...4)
                        .textInputAutocapitalization(.sentences)
                        .padding(13)
                        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(.white.opacity(0.08), lineWidth: 1)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .background(.white.opacity(0.080), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(isExpanded ? 0.16 : 0.10), lineWidth: 1)
        }
    }

    private func restPresetTitle(_ seconds: Int) -> String {
        seconds >= 60 ? "\(seconds / 60)m" : "\(seconds)s"
    }
}

private struct GymPlanIntegerField: View {
    var title: String
    var unit: String = ""
    @Binding var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(.white.opacity(0.52))

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                TextField(title, value: $value, format: .number)
                    .keyboardType(.numberPad)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)

                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white.opacity(0.50))
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
        }
    }
}

private struct GymPlanDecimalField: View {
    var title: String
    var unit: String
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(.white.opacity(0.52))

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                TextField(title, value: $value, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)

                Text(unit)
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white.opacity(0.50))
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
        }
    }
}

private struct GymRestPresetButton: View {
    var title: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(isSelected ? Color(red: 0.14, green: 0.09, blue: 0.22) : .white.opacity(0.72))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(background, in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(isSelected ? 0.34 : 0.08), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private var background: LinearGradient {
        LinearGradient(
            colors: isSelected
                ? [.white.opacity(0.96), Color(red: 0.84, green: 0.78, blue: 1.0).opacity(0.88)]
                : [.white.opacity(0.08), .white.opacity(0.045)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

#Preview {
    GymRoutineBuilderFlowView(
        routineStore: PulsarRoutineStore(defaults: .standard),
        onCancel: {},
        onStartWorkout: { _ in }
    )
}
