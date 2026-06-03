//
//  GymRoutineBuilderViews.swift
//  Pulsar
//

import PhotosUI
import SwiftUI
import UIKit

struct GymRoutineBuilderFlowView: View {
    private enum Route: Hashable {
        case routineDetails
    }

    @ObservedObject var routineStore: PulsarRoutineStore
    var initialRoutine: PulsarRoutine?
    var defaultWeightUnit: PulsarWeightUnit
    var onCancel: () -> Void
    var onStartWorkout: (PulsarRoutine) -> Void

    @StateObject private var catalogStore = ExerciseCatalogStore()
    @StateObject private var viewModel: RoutineBuilderViewModel
    @State private var path: [Route]

    init(
        routineStore: PulsarRoutineStore,
        initialRoutine: PulsarRoutine? = nil,
        defaultWeightUnit: PulsarWeightUnit = .kilograms,
        onCancel: @escaping () -> Void,
        onStartWorkout: @escaping (PulsarRoutine) -> Void
    ) {
        self.routineStore = routineStore
        self.initialRoutine = initialRoutine
        self.defaultWeightUnit = defaultWeightUnit
        self.onCancel = onCancel
        self.onStartWorkout = onStartWorkout
        _viewModel = StateObject(wrappedValue: initialRoutine.map {
            RoutineBuilderViewModel(routine: $0, defaultWeightUnit: defaultWeightUnit)
        } ?? RoutineBuilderViewModel(defaultWeightUnit: defaultWeightUnit))
        _path = State(initialValue: initialRoutine == nil ? [] : [.routineDetails])
    }

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
                        mode: initialRoutine == nil ? .create : .edit,
                        onStartWorkout: onStartWorkout
                    )
                }
            }
        }
        .tint(.white)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .background(GymGlassBackground().ignoresSafeArea())
        .onAppear {
            viewModel.updateDefaultWeightUnit(defaultWeightUnit)
        }
    }
}

private struct GymExercisePickerView: View {
    @ObservedObject var catalogStore: ExerciseCatalogStore
    @ObservedObject var viewModel: RoutineBuilderViewModel
    var onCancel: () -> Void
    var onContinue: () -> Void

    @State private var isPresentingCustomExerciseSheet = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                GymExerciseSearchBar(text: $viewModel.searchText)
                    .padding(.top, 8)

                GymMuscleGroupChips(
                    groups: catalogStore.availableMuscleGroups,
                    selection: $viewModel.selectedMuscleGroup
                )

