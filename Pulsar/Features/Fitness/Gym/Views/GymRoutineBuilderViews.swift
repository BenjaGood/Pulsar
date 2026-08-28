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
        .environment(\.colorScheme, .light)
        .pulsarFitnessMonochromeAppearance()
        .background(GymGlassBackground().ignoresSafeArea())
        .onAppear {
            viewModel.updateDefaultWeightUnit(defaultWeightUnit)
        }
    }
}

private enum GymExercisePickerMetrics {
    static let chromeActionSize: CGFloat = 46
    static let chromeExpandedTopPadding: CGFloat = 12
    static let chromeCompactTopPadding: CGFloat = 8
    static let chromeToTitleSpacing: CGFloat = 12
    static let titleBottomPadding: CGFloat = 18
    static let searchHeight: CGFloat = 50
    static let searchRadius: CGFloat = 25
    static let searchBottomPadding: CGFloat = 16
    static let filterHeight: CGFloat = 42
    static let filterHorizontalPadding: CGFloat = 16
    static let filterSpacing: CGFloat = 8
    static let filterRadius: CGFloat = 21
    static let filterBottomPadding: CGFloat = 20
    static let customMinHeight: CGFloat = 96
    static let customRadius: CGFloat = 26
    static let customPadding: CGFloat = 12
    static let customActionSize: CGFloat = 46
    static let customBottomPadding: CGFloat = 24
    static let sectionHeaderToRows: CGFloat = 12
    static let sectionToSection: CGFloat = 22
    static let rowGap: CGFloat = 7
    static let rowMinHeight: CGFloat = 96
    static let rowVerticalPadding: CGFloat = 11
    static let rowHorizontalPadding: CGFloat = 13
    static let rowRadius: CGFloat = 23
    static let imageSize: CGFloat = 74
    static let rowActionSize: CGFloat = 42
    static let rowActionHitSize: CGFloat = 44
    static let rowActionSpacing: CGFloat = 6
    static let addClusterSpacing: CGFloat = 10
    static let surfaceShadowRadius: CGFloat = 10
    static let surfaceShadowY: CGFloat = 4
    static let continueControlHeight: CGFloat = 72
    static let continueBadgeSize: CGFloat = 38
    static let continueContentSpacing: CGFloat = 16
    static let headerBlurFadeStart: CGFloat = PulsarScreenHeaderBlur.standard.fadeStart
    static let headerBlurFadeEnd: CGFloat = PulsarScreenHeaderBlur.standard.fadeEnd

    static var chromeCollapseTravel: CGFloat {
        max(0, chromeExpandedTopPadding - chromeCompactTopPadding)
    }
}

private struct GymExercisePickerHeaderLayout {
    var safeAreaTop: CGFloat

    var controlDiameter: CGFloat { GymExercisePickerMetrics.chromeActionSize }
    var compactBottomPadding: CGFloat { GymExercisePickerMetrics.chromeCompactTopPadding }
    var scrimFadeTail: CGFloat { 16 }

    var expandedControlTop: CGFloat {
        GymExercisePickerMetrics.chromeExpandedTopPadding
    }

    var compactControlTop: CGFloat {
        GymExercisePickerMetrics.chromeCompactTopPadding
    }

    var compactHeaderHeight: CGFloat {
        compactControlTop + controlDiameter + compactBottomPadding
    }

    var expandedHeaderSpacing: CGFloat {
        expandedControlTop
            + controlDiameter
            + GymExercisePickerMetrics.chromeToTitleSpacing
    }

    func controlTop(scrollOffset: CGFloat) -> CGFloat {
        max(compactControlTop, expandedControlTop - max(0, scrollOffset))
    }
}

private extension View {
    func gymExercisePickerSurface(
        cornerRadius: CGFloat,
        isInteractive: Bool = false,
        shadowOpacity: Double
    ) -> some View {
        pulsarFitnessMonochromeSurface(
            cornerRadius: cornerRadius,
            isInteractive: isInteractive,
            shadowOpacity: shadowOpacity,
            shadowRadius: GymExercisePickerMetrics.surfaceShadowRadius,
            shadowY: GymExercisePickerMetrics.surfaceShadowY,
            usesCompactHighlight: true
        )
    }
}

private struct GymExercisePickerView: View {
    @ObservedObject var catalogStore: ExerciseCatalogStore
    @ObservedObject var viewModel: RoutineBuilderViewModel
    var onCancel: () -> Void
    var onContinue: () -> Void

    @State private var isPresentingCustomExerciseSheet = false
    @State private var selectedExerciseDetails: PulsarExercise?
    @State private var headerState = GymExercisePickerHeaderState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let headerLayout = GymExercisePickerHeaderLayout(
                safeAreaTop: max(proxy.safeAreaInsets.top, 0)
            )

            ZStack(alignment: .top) {
                PulsarFitnessMonochromeBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear
                            .frame(height: headerLayout.expandedHeaderSpacing)
                            .accessibilityHidden(true)

                        Text("Choose Exercises")
                            .font(.largeTitle.bold())
                            .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                            .padding(.bottom, GymExercisePickerMetrics.titleBottomPadding)

                        GymExerciseSearchBar(text: $viewModel.searchText)
                            .padding(.bottom, GymExercisePickerMetrics.searchBottomPadding)

                        GymMuscleGroupChips(
                            groups: catalogStore.availableMuscleGroups,
                            selection: $viewModel.selectedMuscleGroup
                        )
                        .padding(.bottom, GymExercisePickerMetrics.filterBottomPadding)

                        GymCustomExercisePrompt(searchText: viewModel.searchText) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            isPresentingCustomExerciseSheet = true
                        }
                        .padding(.bottom, GymExercisePickerMetrics.customBottomPadding)

