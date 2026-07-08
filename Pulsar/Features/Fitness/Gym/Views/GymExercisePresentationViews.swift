//
//  GymExercisePresentationViews.swift
//  Pulsar
//

import SwiftUI
import UIKit
import WebKit

struct GymSetEditorSheet: View {
    var setNumber: Int
    var reps: Int
    var weight: Double
    var weightUnit: PulsarWeightUnit
    var onSave: (Int, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftReps: Int
    @State private var draftWeight: Double

    init(
        setNumber: Int,
        reps: Int,
        weight: Double,
        weightUnit: PulsarWeightUnit,
        onSave: @escaping (Int, Double) -> Void
    ) {
        self.setNumber = setNumber
        self.reps = reps
        self.weight = weight
        self.weightUnit = weightUnit
        self.onSave = onSave
        _draftReps = State(initialValue: reps)
        _draftWeight = State(initialValue: weight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Set \(setNumber)")
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(.white.opacity(0.54))
                    .textCase(.uppercase)

                Text("Adjust performance")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 12) {
                GymSetEditorStepper(
                    title: "Reps",
                    value: "\(draftReps)",
                    onMinus: { draftReps = max(1, draftReps - 1) },
                    onPlus: { draftReps = min(200, draftReps + 1) }
                )

                GymSetEditorStepper(
                    title: "Weight",
                    value: "\(draftWeight.formattedGymDecimal) \(weightUnit.displayName)",
                    onMinus: { draftWeight = max(0, draftWeight - weightStep) },
                    onPlus: { draftWeight += weightStep }
                )
            }

            Button {
                onSave(draftReps, draftWeight)
                dismiss()
            } label: {
                Text("Save Set Values")
                    .pulsarTextStyle(.cardTitle)
                    .foregroundStyle(Color(red: 0.14, green: 0.09, blue: 0.22))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        LinearGradient(
                            colors: [.white.opacity(0.98), Color(red: 0.74, green: 1.0, blue: 0.78)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Capsule(style: .continuous)
                    )
            }
            .buttonStyle(PulsarGymPressButtonStyle())
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(GymGlassBackground().ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var weightStep: Double {
        weightUnit == .pounds ? 5 : 2.5
    }
}

private struct GymSetEditorStepper: View {
    var title: String
    var value: String
    var onMinus: () -> Void
    var onPlus: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(.white.opacity(0.54))
                Text(value)
                    .pulsarTextStyle(.sectionHeader)
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button(action: onMinus) {
                    Image(systemName: "minus")
                        .pulsarTextStyle(.label)
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .accessibilityLabel("Decrease \(title.lowercased())")

                Button(action: onPlus) {
                    Image(systemName: "plus")
                        .pulsarTextStyle(.label)
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .accessibilityLabel("Increase \(title.lowercased())")
            }
            .foregroundStyle(.white.opacity(0.88))
            .buttonStyle(.plain)
        }
        .padding(14)
        .pulsarLiquidGlass(cornerRadius: 20)
    }
}

struct GymExerciseThumbnailView: View {
    var thumbnailURL: String?
    var muscleGroup: PulsarMuscleGroup
    var size: CGFloat = 52
    var isCompleted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: max(12, size * 0.28), style: .continuous)
                .fill(background)

            if let url = ExerciseDatasetMediaResolver.url(for: thumbnailURL) {
                resolvedImage(url)
            } else {
                fallbackIcon
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(12, size * 0.28), style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: max(12, size * 0.28), style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func resolvedImage(_ url: URL) -> some View {
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
    }

    private var fallbackIcon: some View {
        Image(systemName: isCompleted ? "checkmark" : symbolName)
            .font(.system(size: max(18, size * 0.42), weight: .semibold, design: .rounded))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isCompleted ? Color(red: 0.72, green: 1.0, blue: 0.78) : .white.opacity(0.76))
    }

    private var symbolName: String {
        switch muscleGroup {
        case .cardioConditioning:
            return "figure.run"
        case .absCore:
            return "figure.core.training"
        case .quadriceps, .hamstrings, .calves, .glutes, .adductors, .abductors:
            return "figure.strengthtraining.functional"
        default:
            return "figure.strengthtraining.traditional"
        }
    }

    private var background: LinearGradient {
        LinearGradient(
            colors: isCompleted
                ? [Color(red: 0.66, green: 1.0, blue: 0.78).opacity(0.22), .white.opacity(0.07)]
                : [Color(red: 0.78, green: 0.72, blue: 1.0).opacity(0.18), .white.opacity(0.07)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct GymExerciseCatalogDetailSheet: View {
    var exercise: PulsarExercise
    @Environment(\.dismiss) private var dismiss

    private var instructionSteps: [String] {
        exercise.instructions?
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                mediaPreview
                metadataGrid
                instructionsSection
                attribution
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 30)
        }
        .background(GymGlassBackground().ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            GymExerciseThumbnailView(
                thumbnailURL: exercise.thumbnailURL,
                muscleGroup: exercise.primaryMuscleGroup,
                size: 64
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(exercise.name)
                    .pulsarTextStyle(.title)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(exercise.primaryMuscleSummary)
                    .pulsarTextStyle(.label)
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .pulsarTextStyle(.label)
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(width: 34, height: 34)
                    .background(PulsarCircularGlassSurface(cornerRadius: 17, opacity: 0.82))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close exercise details")
        }
    }

    @ViewBuilder
    private var mediaPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.white.opacity(0.08))

            if let animationURL = ExerciseDatasetMediaResolver.url(for: exercise.animationURL) {
                GymExerciseWebMediaView(url: animationURL)
            } else if let thumbnailURL = ExerciseDatasetMediaResolver.url(for: exercise.thumbnailURL) {
                GymExerciseResolvedImage(url: thumbnailURL)
            } else {
                GymExerciseMediaFallback()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 270)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .pulsarLiquidGlass(cornerRadius: 24, tint: Color(red: 0.78, green: 0.72, blue: 1.0).opacity(0.08), isClear: true)
    }

    private var metadataGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            GymExerciseDetailMetric(title: "Target", value: exercise.primaryMuscleGroup.displayName, symbolName: "scope")
            GymExerciseDetailMetric(title: "Equipment", value: exercise.equipmentSummary, symbolName: "dumbbell.fill")
            if let category = exercise.category {
                GymExerciseDetailMetric(title: "Category", value: category, symbolName: "square.grid.2x2")
            }
            if exercise.animationURL != nil {
                GymExerciseDetailMetric(title: "Media", value: "GIF", symbolName: "play.rectangle.fill")
            }
        }
    }

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Instructions")
                .pulsarTextStyle(.cardTitle)
                .foregroundStyle(.white)

            if instructionSteps.isEmpty {
                Text("No form instructions saved for this exercise.")
                    .pulsarTextStyle(.label)
                    .foregroundStyle(.white.opacity(0.70))
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .pulsarLiquidGlass(cornerRadius: 18, tint: Color(red: 0.78, green: 0.72, blue: 1.0).opacity(0.06), isClear: true)
            } else {
                PulsarGlassEffectGroup(spacing: 10) {
                    VStack(spacing: 10) {
                        ForEach(Array(instructionSteps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 11) {
                                Text("\(index + 1)")
                                    .pulsarTextStyle(.captionEmphasis)
                                    .foregroundStyle(Color(red: 0.14, green: 0.09, blue: 0.22))
                                    .frame(width: 24, height: 24)
                                    .background(.white.opacity(0.92), in: Circle())

                                Text(step)
                                    .pulsarTextStyle(.label)
                                    .foregroundStyle(.white.opacity(0.78))
                                    .fixedSize(horizontal: false, vertical: true)

                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .pulsarLiquidGlass(cornerRadius: 18, tint: Color(red: 0.78, green: 0.72, blue: 1.0).opacity(0.055), isClear: true)
                        }
                    }
                }
            }
        }
    }