                GymCustomExercisePrompt(searchText: viewModel.searchText) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    isPresentingCustomExerciseSheet = true
                }

                catalogContent
            }
            .padding(.horizontal, 18)
            .padding(.bottom, viewModel.canContinue ? 112 : 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .premiumScrollHeaderBlur(height: 52)
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
        .sheet(isPresented: $isPresentingCustomExerciseSheet) {
            GymCustomExerciseSheet(
                initialName: viewModel.searchText,
                initialMuscleGroup: viewModel.selectedMuscleGroup
            ) { draft in
                let exercise = try catalogStore.addCustomExercise(
                    name: draft.name,
                    primaryMuscleGroup: draft.muscleGroup,
                    imageData: draft.imageData
                )
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    viewModel.addExercise(exercise)
                }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
            .environment(\.colorScheme, .dark)
            .preferredColorScheme(.dark)
        }
    }

    @ViewBuilder
    private var catalogContent: some View {
        if catalogStore.isLoading && !catalogStore.hasExercises {
            GymCatalogStateView(
                symbolName: "dumbbell.fill",
                title: "Loading exercises",
                message: "Loading the Pulsar exercise catalog."
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
                    message: "Try another name, choose another muscle group, or create a custom exercise."
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

private struct GymCustomExercisePrompt: View {
    var searchText: String
    var action: () -> Void

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.10))
                    Image(systemName: "plus")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Create custom exercise")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)

                    Text(subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white.opacity(0.46))
            }
            .padding(14)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.75, green: 0.66, blue: 1.0).opacity(0.16),
                        .white.opacity(0.055)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(PulsarGymPressButtonStyle())
    }

    private var subtitle: String {
        if trimmedSearchText.isEmpty {
            return "Add your own name, photo, and muscle group."
        }
        return "Use \"\(trimmedSearchText)\" as a starting point."
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
                if url.isFileURL {
                    if let image = UIImage(contentsOfFile: url.path) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        fallbackIcon
                    }
                } else {
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

private struct GymCustomExerciseDraft {
    var name: String
    var muscleGroup: PulsarMuscleGroup
    var imageData: Data?
}

private struct GymCustomExerciseSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var exerciseName: String
    @State private var muscleGroup: PulsarMuscleGroup
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var selectedImageData: Data?
    @State private var errorMessage: String?
    @FocusState private var isNameFocused: Bool

    var onCreate: (GymCustomExerciseDraft) throws -> Void

    init(
        initialName: String,
        initialMuscleGroup: PulsarMuscleGroup?,
        onCreate: @escaping (GymCustomExerciseDraft) throws -> Void
    ) {
        let trimmedName = initialName.trimmingCharacters(in: .whitespacesAndNewlines)
        _exerciseName = State(initialValue: trimmedName)
        _muscleGroup = State(initialValue: initialMuscleGroup ?? .other)
        self.onCreate = onCreate
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    photoPicker
                    nameField
                    muscleGroupPicker

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(red: 1.0, green: 0.48, blue: 0.56))
                            .padding(.horizontal, 2)
                    }
                }
                .padding(18)
            }
            .background(GymGlassBackground().ignoresSafeArea())
            .navigationTitle("Custom Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.76))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create & Add") {
                        createExercise()
                    }
                    .font(.subheadline.weight(.bold))
                    .disabled(!canCreate)
                }
            }
            .onAppear {
                isNameFocused = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .onChange(of: selectedPhotoItem) { _, item in
                loadPhoto(from: item)
            }
        }
        .tint(.white)
    }

    private var canCreate: Bool {
        !exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var photoPicker: some View {
        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.white.opacity(0.085))

                if let selectedImage {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 30, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                        Text("Add exercise photo")
                            .font(.subheadline.weight(.bold))
                        Text("Optional, saved only for this custom exercise.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.54))
                    }
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 178)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.13), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Name")
                .font(.caption.weight(.black))
                .foregroundStyle(.white.opacity(0.58))

            TextField("Exercise name", text: $exerciseName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($isNameFocused)
                .submitLabel(.done)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(.white.opacity(0.085), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
        }
    }

    private var muscleGroupPicker: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Muscle division")
                .font(.caption.weight(.black))
                .foregroundStyle(.white.opacity(0.58))

            Menu {
                ForEach(PulsarMuscleGroup.allCases) { group in
                    Button {
                        muscleGroup = group
                    } label: {
                        if group == muscleGroup {
                            Label(group.displayName, systemImage: "checkmark")
                        } else {
                            Text(group.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(muscleGroup.displayName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white.opacity(0.48))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(.white.opacity(0.085), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
            }
        }
    }

    private func createExercise() {
        do {
            try onCreate(
                GymCustomExerciseDraft(
                    name: exerciseName,
                    muscleGroup: muscleGroup,
                    imageData: selectedImageData
                )
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadPhoto(from item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = "Could not load that photo. Try another image."
                return
            }
            selectedImage = image
            selectedImageData = GymCustomExerciseImageProcessor.jpegData(from: image)
            errorMessage = nil
        }
    }
}

private enum GymCustomExerciseImageProcessor {
    static func jpegData(from image: UIImage) -> Data? {
        let maxDimension: CGFloat = 900
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > 0 else { return image.jpegData(compressionQuality: 0.84) }

        let scale = min(1, maxDimension / longestSide)
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resizedImage.jpegData(compressionQuality: 0.84)
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

private struct GymSupersetEditorContext: Identifiable, Hashable {
    var groupID: UUID
    var routineExerciseID: UUID

    var id: String {
        "\(groupID.uuidString)-\(routineExerciseID.uuidString)"
    }
}

private struct GymRoutineCreationView: View {
    enum Mode {
        case create
        case edit
    }

    @ObservedObject var routineStore: PulsarRoutineStore
    @ObservedObject var viewModel: RoutineBuilderViewModel
    var mode: Mode
    var onStartWorkout: (PulsarRoutine) -> Void

    @State private var didSave = false
    @State private var expandedExerciseIDs: Set<UUID> = []
    @State private var isShowingEmojiPicker = false
    @State private var supersetPickerExercise: PulsarRoutineExercise?
    @State private var supersetEditorContext: GymSupersetEditorContext?
    @FocusState private var focusedPlanningField: GymPlanningInputField?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                routineNameSection
                planningSection
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, focusedPlanningField == nil ? 126 : 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .premiumScrollHeaderBlur(height: 52)
        .background(GymGlassBackground().ignoresSafeArea())
        .navigationTitle(mode == .edit ? "Edit Routine" : "Create Routine")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedPlanningField = nil
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if focusedPlanningField == nil {
                actionBar
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: focusedPlanningField)
        .onChange(of: viewModel.routineExercises) { _, _ in
            didSave = false
            if viewModel.routineExercises.count == 1, let firstID = viewModel.routineExercises.first?.id {
                expandedExerciseIDs = [firstID]
            }
        }
        .onChange(of: viewModel.routineName) { _, _ in
            didSave = false
        }
        .onChange(of: viewModel.routineEmoji) { _, _ in
            didSave = false
        }
        .onChange(of: viewModel.supersetGroups) { _, _ in
            didSave = false
        }
        .onAppear {
            if viewModel.routineExercises.count == 1, let firstID = viewModel.routineExercises.first?.id {
                expandedExerciseIDs = [firstID]
            }
        }
        .sheet(isPresented: $isShowingEmojiPicker) {
            GymRoutineEmojiPicker(
                selectedEmoji: $viewModel.routineEmoji,
                suggestedEmoji: PulsarRoutine.defaultEmoji(for: viewModel.routineExercises)
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.clear)
            .presentationCornerRadius(34)
            .presentationContentInteraction(.scrolls)
        }
        .sheet(item: $supersetPickerExercise) { routineExercise in
            GymSupersetPartnerPickerSheet(
                baseExercise: routineExercise,
                candidates: viewModel.supersetPartnerOptions(for: routineExercise.id)
            ) { partnerID, restSeconds in
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                    viewModel.createSuperset(
                        firstExerciseID: routineExercise.id,
                        secondExerciseID: partnerID,
                        restTimeSeconds: restSeconds
                    )
                    expandedExerciseIDs.insert(routineExercise.id)
                    expandedExerciseIDs.insert(partnerID)
                }
                supersetPickerExercise = nil
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.clear)
            .presentationCornerRadius(34)
        }
        .sheet(item: $supersetEditorContext) { context in
            if let group = viewModel.supersetGroup(id: context.groupID) {
                GymSupersetEditorSheet(
                    title: viewModel.supersetLabel(for: group.id),
                    group: group,
                    exercises: group.exerciseIds.compactMap { exerciseID in
                        viewModel.routineExercises.first(where: { $0.id == exerciseID })
                    },
                    onUpdateSets: { viewModel.updateSupersetSetCount(groupID: group.id, sharedSetCount: $0) },
                    onUpdateRest: { viewModel.updateSupersetRest(groupID: group.id, restTimeSeconds: $0) },
                    onRemoveExercise: {
                        viewModel.removeFromSuperset(routineExerciseID: context.routineExerciseID)
                        supersetEditorContext = nil
                    },
                    onBreakGroup: {
                        viewModel.dissolveSuperset(groupID: group.id)
                        supersetEditorContext = nil
                    }
                )
                .presentationDetents([.height(460), .medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.clear)
                .presentationCornerRadius(34)
            }
        }
    }

    private var routineNameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Routine Identity")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    isShowingEmojiPicker = true
                } label: {
                    Text(viewModel.resolvedRoutineEmoji)
                        .font(.system(size: 28))
                        .frame(width: 58, height: 58)
                        .background(.white.opacity(0.10), in: Circle())
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.14), lineWidth: 1)
                        }
                }
                .buttonStyle(PulsarGymPressButtonStyle())
                .accessibilityLabel("Choose routine icon")

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
                    let supersetGroup = viewModel.supersetGroup(containing: routineExercise.id)
                    GymRoutineExercisePlanningCard(
                        routineExercise: routineExercise,
                        viewModel: viewModel,
                        focusedField: $focusedPlanningField,
                        supersetGroup: supersetGroup,
                        supersetBadge: viewModel.supersetBadge(for: routineExercise),
                        isExpanded: isExpanded(routineExercise),
                        canCollapse: viewModel.routineExercises.count > 1,
                        onToggleExpanded: {
                            toggleExpanded(routineExercise)
                        },
                        onCreateSuperset: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            supersetPickerExercise = routineExercise
                        },
                        onEditSuperset: {
                            guard let supersetGroup else { return }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            supersetEditorContext = GymSupersetEditorContext(groupID: supersetGroup.id, routineExerciseID: routineExercise.id)
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
                let routine = viewModel.makeRoutine()
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
    var focusedField: FocusState<GymPlanningInputField?>.Binding
    var supersetGroup: PulsarSupersetGroup?
    var supersetBadge: String?
    var isExpanded: Bool
    var canCollapse: Bool
    var onToggleExpanded: () -> Void
    var onCreateSuperset: () -> Void
    var onEditSuperset: () -> Void
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
                    if let supersetBadge {
                        Text(supersetBadge)
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundStyle(Color(red: 0.78, green: 0.72, blue: 1.0))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(red: 0.72, green: 0.66, blue: 1.0).opacity(0.14), in: Capsule(style: .continuous))
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(Color(red: 0.78, green: 0.72, blue: 1.0).opacity(0.20), lineWidth: 1)
                            }
                    }

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

                Button(action: supersetGroup == nil ? onCreateSuperset : onEditSuperset) {
                    Image(systemName: supersetGroup == nil ? "link.badge.plus" : "link")
                        .font(.subheadline.weight(.black))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(supersetGroup == nil ? .white.opacity(0.76) : Color(red: 0.84, green: 0.78, blue: 1.0))
                        .frame(width: 32, height: 32)
                        .background(.white.opacity(supersetGroup == nil ? 0.075 : 0.12), in: Circle())
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(supersetGroup == nil ? 0.10 : 0.20), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .disabled(supersetGroup == nil && viewModel.routineExercises.count < 2)
                .accessibilityLabel(supersetGroup == nil ? "Create superset" : "Edit superset")

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
                            title: supersetGroup == nil ? "Sets" : "Shared Sets",
                            focus: .sets(routineExercise.id),
                            focusedField: focusedField,
                            value: Binding(
                                get: { supersetGroup?.sharedSetCount ?? routineExercise.plannedSets },
                                set: { newValue in
                                    if let supersetGroup {
                                        viewModel.updateSupersetSetCount(groupID: supersetGroup.id, sharedSetCount: newValue)
                                    } else {
                                        viewModel.updatePlan(for: routineExercise.id, plannedSets: newValue)
                                    }
                                    onEdit()
                                }
                            )
                        )

                        GymPlanIntegerField(
                            title: "Reps",
                            focus: .reps(routineExercise.id),
                            focusedField: focusedField,
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
                            focus: .weight(routineExercise.id),
                            focusedField: focusedField,
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
                        Text(supersetGroup == nil ? "Rest between sets" : "Superset rest")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.white.opacity(0.52))

                        HStack(spacing: 8) {
                            ForEach([30, 60, 90, 120], id: \.self) { seconds in
                                GymRestPresetButton(
                                    title: restPresetTitle(seconds),
                                    isSelected: (supersetGroup?.restTimeSeconds ?? routineExercise.plannedRestSeconds) == seconds
                                ) {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    if let supersetGroup {
                                        viewModel.updateSupersetRest(groupID: supersetGroup.id, restTimeSeconds: seconds)
                                    } else {
                                        viewModel.updatePlan(for: routineExercise.id, plannedRestSeconds: seconds)
                                    }
                                    onEdit()
                                }
                            }
                        }

                        GymPlanIntegerField(
                            title: "Custom Rest",
                            unit: "sec",
                            focus: .rest(routineExercise.id),
                            focusedField: focusedField,
                            value: Binding(
                                get: { supersetGroup?.restTimeSeconds ?? routineExercise.plannedRestSeconds },
                                set: { newValue in
                                    if let supersetGroup {
                                        viewModel.updateSupersetRest(groupID: supersetGroup.id, restTimeSeconds: newValue)
                                    } else {
                                        viewModel.updatePlan(for: routineExercise.id, plannedRestSeconds: newValue)
                                    }
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
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        }
    }

    private func restPresetTitle(_ seconds: Int) -> String {
        if seconds >= 60, seconds.isMultiple(of: 60) {
            return "Rest \(seconds / 60) min"
        }
        return "Rest \(seconds)s"
    }

    private var cardBackground: LinearGradient {
        LinearGradient(
            colors: supersetGroup == nil
                ? [.white.opacity(0.080), .white.opacity(0.052)]
                : [Color(red: 0.72, green: 0.66, blue: 1.0).opacity(0.13), .white.opacity(0.062)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBorder: Color {
        if supersetGroup != nil {
            return Color(red: 0.78, green: 0.72, blue: 1.0).opacity(isExpanded ? 0.32 : 0.22)
        }
        return .white.opacity(isExpanded ? 0.16 : 0.10)
    }
}

private enum GymPlanningInputField: Hashable {
    case sets(UUID)
    case reps(UUID)
    case weight(UUID)
    case rest(UUID)
}

private struct GymSupersetPartnerPickerSheet: View {
    var baseExercise: PulsarRoutineExercise
    var candidates: [PulsarRoutineExercise]
    var onCreate: (UUID, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPartnerID: UUID?
    @State private var restSeconds = 90

    init(
        baseExercise: PulsarRoutineExercise,
        candidates: [PulsarRoutineExercise],
        onCreate: @escaping (UUID, Int) -> Void
    ) {
        self.baseExercise = baseExercise
        self.candidates = candidates
        self.onCreate = onCreate
        _selectedPartnerID = State(initialValue: candidates.first?.id)
    }

    var body: some View {
        ZStack {
            GymSupersetSheetBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    sheetHeader(title: "Create Superset", subtitle: baseExercise.exerciseName)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Pair with")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.white.opacity(0.54))

                        VStack(spacing: 9) {
                            ForEach(candidates) { candidate in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    selectedPartnerID = candidate.id
                                } label: {
                                    HStack(spacing: 11) {
                                        Image(systemName: selectedPartnerID == candidate.id ? "checkmark.circle.fill" : "circle")
                                            .font(.headline.weight(.black))
                                            .symbolRenderingMode(.hierarchical)
                                            .foregroundStyle(selectedPartnerID == candidate.id ? Color(red: 0.70, green: 1.0, blue: 0.76) : .white.opacity(0.52))

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(candidate.exerciseName)
                                                .font(.subheadline.weight(.bold))
                                                .foregroundStyle(.white)
                                                .lineLimit(2)
                                            Text(candidate.primaryMuscleGroup.displayName)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.white.opacity(0.56))
                                        }

                                        Spacer(minLength: 0)
                                    }
                                    .padding(13)
                                    .background(.white.opacity(selectedPartnerID == candidate.id ? 0.12 : 0.065), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .stroke(.white.opacity(selectedPartnerID == candidate.id ? 0.22 : 0.08), lineWidth: 1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    GymSupersetRestSelector(restSeconds: $restSeconds)

                    Button {
                        guard let selectedPartnerID else { return }
                        onCreate(selectedPartnerID, restSeconds)
                        dismiss()
                    } label: {
                        Text("Create Superset")
                            .font(.headline.weight(.bold))
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
                    .disabled(selectedPartnerID == nil)
                }
                .padding(22)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func sheetHeader(title: String, subtitle: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Button("Done") {
                dismiss()
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white.opacity(0.84))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.white.opacity(0.08), in: Capsule(style: .continuous))
        }
    }
}

private struct GymSupersetEditorSheet: View {
    var title: String
    var group: PulsarSupersetGroup
    var exercises: [PulsarRoutineExercise]
    var onUpdateSets: (Int) -> Void
    var onUpdateRest: (Int) -> Void
    var onRemoveExercise: () -> Void
    var onBreakGroup: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sharedSets: Int
    @State private var restSeconds: Int

    init(
        title: String,
        group: PulsarSupersetGroup,
        exercises: [PulsarRoutineExercise],
        onUpdateSets: @escaping (Int) -> Void,
        onUpdateRest: @escaping (Int) -> Void,
        onRemoveExercise: @escaping () -> Void,
        onBreakGroup: @escaping () -> Void
    ) {
        self.title = title
        self.group = group
        self.exercises = exercises
        self.onUpdateSets = onUpdateSets
        self.onUpdateRest = onUpdateRest
        self.onRemoveExercise = onRemoveExercise
        self.onBreakGroup = onBreakGroup
        _sharedSets = State(initialValue: group.sharedSetCount)
        _restSeconds = State(initialValue: group.restTimeSeconds)
    }

    var body: some View {
        ZStack {
            GymSupersetSheetBackground()

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                        Text(exercises.map(\.exerciseName).joined(separator: " + "))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(2)
                    }

                    Spacer(minLength: 12)

                    Button("Done") {
                        dismiss()
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.84))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.08), in: Capsule(style: .continuous))
                }

                GymSupersetStepper(
                    title: "Shared Sets",
                    value: "\(sharedSets)",
                    onMinus: {
                        sharedSets = max(1, sharedSets - 1)
                        onUpdateSets(sharedSets)
                    },
                    onPlus: {
                        sharedSets = min(20, sharedSets + 1)
                        onUpdateSets(sharedSets)
                    }
                )

                GymSupersetRestSelector(
                    restSeconds: Binding(
                        get: { restSeconds },
                        set: { newValue in
                            restSeconds = newValue
                            onUpdateRest(newValue)
                        }
                    )
                )

                VStack(spacing: 10) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onRemoveExercise()
                        dismiss()
                    } label: {
                        Text("Remove from Superset")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white.opacity(0.86))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.white.opacity(0.09), in: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onBreakGroup()
                        dismiss()
                    } label: {
                        Text("Delete Superset")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color(red: 1.0, green: 0.58, blue: 0.58))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(red: 1.0, green: 0.40, blue: 0.45).opacity(0.11), in: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }
            .padding(22)
        }
        .preferredColorScheme(.dark)
    }
}