                        catalogContent
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, viewModel.canContinue ? 112 : 30)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollContentBackground(.hidden)
                .gymExercisePickerHeaderProgress(state: headerState)
                .safeAreaInset(edge: .bottom) {
                    if viewModel.canContinue {
                        GymContinueButton(
                            title: "Continue",
                            count: viewModel.selectedExercises.count,
                            action: onContinue
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }

                GymExercisePickerStickyHeader(
                    layout: headerLayout,
                    headerState: headerState,
                    isRefreshDisabled: catalogStore.isLoading,
                    onClose: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onCancel()
                    },
                    onRefresh: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        Task { await catalogStore.refreshCatalog() }
                    }
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
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
                withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82)) {
                    viewModel.addExercise(exercise)
                }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
            .environment(\.colorScheme, .light)
            .pulsarFitnessMonochromeAppearance()
        }
        .sheet(item: $selectedExerciseDetails) { exercise in
            GymExerciseCatalogDetailSheet(exercise: exercise)
                .environment(\.colorScheme, .light)
                .pulsarFitnessMonochromeAppearance()
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
                LazyVStack(alignment: .leading, spacing: GymExercisePickerMetrics.rowGap) {
                    ForEach(Array(sections.enumerated()), id: \.element.group) { index, section in
                        Section {
                            ForEach(section.exercises) { exercise in
                                GymExerciseCard(
                                    exercise: exercise,
                                    isSelected: viewModel.isSelected(exercise)
                                ) {
                                    UIImpactFeedbackGenerator(
                                        style: viewModel.isSelected(exercise) ? .light : .medium
                                    ).impactOccurred()
                                    withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82)) {
                                        viewModel.toggleExercise(exercise)
                                    }
                                } onShowDetails: {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    selectedExerciseDetails = exercise
                                }
                            }
                        } header: {
                            GymExerciseSectionView(
                                group: section.group,
                                count: section.exercises.count
                            )
                            .padding(
                                .top,
                                index == 0
                                    ? 0
                                    : GymExercisePickerMetrics.sectionToSection - GymExercisePickerMetrics.rowGap
                            )
                            .padding(
                                .bottom,
                                GymExercisePickerMetrics.sectionHeaderToRows - GymExercisePickerMetrics.rowGap
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct GymExerciseSectionView: View {
    var group: PulsarMuscleGroup
    var count: Int

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle
                exerciseCount
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionTitle
                exerciseCount
            }
        }
    }

    private var sectionTitle: some View {
        Text(group.displayName)
            .font(.title.bold())
            .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var exerciseCount: some View {
        Text("\(count)")
            .font(.subheadline.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
            .padding(.horizontal, 9)
            .frame(minHeight: 28)
            .background(Color.black.opacity(0.045), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.black.opacity(0.045), lineWidth: 0.7)
            }
    }
}

private struct GymCustomExercisePrompt: View {
    var searchText: String
    var action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Button(action: action) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            GymExercisePickerActionSurface(
                                systemImage: "plus",
                                size: GymExercisePickerMetrics.customActionSize
                            )
                            Spacer(minLength: 20)

                            Image(systemName: "chevron.right")
                                .font(.body.weight(.medium))
                                .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                        }

                        Text("Create custom exercise")
                            .font(.headline)
                            .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)

                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                            .lineSpacing(2)
                    }
                } else {
                    HStack(spacing: 12) {
                        GymExercisePickerActionSurface(
                            systemImage: "plus",
                            size: GymExercisePickerMetrics.customActionSize
                        )

                        VStack(alignment: .leading, spacing: 5) {
                            Text("Create custom exercise")
                                .font(.headline)
                                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.88)

                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                                .lineLimit(2)
                                .lineSpacing(2)
                        }

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.right")
                            .font(.body.weight(.medium))
                            .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                    }
                }
            }
            .padding(GymExercisePickerMetrics.customPadding)
            .frame(
                maxWidth: .infinity,
                minHeight: GymExercisePickerMetrics.customMinHeight,
                alignment: .leading
            )
            .contentShape(.rect(cornerRadius: GymExercisePickerMetrics.customRadius))
            .gymExercisePickerSurface(
                cornerRadius: GymExercisePickerMetrics.customRadius,
                isInteractive: true,
                shadowOpacity: 0.03
            )
        }
        .buttonStyle(GymExercisePickerPressButtonStyle())
        .accessibilityHint("Opens the custom exercise editor")
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
    var onShowDetails: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var rowActionSize: CGFloat {
        dynamicTypeSize.isAccessibilitySize
            ? GymExercisePickerMetrics.rowActionHitSize
            : GymExercisePickerMetrics.rowActionSize
    }

    var body: some View {
        HStack(spacing: GymExercisePickerMetrics.rowActionSpacing) {
            Button(action: action) {
                HStack(spacing: GymExercisePickerMetrics.addClusterSpacing) {
                    thumbnailTile

                    VStack(alignment: .leading, spacing: 6) {
                        Text(exercise.name)
                            .font(.headline)
                            .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                            .multilineTextAlignment(.leading)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 6) {
                                GymExerciseTag(text: exercise.primaryMuscleGroup.displayName)
                                GymExerciseTag(text: exercise.equipment.first?.name ?? "Bodyweight")
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                GymExerciseTag(text: exercise.primaryMuscleGroup.displayName)
                                GymExerciseTag(text: exercise.equipment.first?.name ?? "Bodyweight")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                    GymExercisePickerActionSurface(
                        systemImage: isSelected ? "checkmark" : "plus",
                        size: rowActionSize,
                        isSelected: isSelected
                    )
                    .frame(
                        width: GymExercisePickerMetrics.rowActionHitSize,
                        height: GymExercisePickerMetrics.rowActionHitSize
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(GymExercisePickerPressButtonStyle())
            .accessibilityLabel(isSelected ? "Remove \(exercise.name)" : "Add \(exercise.name)")
            .accessibilityValue(isSelected ? "Selected" : "Not selected")

            Button(action: onShowDetails) {
                GymExercisePickerActionSurface(systemImage: "info", size: rowActionSize)
                    .frame(
                        width: GymExercisePickerMetrics.rowActionHitSize,
                        height: GymExercisePickerMetrics.rowActionHitSize
                    )
            }
            .buttonStyle(GymExercisePickerPressButtonStyle())
            .fixedSize()
            .accessibilityLabel("Show details for \(exercise.name)")
        }
        .padding(.horizontal, GymExercisePickerMetrics.rowHorizontalPadding)
        .padding(.vertical, GymExercisePickerMetrics.rowVerticalPadding)
        .frame(
            maxWidth: .infinity,
            minHeight: dynamicTypeSize.isAccessibilitySize ? nil : GymExercisePickerMetrics.rowMinHeight,
            alignment: .leading
        )
        .gymExercisePickerSurface(
            cornerRadius: GymExercisePickerMetrics.rowRadius,
            shadowOpacity: isSelected ? 0.035 : 0.025
        )
        .overlay {
            RoundedRectangle(cornerRadius: GymExercisePickerMetrics.rowRadius, style: .continuous)
                .strokeBorder(
                    PulsarFitnessMonochromeDesign.primaryText.opacity(isSelected ? 0.15 : 0),
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .contain)
    }

    private var thumbnailTile: some View {
        GymExerciseThumbnailView(
            thumbnailURL: exercise.thumbnailURL,
            muscleGroup: exercise.primaryMuscleGroup,
            size: GymExercisePickerMetrics.imageSize,
            usesLightSurface: true
        )
    }
}

private struct GymExerciseTag: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .fixedSize(horizontal: true, vertical: false)
            .background(Color.black.opacity(0.045), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.black.opacity(0.04), lineWidth: 0.65)
            }
    }
}

private struct GymMuscleGroupChips: View {
    var groups: [PulsarMuscleGroup]
    @Binding var selection: PulsarMuscleGroup?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: GymExercisePickerMetrics.filterSpacing) {
                GymMuscleGroupChip(title: "All", isSelected: selection == nil) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.84)) {
                        selection = nil
                    }
                }

                ForEach(groups) { group in
                    GymMuscleGroupChip(title: group.displayName, isSelected: selection == group) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.84)) {
                            selection = group
                        }
                    }
                }
            }
            .padding(.vertical, 3)
        }
        .contentMargins(.horizontal, 1, for: .scrollContent)
    }
}

