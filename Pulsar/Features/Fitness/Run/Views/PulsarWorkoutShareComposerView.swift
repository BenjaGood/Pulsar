//
//  PulsarWorkoutShareComposerView.swift
//  Pulsar
//

import PhotosUI
import SwiftUI
import UIKit

struct PulsarWorkoutShareComposerView: View {
    private var content: PulsarWorkoutShareContent

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var isShowingCamera = false
    @State private var isShowingShareSheet = false
    @State private var renderedImage: UIImage?

    init(summary: PulsarRunSummary) {
        content = .outdoor(summary)
    }

    init(gymSummary: PulsarGymWorkoutSummary) {
        content = .gym(gymSummary)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    PulsarWorkoutShareCard(content: content, photo: selectedImage)
                        .aspectRatio(4 / 5, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                        .shadow(color: .black.opacity(0.24), radius: 22, y: 14)

                    HStack(spacing: 12) {
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Label("Photo", systemImage: "photo")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PulsarShareControlButtonStyle(tint: content.tint))

                        Button {
                            isShowingCamera = true
                        } label: {
                            Label("Camera", systemImage: "camera.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PulsarShareControlButtonStyle(tint: content.tint))
                        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                    }

                    Button {
                        renderShareImage()
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PulsarShareControlButtonStyle(tint: content.tint, isProminent: true))
                }
                .padding(18)
            }
            .background(PulsarSectionBackground())
            .navigationTitle("Share Workout")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: selectedPhotoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        selectedImage = image
                    }
                }
            }
            .sheet(isPresented: $isShowingCamera) {
                PulsarWorkoutCameraPicker(image: $selectedImage)
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $isShowingShareSheet) {
                if let renderedImage {
                    PulsarActivityView(activityItems: [renderedImage])
                }
            }
        }
    }

    @MainActor
    private func renderShareImage() {
        let card = PulsarWorkoutShareCard(content: content, photo: selectedImage)
            .frame(width: 1080, height: 1350)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        renderedImage = renderer.uiImage
        isShowingShareSheet = renderedImage != nil
    }
}

private enum PulsarWorkoutShareContent {
    case outdoor(PulsarRunSummary)
    case gym(PulsarGymWorkoutSummary)

    var title: String {
        switch self {
        case .outdoor(let summary):
            summary.workoutKind.outdoorTitle
        case .gym(let summary):
            summary.routineName
        }
    }

    var workoutLabel: String {
        switch self {
        case .outdoor(let summary):
            summary.workoutKind.displayName
        case .gym:
            "Strength"
        }
    }

    var symbolName: String {
        switch self {
        case .outdoor(let summary):
            summary.workoutKind.systemImageName
        case .gym:
            "dumbbell.fill"
        }
    }

    var tint: Color {
        switch self {
        case .outdoor(let summary):
            summary.workoutKind.accentColor
        case .gym:
            Color(red: 0.70, green: 1.0, blue: 0.76)
        }
    }

    var startedAt: Date {
        switch self {
        case .outdoor(let summary):
            summary.startedAt
        case .gym(let summary):
            summary.startedAt ?? summary.endedAt ?? Date()
        }
    }

    var sourceDeviceName: String {
        switch self {
        case .outdoor(let summary):
            summary.sourceDeviceName
        case .gym(let summary):
            summary.sourceDeviceName
        }
    }

    var primaryMetrics: [PulsarWorkoutShareMetric] {
        switch self {
        case .outdoor(let summary):
            var metrics = [
                PulsarWorkoutShareMetric(title: "Duration", value: PulsarRunFormatters.duration(summary.elapsedTime))
            ]
            if summary.workoutKind.isOutdoorDistanceWorkout || summary.distanceMeters > 10 || summary.route.count > 1 {
                metrics.append(PulsarWorkoutShareMetric(title: "Distance", value: PulsarRunFormatters.distance(summary.distanceMeters)))
                metrics.append(PulsarWorkoutShareMetric(title: PulsarRunFormatters.paceOrSpeedTitle(for: summary.workoutKind, average: true), value: PulsarRunFormatters.paceOrSpeed(workoutKind: summary.workoutKind, paceSecondsPerKilometer: summary.averagePaceSecondsPerKilometer, speedMetersPerSecond: summary.averageSpeedMetersPerSecond)))
            }
            if let activeEnergyKilocalories = summary.activeEnergyKilocalories {
                metrics.append(PulsarWorkoutShareMetric(title: "Calories", value: "\(Int(activeEnergyKilocalories.rounded())) kcal"))
            }
            if let averageHeartRate = summary.averageHeartRate {
                metrics.append(PulsarWorkoutShareMetric(title: "Avg HR", value: "\(Int(averageHeartRate.rounded())) bpm"))
            }
            return metrics
        case .gym(let summary):
            var metrics = [
                PulsarWorkoutShareMetric(title: "Duration", value: summary.durationSeconds.formattedGymDuration),
                PulsarWorkoutShareMetric(title: "Exercises", value: "\(summary.exercisesCompleted)/\(summary.totalExercises)"),
                PulsarWorkoutShareMetric(title: "Sets", value: "\(summary.setsCompleted)/\(summary.totalSets)")
            ]
            if summary.totalVolume > 0 {
                metrics.append(PulsarWorkoutShareMetric(title: "Volume", value: "\(summary.totalVolume.formattedGymDecimal) \(summary.weightUnit.displayName)"))
            }
            if let activeEnergyKilocalories = summary.activeEnergyKilocalories {
                metrics.append(PulsarWorkoutShareMetric(title: "Calories", value: "\(Int(activeEnergyKilocalories.rounded())) kcal"))
            }
            if let averageHeartRate = summary.averageHeartRate {
                metrics.append(PulsarWorkoutShareMetric(title: "Avg HR", value: "\(Int(averageHeartRate.rounded())) bpm"))
            }
            return metrics
        }
    }