private struct GymSupersetRestSelector: View {
    @Binding var restSeconds: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Superset rest")
                .font(.caption.weight(.black))
                .foregroundStyle(.white.opacity(0.54))

            HStack(spacing: 8) {
                ForEach([30, 60, 90, 120], id: \.self) { seconds in
                    GymRestPresetButton(
                        title: seconds >= 60 ? "\(seconds / 60)m" : "\(seconds)s",
                        isSelected: restSeconds == seconds
                    ) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        restSeconds = seconds
                    }
                }
            }

            GymSupersetStepper(
                title: "Custom Rest",
                value: "\(restSeconds)s",
                onMinus: { restSeconds = max(0, restSeconds - 15) },
                onPlus: { restSeconds = min(600, restSeconds + 15) }
            )
        }
    }
}

private struct GymSupersetStepper: View {
    var title: String
    var value: String
    var onMinus: () -> Void
    var onPlus: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white.opacity(0.54))
                Text(value)
                    .font(.title3.weight(.black))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button(action: onMinus) {
                    Image(systemName: "minus")
                        .font(.subheadline.weight(.black))
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.08), in: Circle())
                }

                Button(action: onPlus) {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.black))
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.12), in: Circle())
                }
            }
            .foregroundStyle(.white.opacity(0.88))
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }
}