private struct GymMuscleGroupChip: View {
    var title: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .lineLimit(1)
                .foregroundStyle(
                    isSelected
                        ? PulsarFitnessMonochromeDesign.primaryText
                        : PulsarFitnessMonochromeDesign.secondaryText
                )
                .padding(.horizontal, GymExercisePickerMetrics.filterHorizontalPadding)
                .frame(height: GymExercisePickerMetrics.filterHeight)
                .background(
                    PulsarFitnessMonochromeDesign.primaryText.opacity(isSelected ? 0.08 : 0),
                    in: Capsule()
                )
                .gymExercisePickerSurface(
                    cornerRadius: GymExercisePickerMetrics.filterRadius,
                    isInteractive: true,
                    shadowOpacity: isSelected ? 0.03 : 0.02
                )
        }
        .frame(minHeight: GymExercisePickerMetrics.rowActionHitSize)
        .buttonStyle(GymExercisePickerPressButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct GymExerciseSearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)

            TextField("Search exercises", text: $text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .font(.body)
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        text = ""
                    }
                } label: {
                    Label("Clear search", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.body)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, text.isEmpty ? 18 : 8)
        .frame(maxWidth: .infinity, minHeight: GymExercisePickerMetrics.searchHeight)
        .gymExercisePickerSurface(
            cornerRadius: GymExercisePickerMetrics.searchRadius,
            shadowOpacity: 0.025
        )
    }
}

private struct GymExercisePickerStickyHeader: View {
    var layout: GymExercisePickerHeaderLayout
    var headerState: GymExercisePickerHeaderState
    var isRefreshDisabled: Bool
    var onClose: () -> Void
    var onRefresh: () -> Void