    var routePoints: [CGPoint] {
        guard case .outdoor(let summary) = self else { return [] }
        let points = summary.gpsRoute.points
        guard let bounds = summary.gpsRoute.bounds,
              bounds.maximumLatitude > bounds.minimumLatitude,
              bounds.maximumLongitude > bounds.minimumLongitude else { return [] }
        return points.map { point in
            CGPoint(
                x: (point.longitude - bounds.minimumLongitude) / (bounds.maximumLongitude - bounds.minimumLongitude),
                y: 1 - ((point.latitude - bounds.minimumLatitude) / (bounds.maximumLatitude - bounds.minimumLatitude))
            )
        }
    }
}

private struct PulsarWorkoutShareMetric: Identifiable {
    let id = UUID()
    var title: String
    var value: String
}

private struct PulsarWorkoutShareCard: View {
    var content: PulsarWorkoutShareContent
    var photo: UIImage?

    var body: some View {
        ZStack {
            photoLayer

            LinearGradient(
                colors: [.black.opacity(0.12), .black.opacity(0.48)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading) {
                HStack {
                    Image("PulsarLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 46, height: 46)
                    Text("Pulsar")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                    Spacer()
                    Text(content.startedAt.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)

                Spacer()

                VStack(alignment: .leading, spacing: 18) {
                    Label(content.workoutLabel.uppercased(), systemImage: content.symbolName)
                        .font(.system(size: 19, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.74))

                    if content.routePoints.count > 1 {
                        RouteMiniLine(points: content.routePoints, tint: content.tint)
                            .frame(height: 120)
                    }

                    Text(content.title)
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.62)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(content.primaryMetrics) { metric in
                            shareMetric(metric.title, metric.value)
                        }
                    }

                    Label("\(content.startedAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())) · \(content.sourceDeviceName)", systemImage: "sparkles")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.82))
                }
                .padding(26)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(.white.opacity(0.22), lineWidth: 1)
                }
            }
            .padding(34)
        }
        .background(Color.black)
    }

    @ViewBuilder
    private var photoLayer: some View {
        if let photo {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
        } else {
            LinearGradient(
                colors: [
                    content.tint.opacity(0.82),
                    Color(red: 0.05, green: 0.07, blue: 0.09),
                    Color(red: 0.02, green: 0.03, blue: 0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if content.routePoints.count > 1 {
                RouteMiniLine(points: content.routePoints, tint: .white.opacity(0.25))
                    .padding(90)
            } else {
                Image(systemName: content.symbolName)
                    .font(.system(size: 260, weight: .black))
                    .foregroundStyle(.white.opacity(0.12))
            }
        }
    }

    private func shareMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.system(size: 34, weight: .black, design: .rounded))
                .minimumScaleFactor(0.72)
                .lineLimit(1)
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
        }
        .foregroundStyle(.white)
    }
}

private struct RouteMiniLine: View {
    var points: [CGPoint]
    var tint: Color

    var body: some View {
        Canvas { context, size in
            guard points.count > 1 else { return }
            var path = Path()
            let scaled = points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            path.move(to: scaled[0])
            for point in scaled.dropFirst() {
                path.addLine(to: point)
            }
            context.stroke(path, with: .color(tint), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
            if let first = scaled.first {
                context.fill(Path(ellipseIn: CGRect(x: first.x - 8, y: first.y - 8, width: 16, height: 16)), with: .color(.white))
            }
            if let last = scaled.last {
                context.fill(Path(ellipseIn: CGRect(x: last.x - 10, y: last.y - 10, width: 20, height: 20)), with: .color(tint))
            }
        }
    }
}

private struct PulsarShareControlButtonStyle: ButtonStyle {
    var tint: Color
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(isProminent ? .white : tint)
            .padding(.vertical, 15)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        isProminent
                            ? AnyShapeStyle(tint.gradient)
                            : AnyShapeStyle(LinearGradient(colors: [tint.opacity(0.14), tint.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct PulsarActivityView: UIViewControllerRepresentable {
    var activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct PulsarWorkoutCameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: PulsarWorkoutCameraPicker

        init(parent: PulsarWorkoutCameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