private struct GymSupersetSheetBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.04, blue: 0.09),
                    Color(red: 0.14, green: 0.07, blue: 0.20),
                    Color.black.opacity(0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.16)
        }
        .ignoresSafeArea()
    }
}

private struct GymPlanIntegerField: View {
    var title: String
    var unit: String = ""
    var focus: GymPlanningInputField
    var focusedField: FocusState<GymPlanningInputField?>.Binding
    @Binding var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(.white.opacity(0.52))

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                TextField(title, value: $value, format: .number)
                    .keyboardType(.numberPad)
                    .focused(focusedField, equals: focus)
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
    var focus: GymPlanningInputField
    var focusedField: FocusState<GymPlanningInputField?>.Binding
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(.white.opacity(0.52))

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                TextField(title, value: $value, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad)
                    .focused(focusedField, equals: focus)
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

private struct GymRoutineEmojiPicker: View {
    private static let defaultOptions: [String] = ["💪", "🦵", "🏋️", "🔥", "⚡️", "🏃", "🧠", "🪽", "🍑", "🧱", "🎯", "⭐️"]

    @Binding var selectedEmoji: String
    var suggestedEmoji: String
    @Environment(\.dismiss) private var dismiss
    @State private var customEmoji = ""
    @FocusState private var isCustomEmojiFocused: Bool