    var body: some View {
        let progress = headerState.progress
        let offset = headerState.offset

        ZStack(alignment: .top) {
            GymExercisePickerHeaderScrim(
                layout: layout,
                progress: progress
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .animation(nil, value: progress)

            GymExercisePickerFloatingChrome(
                isRefreshDisabled: isRefreshDisabled,
                onClose: onClose,
                onRefresh: onRefresh
            )
            .padding(.horizontal, 20)
            .padding(.top, layout.controlTop(scrollOffset: offset))
            .animation(nil, value: offset)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

private struct GymExercisePickerHeaderScrim: View {
    var layout: GymExercisePickerHeaderLayout
    var progress: CGFloat

    var body: some View {
        PulsarTopBlurOverlay(
            height: layout.compactHeaderHeight + layout.scrimFadeTail,
            safeAreaTop: layout.safeAreaTop,
            solidContentHeight: layout.compactHeaderHeight,
            style: .collapsingHeader
        )
        .opacity(Double(progress))
        .frame(height: layout.safeAreaTop + layout.compactHeaderHeight + layout.scrimFadeTail)
        .frame(maxWidth: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .top)
    }
}

@MainActor
@Observable
private final class GymExercisePickerHeaderState {
    var offset: CGFloat = 0
    var progress: CGFloat = 0
}

private struct GymExercisePickerHeaderScrollModifier: ViewModifier {
    var state: GymExercisePickerHeaderState

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { _, newOffset in
                let pinOffset = min(newOffset, GymExercisePickerMetrics.chromeCollapseTravel)
                let quantizedOffset = (pinOffset * 2).rounded() / 2

                let fadeStart = GymExercisePickerMetrics.headerBlurFadeStart
                let fadeEnd = GymExercisePickerMetrics.headerBlurFadeEnd
                let rawProgress: CGFloat
                if fadeEnd > fadeStart {
                    rawProgress = min(max((newOffset - fadeStart) / (fadeEnd - fadeStart), 0), 1)
                } else {
                    rawProgress = newOffset > fadeStart ? 1 : 0
                }
                let quantizedProgress = (
                    rawProgress * PulsarCollapsingHeaderMetrics.progressSteps
                ).rounded() / PulsarCollapsingHeaderMetrics.progressSteps

                if state.offset != quantizedOffset {
                    state.offset = quantizedOffset
                }
                if state.progress != quantizedProgress {
                    state.progress = quantizedProgress
                }
            }
    }
}

private extension View {
    func gymExercisePickerHeaderProgress(
        state: GymExercisePickerHeaderState
    ) -> some View {
        modifier(GymExercisePickerHeaderScrollModifier(state: state))
    }
}

private struct GymExercisePickerFloatingChrome: View {
    var isRefreshDisabled: Bool
    var onClose: () -> Void
    var onRefresh: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            GymExercisePickerChromeButton(
                systemImage: "xmark",
                accessibilityLabel: "Close",
                action: onClose
            )

            Spacer(minLength: 20)
                .allowsHitTesting(false)

            GymExercisePickerChromeButton(
                systemImage: "arrow.clockwise",
                accessibilityLabel: "Refresh",
                action: onRefresh
            )
            .disabled(isRefreshDisabled)
        }
        .frame(height: GymExercisePickerMetrics.chromeActionSize)
    }
}

private struct GymExercisePickerChromeButton: View {
    var systemImage: String
    var accessibilityLabel: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: max(17, GymExercisePickerMetrics.chromeActionSize * 0.40), weight: .medium))
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                .frame(
                    width: GymExercisePickerMetrics.chromeActionSize,
                    height: GymExercisePickerMetrics.chromeActionSize
                )
                .modifier(GymExercisePickerChromeGlassModifier())
                .accessibilityHidden(true)
        }
        .buttonStyle(GymExercisePickerPressButtonStyle())
        .buttonBorderShape(.circle)
        .frame(
            width: GymExercisePickerMetrics.chromeActionSize,
            height: GymExercisePickerMetrics.chromeActionSize
        )
        .contentShape(Circle())
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct GymExercisePickerChromeGlassModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(PulsarTabPalette.cardBackground, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(Color.black.opacity(0.10), lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .shadow(
                    color: PulsarTabPalette.shadowColor.opacity(0.02),
                    radius: GymExercisePickerMetrics.surfaceShadowRadius,
                    y: GymExercisePickerMetrics.surfaceShadowY
                )
        } else {
            content
                .background(PulsarTabPalette.cardBackground.opacity(0.64), in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.90), lineWidth: 0.7)
                        .allowsHitTesting(false)
                }
                .shadow(
                    color: PulsarTabPalette.shadowColor.opacity(0.02),
                    radius: GymExercisePickerMetrics.surfaceShadowRadius,
                    y: GymExercisePickerMetrics.surfaceShadowY
                )
                .glassEffect(.clear.interactive(), in: Circle())
        }
    }
}

private struct GymExercisePickerActionSurface: View {
    var systemImage: String
    var size: CGFloat
    var isSelected = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: max(17, size * 0.40), weight: .medium))
            .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
            .frame(width: size, height: size)
            .background(
                PulsarFitnessMonochromeDesign.primaryText.opacity(isSelected ? 0.08 : 0),
                in: Circle()
            )
            .gymExercisePickerSurface(
                cornerRadius: size / 2,
                isInteractive: true,
                shadowOpacity: isSelected ? 0.03 : 0.02
            )
            .accessibilityHidden(true)
    }
}