    private var attribution: some View {
        Text("Source: \(exercise.attribution.sourceName)")
            .pulsarTextStyle(.captionEmphasis)
            .foregroundStyle(.white.opacity(0.48))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GymExerciseDetailMetric: View {
    var title: String
    var value: String
    var symbolName: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .pulsarTextStyle(.label)
                .foregroundStyle(Color(red: 0.78, green: 0.72, blue: 1.0))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(.white.opacity(0.52))
                Text(value)
                    .pulsarTextStyle(.label)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .pulsarLiquidGlass(cornerRadius: 18, tint: Color(red: 0.78, green: 0.72, blue: 1.0).opacity(0.045), isClear: true)
    }
}

private struct GymExerciseResolvedImage: View {
    var url: URL

    var body: some View {
        if url.isFileURL {
            if let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                GymExerciseMediaFallback()
            }
        } else {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    GymExerciseMediaFallback()
                case .empty:
                    ProgressView()
                        .tint(.white.opacity(0.72))
                @unknown default:
                    GymExerciseMediaFallback()
                }
            }
        }
    }
}

private struct GymExerciseMediaFallback: View {
    var body: some View {
        Image(systemName: "figure.strengthtraining.traditional")
            .pulsarTextStyle(.title)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.white.opacity(0.70))
    }
}