    private var options: [String] {
        let values = [suggestedEmoji] + Self.defaultOptions
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }

    var body: some View {
        ZStack {
            sheetBackground

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Routine Icon")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.white)
                            Text("Choose an emoji that makes this plan instantly recognizable.")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.62))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 12)
                        Button("Done") {
                            isCustomEmojiFocused = false
                            dismiss()
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.84))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.08), in: Capsule(style: .continuous))
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                        ForEach(options, id: \.self) { emoji in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                selectedEmoji = PulsarRoutine.normalizedEmoji(emoji)
                                isCustomEmojiFocused = false
                            } label: {
                                Text(emoji)
                                    .font(.system(size: 28))
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                    .background(
                                        isSelected(emoji) ? .white.opacity(0.22) : .white.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(isSelected(emoji) ? .white.opacity(0.34) : .white.opacity(0.10), lineWidth: 1)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack(spacing: 10) {
                        TextField("Custom emoji", text: $customEmoji)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .submitLabel(.done)
                            .focused($isCustomEmojiFocused)
                            .padding(14)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(.white.opacity(isCustomEmojiFocused ? 0.24 : 0.10), lineWidth: 1)
                            }
                            .onSubmit {
                                isCustomEmojiFocused = false
                            }
                            .onChange(of: customEmoji) { _, newValue in
                                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                customEmoji = trimmed.isEmpty ? "" : String(trimmed.prefix(4))
                            }

                        Button("Use") {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            selectedEmoji = PulsarRoutine.normalizedEmoji(customEmoji)
                            isCustomEmojiFocused = false
                            dismiss()
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color(red: 0.14, green: 0.09, blue: 0.22))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(.white.opacity(0.96), in: Capsule(style: .continuous))
                        .disabled(customEmoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isCustomEmojiFocused = false
                }
            }
        }
    }

    private func isSelected(_ emoji: String) -> Bool {
        if selectedEmoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return emoji == suggestedEmoji
        }
        return selectedEmoji == emoji
    }

    private var sheetBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.04, blue: 0.09),
                    Color(red: 0.13, green: 0.06, blue: 0.17),
                    Color.black.opacity(0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.16)
        }
        .ignoresSafeArea()
    }
}

#Preview {
    GymRoutineBuilderFlowView(
        routineStore: PulsarRoutineStore(defaults: .standard),
        onCancel: {},
        onStartWorkout: { _ in }
    )
}