private struct GymExercisePickerPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
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
                            .pulsarTextStyle(.captionEmphasis)
                            .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
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
                    .pulsarTextStyle(.label)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create & Add") {
                        createExercise()
                    }
                    .pulsarTextStyle(.label)
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
                            .pulsarTextStyle(.label)
                        Text("Optional, saved only for this custom exercise.")
                            .pulsarTextStyle(.captionEmphasis)
                            .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                    }
                    .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
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
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)

            TextField("Exercise name", text: $exerciseName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($isNameFocused)
                .submitLabel(.done)
                .pulsarTextStyle(.cardTitle)
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
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
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)

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
                        .pulsarTextStyle(.cardTitle)
                        .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.up.chevron.down")
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
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
                .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)

            Text(title)
                .pulsarTextStyle(.cardTitle)
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)

            Text(message)
                .pulsarTextStyle(.label)
                .multilineTextAlignment(.center)
                .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
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

    @ScaledMetric(relativeTo: .headline) private var controlHeight = GymExercisePickerMetrics.continueControlHeight
    @ScaledMetric(relativeTo: .headline) private var badgeSize = GymExercisePickerMetrics.continueBadgeSize
    @ScaledMetric(relativeTo: .headline) private var contentSpacing = GymExercisePickerMetrics.continueContentSpacing

    var body: some View {
        Button(action: action) {
            HStack(spacing: contentSpacing) {
                Text(title)
                    .pulsarTextStyle(.buttonTitle)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                GymContinueCountBadge(count: count, size: badgeSize)

                Image(systemName: "arrow.right")
                    .pulsarTextStyle(.buttonTitle)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: controlHeight)
            .contentShape(Capsule())
            .modifier(GymContinueButtonGlassModifier())
        }
        .buttonStyle(PulsarGymPressButtonStyle())
        .accessibilityLabel(title)
        .accessibilityValue("^[\(count) exercise](inflect: true) selected")
    }
}

private struct GymContinueCountBadge: View {
    var count: Int
    var size: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Text("\(count)")
            .pulsarTextStyle(.label)
            .monospacedDigit()
            .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(PulsarTabPalette.cardBackground.opacity(reduceTransparency ? 0.96 : 0.58))
            }
            .overlay {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(reduceTransparency ? 0.55 : 0.94),
                                .white.opacity(0.42),
                                Color.black.opacity(reduceTransparency ? 0.08 : 0.045)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.7
                    )
                    .allowsHitTesting(false)
            }
            .shadow(
                color: PulsarTabPalette.shadowColor.opacity(reduceTransparency ? 0.02 : 0.016),
                radius: 6,
                y: 2
            )
            .pulsarLiquidGlass(cornerRadius: size / 2, isClear: true)
            .accessibilityHidden(true)
    }
}