private struct GymExerciseWebMediaView: UIViewRepresentable {
    var url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url

        if url.isFileURL {
            webView.loadHTMLString(html(src: url.lastPathComponent), baseURL: url.deletingLastPathComponent())
        } else {
            webView.loadHTMLString(html(src: url.absoluteString), baseURL: nil)
        }
    }

    private func html(src: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="initial-scale=1, maximum-scale=1">
        <style>
        html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; background: transparent; }
        img { width: 100%; height: 100%; object-fit: cover; display: block; }
        </style>
        </head>
        <body><img src="\(escapedHTMLAttribute(src))"></body>
        </html>
        """
    }

    private func escapedHTMLAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    final class Coordinator {
        var loadedURL: URL?
    }
}

struct GymSessionExerciseDetailSheet: View {
    var exercise: PulsarGymWorkoutExerciseSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    GymExerciseThumbnailView(
                        thumbnailURL: exercise.thumbnailURL,
                        muscleGroup: exercise.primaryMuscleGroup,
                        size: 64,
                        isCompleted: exercise.isCompleted
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text(exercise.exerciseName)
                            .pulsarTextStyle(.title)
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(exercise.primaryMuscleGroup.displayName)
                            .pulsarTextStyle(.label)
                            .foregroundStyle(.white.opacity(0.62))
                    }

                    Spacer(minLength: 8)

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .pulsarTextStyle(.label)
                            .foregroundStyle(.white.opacity(0.78))
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.09), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close exercise details")
                }

                GymExerciseMetadataRow(
                    muscleGroup: exercise.primaryMuscleGroup,
                    equipment: exercise.equipment
                )

                if let instructionsPreview = exercise.instructionsPreview {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Form Cues", systemImage: "list.clipboard.fill")
                            .pulsarTextStyle(.cardTitle)
                            .foregroundStyle(.white)

                        Text(instructionsPreview)
                            .pulsarTextStyle(.label)
                            .foregroundStyle(.white.opacity(0.76))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(13)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                } else {
                    Label("No form instructions saved for this exercise.", systemImage: "info.circle")
                        .pulsarTextStyle(.label)
                        .foregroundStyle(.white.opacity(0.62))
                        .padding(13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 30)
        }
        .background(GymGlassBackground().ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct GymExerciseMetadataRow: View {
    var muscleGroup: PulsarMuscleGroup
    var equipment: String

    var body: some View {
        HStack(spacing: 8) {
            metadataChip(muscleGroup.displayName, systemImage: "scope")
            metadataChip(equipment, systemImage: "dumbbell.fill")
        }
    }

    private func metadataChip(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .pulsarTextStyle(.captionEmphasis)
            .foregroundStyle(.white.opacity(0.74))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.white.opacity(0.075), in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            }
    }
}

struct CompletedWorkoutExerciseInstructionsSheet: View {
    var exercise: CompletedWorkoutExercisePresentation

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header

                GymExerciseMetadataRow(
                    muscleGroup: exercise.primaryMuscleGroup,
                    equipment: exercise.equipment
                )

                instructionsPanel
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 30)
        }
        .background(GymGlassBackground().ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            GymExerciseThumbnailView(
                thumbnailURL: exercise.thumbnailURL,
                muscleGroup: exercise.primaryMuscleGroup,
                size: 64
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(exercise.exerciseName)
                    .pulsarTextStyle(.title)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Form instructions")
                    .pulsarTextStyle(.label)
                    .foregroundStyle(.white.opacity(0.62))
            }

            Spacer(minLength: 8)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .pulsarTextStyle(.label)
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.09), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close instructions")
        }
    }

    private var instructionsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Instructions", systemImage: "list.clipboard.fill")
                .pulsarTextStyle(.cardTitle)
                .foregroundStyle(.white)

            Text(exercise.instructionsFull ?? exercise.instructionsPreview ?? "No form instructions saved for this exercise.")
                .pulsarTextStyle(.label)
                .foregroundStyle(.white.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(FitnessGlassSurfaceModifier(cornerRadius: 20, tint: accent, borderOpacity: 0.60))
    }

    private var accent: Color {
        ExerciseProgressService.primaryMatrixGroup(for: exercise.primaryMuscleGroup)?.accent
            ?? Color(red: 0.78, green: 0.62, blue: 1.0)
    }
}

struct ExercisePreviousWeightsSheet: View {
    var exercise: PulsarGymWorkoutExerciseSession
    var history: ExerciseProgressHistory
    var recentSessions: [ExerciseRecentSessionSummary]
    var onOpenFullHistory: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                summaryGrid

                if recentSessions.isEmpty {
                    emptyState
                } else {
                    recentSessionsList
                }

                Button {
                    dismiss()
                    onOpenFullHistory()
                } label: {
                    Label("Open Full Progress", systemImage: "chart.line.uptrend.xyaxis")
                        .pulsarTextStyle(.cardTitle)
                        .foregroundStyle(Color(red: 0.14, green: 0.09, blue: 0.22))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.white.opacity(0.94), in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 30)
        }
        .background(GymGlassBackground().ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            GymExerciseThumbnailView(
                thumbnailURL: exercise.thumbnailURL,
                muscleGroup: exercise.primaryMuscleGroup,
                size: 52,
                isCompleted: exercise.isCompleted
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("Previous Weights")
                    .pulsarTextStyle(.title)
                    .foregroundStyle(.white)

                Text(exercise.exerciseName)
                    .pulsarTextStyle(.label)
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(2)
            }

            Spacer(minLength: 8)
        }
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            previousMetric(
                title: history.isBodyweight ? "Last reps" : "Last weight",
                value: history.points.last.map { history.isBodyweight ? "\($0.totalReps)" : "\($0.maxWeight.formattedGymDecimal) \(history.displayUnit.displayName)" } ?? "--"
            )
            previousMetric(
                title: "Best set",
                value: history.lifetimeBestSet?.displayText(unit: history.displayUnit, isBodyweight: history.isBodyweight) ?? "--"
            )
            previousMetric(
                title: "Sessions",
                value: "\(history.totalTimesTrained)"
            )
            previousMetric(
                title: "Est. 1RM",
                value: history.lifetimeBestSet?.estimatedOneRepMax.map { "\($0.formattedGymDecimal) \(history.displayUnit.displayName)" } ?? "--"
            )
        }
    }

    private func previousMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .pulsarTextStyle(.cardTitle)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(title)
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(.white.opacity(0.54))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var emptyState: some View {
        Label("Complete this exercise once to build a weight history.", systemImage: "clock.arrow.circlepath")
            .pulsarTextStyle(.label)
            .foregroundStyle(.white.opacity(0.64))
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var recentSessionsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Recent Sessions", systemImage: "calendar")
                .pulsarTextStyle(.cardTitle)
                .foregroundStyle(.white)

            ForEach(recentSessions) { session in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(session.workoutName)
                            .pulsarTextStyle(.label)
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        Text(session.performedAt.formatted(.dateTime.month(.abbreviated).day()))
                            .pulsarTextStyle(.captionEmphasis)
                            .foregroundStyle(.white.opacity(0.52))
                    }

                    Text(session.sets.map { "\($0.reps)x\($0.weight.formattedGymDecimal)" }.joined(separator: " / "))
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(.white.opacity(0.70))
                        .lineLimit(2)

                    if let bestSet = session.bestSet {
                        Text("Best: \(bestSet.displayText(unit: history.displayUnit, isBodyweight: history.isBodyweight))")
                            .pulsarTextStyle(.captionEmphasis)
                            .foregroundStyle(Color(red: 0.72, green: 1.0, blue: 0.78))
                    }
                }
                .padding(12)
                .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }
}

struct GymCompletedExerciseCard: View {
    var exercise: PulsarGymCompletedExerciseSummary
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button {
            onTap?()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    GymExerciseThumbnailView(
                        thumbnailURL: exercise.thumbnailURL,
                        muscleGroup: exercise.primaryMuscleGroup,
                        size: 48
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text(exercise.exerciseName)
                            .pulsarTextStyle(.label)
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        GymExerciseMetadataRow(
                            muscleGroup: exercise.primaryMuscleGroup,
                            equipment: exercise.equipment
                        )
                    }

                    Spacer(minLength: 0)

                    if onTap != nil {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .pulsarTextStyle(.captionEmphasis)
                            .foregroundStyle(Color(red: 0.78, green: 0.72, blue: 1.0))
                            .frame(width: 30, height: 30)
                            .background(.white.opacity(0.075), in: Circle())
                    }
                }

                VStack(spacing: 7) {
                    ForEach(exercise.sets) { set in
                        HStack(spacing: 10) {
                            Text("Set \(set.setNumber)")
                                .pulsarTextStyle(.captionEmphasis)
                                .foregroundStyle(.white.opacity(0.56))
                                .frame(width: 50, alignment: .leading)

                            Text("\(set.reps) reps")
                                .pulsarTextStyle(.captionEmphasis)
                                .foregroundStyle(.white)

                            Spacer(minLength: 0)

                            Text("\(set.weight.formattedGymDecimal) \(exercise.weightUnit.displayName)")
                                .pulsarTextStyle(.captionEmphasis)
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.82))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.060), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }
}