private struct GymContinueButtonGlassModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = Capsule(style: .continuous)

        if reduceTransparency {
            content
                .background(PulsarTabPalette.cardBackground, in: shape)
                .overlay {
                    shape
                        .strokeBorder(Color.black.opacity(0.10), lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .shadow(
                    color: PulsarTabPalette.shadowColor.opacity(0.04),
                    radius: 16,
                    y: 6
                )
        } else {
            content
                .background {
                    shape
                        .fill(PulsarTabPalette.cardBackground.opacity(0.46))
                        .overlay {
                            shape.fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.38),
                                        .white.opacity(0.06),
                                        .clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                        }
                }
                .overlay {
                    shape
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.94),
                                    .white.opacity(0.36),
                                    Color.black.opacity(0.055)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.7
                        )
                        .allowsHitTesting(false)
                }
                .shadow(
                    color: PulsarTabPalette.shadowColor.opacity(0.045),
                    radius: 18,
                    y: 8
                )
                .glassEffect(.clear.interactive(), in: .capsule)
        }
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
    @State private var instructionExercise: PulsarExercise?
    @State private var supersetPickerExercise: PulsarRoutineExercise?
    @State private var supersetEditorContext: GymSupersetEditorContext?
    @State private var planningViewport = CGRect.zero
    @FocusState private var focusedPlanningField: GymPlanningInputField?

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    routineNameSection
                    planningSection(scrollProxy: scrollProxy)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, focusedPlanningField == nil ? 126 : 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .premiumScrollHeaderBlur(height: 52)
            .coordinateSpace(name: GymRoutinePlanningCoordinateSpace.name)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { planningViewport = proxy.frame(in: .named(GymRoutinePlanningCoordinateSpace.name)) }
                        .onChange(of: proxy.size) { _, _ in
                            planningViewport = proxy.frame(in: .named(GymRoutinePlanningCoordinateSpace.name))
                        }
                }
            }
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
        .sheet(item: $instructionExercise) { exercise in
            GymExerciseCatalogDetailSheet(exercise: exercise)
                .environment(\.colorScheme, .light)
                .pulsarFitnessMonochromeAppearance()
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
    }

    private var routineNameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Routine Identity")
                .pulsarTextStyle(.cardTitle)
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)

            PulsarGlassCard(cornerRadius: 26, contentPadding: 14, tint: PulsarFitnessMonochromeDesign.primaryText.opacity(0.06)) {
                HStack(spacing: 12) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    isShowingEmojiPicker = true
                } label: {
                    Text(viewModel.resolvedRoutineEmoji)
                        .font(.system(size: 28))
                        .frame(width: 58, height: 58)
                        .background(PulsarCircularGlassSurface(cornerRadius: 29, tint: PulsarFitnessMonochromeDesign.primaryText))
                }
                .buttonStyle(PulsarGymPressButtonStyle())
                .accessibilityLabel("Choose routine icon")

                TextField("Gym Routine", text: $viewModel.routineName)
                    .pulsarTextStyle(.sectionHeader)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .padding(16)
                    .pulsarLiquidGlass(cornerRadius: 20, tint: PulsarFitnessMonochromeDesign.primaryText.opacity(0.055), interactive: true, isClear: true)
                }
            }
        }
    }

    private func planningSection(scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Planning")
                    .pulsarTextStyle(.cardTitle)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)

                Text("\(viewModel.routineExercises.count)")
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .pulsarLiquidGlass(cornerRadius: 12, tint: PulsarFitnessMonochromeDesign.primaryText.opacity(0.08), isClear: true)

                Spacer(minLength: 0)
            }

            PulsarGlassEffectGroup(spacing: 12) {
                GymRoutinePlanningReorderView(
                    exercises: viewModel.routineExercises.sorted { $0.order < $1.order },
                    supersetBlockIDs: { routineExerciseID in
                        Set(viewModel.supersetGroup(containing: routineExerciseID)?.exerciseIds ?? [routineExerciseID])
                    },
                    visibleBounds: planningVisibleBounds,
                    move: { routineExerciseID, destinationIndex in
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            viewModel.moveRoutineExercise(id: routineExerciseID, to: destinationIndex)
                        }
                    },
                    onDragBegan: {
                        focusedPlanningField = nil
                    },
                    onAutoscroll: { routineExerciseID, anchor in
                        withAnimation(.linear(duration: 0.16)) {
                            scrollProxy.scrollTo(routineExerciseID, anchor: anchor)
                        }
                    }
                ) { routineExercise, reorderGesture, isReordering in
                        let supersetGroup = viewModel.supersetGroup(containing: routineExercise.id)
                        GymRoutineExercisePlanningCard(
                            routineExercise: routineExercise,
                            viewModel: viewModel,
                            focusedField: $focusedPlanningField,
                            supersetGroup: supersetGroup,
                            supersetBadge: viewModel.supersetBadge(for: routineExercise),
                            isExpanded: isExpanded(routineExercise),
                            canCollapse: viewModel.routineExercises.count > 1,
                            isReordering: isReordering,
                            reorderGesture: reorderGesture,
                            onToggleExpanded: {
                                toggleExpanded(routineExercise)
                            },
                            onShowInstructions: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                instructionExercise = routineExercise.exercise
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
                            },
                            onMoveUp: {
                                moveForAccessibility(routineExercise.id, direction: .up)
                            },
                            onMoveDown: {
                                moveForAccessibility(routineExercise.id, direction: .down)
                            }
                        )
                }
            }
        }
    }

    private var planningVisibleBounds: CGRect {
        guard planningViewport != .zero else { return .zero }
        let actionBarHeight: CGFloat = focusedPlanningField == nil ? 112 : 12
        return CGRect(
            x: planningViewport.minX,
            y: planningViewport.minY,
            width: planningViewport.width,
            height: max(0, planningViewport.height - actionBarHeight)
        )
    }

    private func moveForAccessibility(
        _ routineExerciseID: UUID,
        direction: GymRoutineAccessibilityMoveDirection
    ) {
        let moved: Bool
        switch direction {
        case .up:
            moved = viewModel.moveRoutineExerciseUp(id: routineExerciseID)
        case .down:
            moved = viewModel.moveRoutineExerciseDown(id: routineExerciseID)
        }
        guard moved,
              let exercise = viewModel.routineExercises.first(where: { $0.id == routineExerciseID }) else { return }
        let label: String
        if let groupID = exercise.supersetGroupId {
            label = "\(viewModel.supersetLabel(for: groupID)) group"
        } else {
            label = exercise.exerciseName
        }
        UIAccessibility.post(
            notification: .announcement,
            argument: "\(label) moved to position \(exercise.order + 1)."
        )
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
        PulsarGlassCard(cornerRadius: 30, contentPadding: 10, tint: PulsarFitnessMonochromeDesign.primaryText.opacity(0.07)) {
            HStack(spacing: 10) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    _ = viewModel.save(using: routineStore)
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        didSave = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: didSave ? "checkmark" : "tray.and.arrow.down.fill")
                        Text(didSave ? "Saved" : "Save Routine")
                    }
                    .pulsarTextStyle(.label)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.roundedRectangle(radius: 24))
                .disabled(!viewModel.canContinue)

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    let routine = viewModel.save(using: routineStore)
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        didSave = true
                    }
                    onStartWorkout(routine)
                } label: {
                    HStack(spacing: 8) {
                        Text("Start Workout")
                        Image(systemName: "arrow.right")
                    }
                    .pulsarTextStyle(.label)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                }
                .pulsarGlassProminent(tint: PulsarFitnessMonochromeDesign.primaryText.opacity(0.62), cornerRadius: 24)
                .disabled(!viewModel.canContinue)
            }
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
    var isReordering: Bool
    var reorderGesture: AnyGesture<Void>
    var onToggleExpanded: () -> Void
    var onShowInstructions: () -> Void
    var onCreateSuperset: () -> Void
    var onEditSuperset: () -> Void
    var onRemove: () -> Void
    var onEdit: () -> Void
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void

    var body: some View {
        PulsarGlassCard(cornerRadius: 24, contentPadding: 14, tint: cardTint) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Button(action: onShowInstructions) {
                        ZStack(alignment: .topLeading) {
                            GymExerciseThumbnailView(
                                thumbnailURL: routineExercise.exercise.thumbnailURL,
                                muscleGroup: routineExercise.exercise.primaryMuscleGroup,
                                size: 64
                            )
                            .pulsarLiquidGlass(cornerRadius: 18, tint: PulsarFitnessMonochromeDesign.primaryText.opacity(0.08), interactive: true, isClear: true)

                            Text("\(routineExercise.order + 1)")
                                .pulsarTextStyle(.captionEmphasis)
                                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                                .frame(width: 24, height: 24)
                                .background(.white.opacity(0.94), in: Circle())
                                .offset(x: -4, y: -4)
                        }
                        .frame(width: 68, height: 68)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View instructions for \(routineExercise.exerciseName)")
                    .accessibilityHint("Opens exercise media and form instructions.")

                    Button(action: {
                        if canCollapse && !isReordering {
                            onToggleExpanded()
                        }
                    }) {
                        VStack(alignment: .leading, spacing: 6) {
                    if let supersetBadge {
                        Text(supersetBadge)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .pulsarLiquidGlass(cornerRadius: 10, tint: PulsarFitnessMonochromeDesign.primaryText.opacity(0.12), isClear: true)
                    }

                    Text(routineExercise.exerciseName)
                        .pulsarTextStyle(.sectionHeader)
                        .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.86)

                    Text(routineExercise.planSummary)
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                        .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(reorderGesture)
                    .accessibilityHint(reorderAccessibilityHint)
                    .accessibilityAction(named: "Move up", onMoveUp)
                    .accessibilityAction(named: "Move down", onMoveDown)

                    Spacer(minLength: 4)

                    HStack(spacing: 8) {
                        planningIconButton(
                            title: supersetGroup == nil ? "Create superset" : "Edit superset",
                            systemName: supersetGroup == nil ? "link.badge.plus" : "link",
                            tint: supersetGroup == nil ? .white.opacity(0.76) : PulsarFitnessMonochromeDesign.primaryText,
                            action: supersetGroup == nil ? onCreateSuperset : onEditSuperset
                        )
                        .disabled(supersetGroup == nil && viewModel.routineExercises.count < 2)

                        planningIconButton(
                            title: "Remove \(routineExercise.exerciseName)",
                            systemName: "minus",
                            tint: PulsarFitnessMonochromeDesign.primaryText,
                            action: onRemove
                        )

                        if canCollapse {
                            planningIconButton(
                                title: isExpanded ? "Collapse exercise plan" : "Expand exercise plan",
                                systemName: "chevron.down",
                                tint: .white.opacity(0.72),
                                action: onToggleExpanded
                            )
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        }
                    }
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
                            .pulsarTextStyle(.captionEmphasis)
                            .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)

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
                            .pulsarTextStyle(.captionEmphasis)
                            .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)

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
                        .pulsarTextStyle(.label)
                        .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                        .lineLimit(2...4)
                        .textInputAutocapitalization(.sentences)
                        .padding(13)
                        .pulsarLiquidGlass(cornerRadius: 18, tint: PulsarFitnessMonochromeDesign.primaryText.opacity(0.045), interactive: true, isClear: true)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        }
    }

    private func planningIconButton(title: String, systemName: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .labelStyle(.iconOnly)
                .pulsarTextStyle(.label)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(PulsarCircularGlassSurface(cornerRadius: 18, tint: tint, opacity: 0.88))
        }
        .buttonStyle(.plain)
    }

    private func restPresetTitle(_ seconds: Int) -> String {
        if seconds >= 60, seconds.isMultiple(of: 60) {
            return "Rest \(seconds / 60) min"
        }
        return "Rest \(seconds)s"
    }

    private var cardTint: Color? {
        if supersetGroup != nil {
            return PulsarFitnessMonochromeDesign.primaryText.opacity(isExpanded ? 0.14 : 0.10)
        }
        return PulsarFitnessMonochromeDesign.primaryText.opacity(isExpanded ? 0.08 : 0.04)
    }

    private var reorderAccessibilityHint: String {
        if supersetGroup == nil {
            return "Long press and drag to reorder. Use Move up or Move down to reorder with VoiceOver."
        }
        return "Long press and drag to move this linked group. Use Move up or Move down to move the entire group with VoiceOver."
    }
}

fileprivate enum GymPlanningInputField: Hashable {
    case sets(UUID)
    case reps(UUID)
    case weight(UUID)
    case rest(UUID)
}

private enum GymRoutineAccessibilityMoveDirection {
    case up
    case down
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
                            .pulsarTextStyle(.captionEmphasis)
                            .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)

                        VStack(spacing: 9) {
                            ForEach(candidates) { candidate in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    selectedPartnerID = candidate.id
                                } label: {
                                    HStack(spacing: 11) {
                                        Image(systemName: selectedPartnerID == candidate.id ? "checkmark.circle.fill" : "circle")
                                            .pulsarTextStyle(.cardTitle)
                                            .symbolRenderingMode(.hierarchical)
                                            .foregroundStyle(selectedPartnerID == candidate.id ? PulsarFitnessMonochromeDesign.primaryText  : PulsarFitnessMonochromeDesign.secondaryText)

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(candidate.exerciseName)
                                                .pulsarTextStyle(.label)
                                                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                                                .lineLimit(2)
                                            Text(candidate.primaryMuscleGroup.displayName)
                                                .pulsarTextStyle(.captionEmphasis)
                                                .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
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
                            .pulsarTextStyle(.cardTitle)
                            .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(
                                LinearGradient(
                                    colors: [.white.opacity(0.98), PulsarFitnessMonochromeDesign.primaryText],
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
        .pulsarFitnessMonochromeAppearance()
    }

    private func sheetHeader(title: String, subtitle: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .pulsarTextStyle(.title)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                Text(subtitle)
                    .pulsarTextStyle(.label)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Button("Done") {
                dismiss()
            }
            .pulsarTextStyle(.label)
            .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
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
                            .pulsarTextStyle(.title)
                            .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                        Text(exercises.map(\.exerciseName).joined(separator: " + "))
                            .pulsarTextStyle(.label)
                            .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 12)

                    Button("Done") {
                        dismiss()
                    }
                    .pulsarTextStyle(.label)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
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
                            .pulsarTextStyle(.label)
                            .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
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
                            .pulsarTextStyle(.label)
                            .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(PulsarFitnessMonochromeDesign.primaryText.opacity(0.11), in: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }
            .padding(22)
        }
        .pulsarFitnessMonochromeAppearance()
    }
}

private struct GymSupersetRestSelector: View {
    @Binding var restSeconds: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Superset rest")
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)

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
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                Text(value)
                    .pulsarTextStyle(.sectionHeader)
                    .monospacedDigit()
                    .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button(action: onMinus) {
                    Image(systemName: "minus")
                        .pulsarTextStyle(.label)
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.08), in: Circle())
                }

                Button(action: onPlus) {
                    Image(systemName: "plus")
                        .pulsarTextStyle(.label)
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.12), in: Circle())
                }
            }
            .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
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
        PulsarFitnessMonochromeBackground()
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
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                TextField(title, value: $value, format: .number)
                    .keyboardType(.numberPad)
                    .focused(focusedField, equals: focus)
                    .pulsarTextStyle(.cardTitle)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                    .multilineTextAlignment(.leading)

                if !unit.isEmpty {
                    Text(unit)
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .pulsarLiquidGlass(cornerRadius: 18, tint: PulsarFitnessMonochromeDesign.primaryText.opacity(0.045), interactive: true, isClear: true)
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
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                TextField(title, value: $value, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad)
                    .focused(focusedField, equals: focus)
                    .pulsarTextStyle(.cardTitle)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                    .multilineTextAlignment(.leading)

                Text(unit)
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .pulsarLiquidGlass(cornerRadius: 18, tint: PulsarFitnessMonochromeDesign.primaryText.opacity(0.045), interactive: true, isClear: true)
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
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(isSelected ? PulsarFitnessMonochromeDesign.primaryText  : PulsarFitnessMonochromeDesign.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selectedFill, in: Capsule(style: .continuous))
                .pulsarLiquidGlass(cornerRadius: 18, tint: PulsarFitnessMonochromeDesign.primaryText.opacity(isSelected ? 0.18 : 0.04), interactive: true, isClear: !isSelected)
        }
        .buttonStyle(.plain)
    }

    private var selectedFill: Color {
        isSelected ? .white.opacity(0.72) : .white.opacity(0.035)
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
                                .pulsarTextStyle(.title)
                                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                            Text("Choose an emoji that makes this plan instantly recognizable.")
                                .pulsarTextStyle(.label)
                                .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 12)
                        Button("Done") {
                            isCustomEmojiFocused = false
                            dismiss()
                        }
                        .pulsarTextStyle(.label)
                        .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
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
                            .pulsarTextStyle(.cardTitle)
                            .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
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
                        .pulsarTextStyle(.label)
                        .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
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
        PulsarFitnessMonochromeBackground()
    }
}

#Preview {
    GymRoutineBuilderFlowView(
        routineStore: PulsarRoutineStore(defaults: .standard),
        onCancel: {},
        onStartWorkout: { _ in }
    )
}

#Preview("Choose Exercises - Small", traits: .fixedLayout(width: 375, height: 812)) {
    GymRoutineBuilderFlowView(
        routineStore: PulsarRoutineStore(defaults: .standard),
        onCancel: {},
        onStartWorkout: { _ in }
    )
}

#Preview("Choose Exercises - Pro Max", traits: .fixedLayout(width: 430, height: 932)) {
    GymRoutineBuilderFlowView(
        routineStore: PulsarRoutineStore(defaults: .standard),
        onCancel: {},
        onStartWorkout: { _ in }
    )
}

#Preview("Continue Button - Small", traits: .fixedLayout(width: 375, height: 240)) {
    GymContinueButtonPreview(count: 1)
}

#Preview("Continue Button - Pro Max", traits: .fixedLayout(width: 430, height: 240)) {
    GymContinueButtonPreview(count: 12)
}

#Preview("Continue Button - Accessibility", traits: .fixedLayout(width: 390, height: 280)) {
    GymContinueButtonPreview(count: 1)
        .environment(\.dynamicTypeSize, .accessibility2)
}

private struct GymContinueButtonPreview: View {
    var count: Int

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 23, style: .continuous)
                        .fill(Color.white)
                        .frame(height: 96)
                        .overlay(alignment: .leading) {
                            Text(index == 0 ? "Archer Push Up" : "Assisted Seated Pectoralis Major Stretch")
                                .pulsarTextStyle(.cardTitle)
                                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                                .padding(.horizontal, 20)
                                .lineLimit(1)
                        }
                }
            }
            .padding(.horizontal, 20)

            GymContinueButton(title: "Continue", count: count, action: {})
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .background(PulsarFitnessMonochromeBackground())
        .pulsarFitnessMonochromeAppearance()
    }
}
