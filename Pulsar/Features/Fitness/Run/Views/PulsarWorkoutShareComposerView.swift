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
        renderer.proposedSize = ProposedViewSize(width: 1080, height: 1350)
        renderer.scale = 1
        renderedImage = renderer.uiImage ?? PulsarWorkoutShareFallbackRenderer.image(for: content, size: CGSize(width: 1080, height: 1350))
        PulsarShareDebugLogger.log("Rendered workout share image title=\(content.title) routePoints=\(content.routePoints.count) hasPhoto=\(selectedImage != nil)")
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
            }
            if let activeEnergyKilocalories = summary.activeEnergyKilocalories {
                metrics.append(PulsarWorkoutShareMetric(title: "Calories", value: "\(Int(activeEnergyKilocalories.rounded())) kcal"))
            }
            if let averageHeartRate = summary.averageHeartRate {
                metrics.append(PulsarWorkoutShareMetric(title: "Avg HR", value: "\(Int(averageHeartRate.rounded())) bpm"))
            }
            if summary.workoutKind.isOutdoorDistanceWorkout || summary.distanceMeters > 10 || summary.route.count > 1 {
                metrics.append(PulsarWorkoutShareMetric(title: PulsarRunFormatters.paceOrSpeedTitle(for: summary.workoutKind, average: true), value: PulsarRunFormatters.paceOrSpeed(workoutKind: summary.workoutKind, paceSecondsPerKilometer: summary.averagePaceSecondsPerKilometer, speedMetersPerSecond: summary.averageSpeedMetersPerSecond)))
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
        return PulsarShareRouteProjection.normalizedPoints(from: summary.gpsRoute, inset: 0.09)
    }
}

enum PulsarShareRouteProjection {
    nonisolated static func normalizedPoints(from route: GPSWorkoutRoute, inset: CGFloat = 0.08) -> [CGPoint] {
        normalizedPoints(from: route.points, inset: inset)
    }

    nonisolated static func normalizedPoints(from points: [GPSRoutePoint], inset: CGFloat = 0.08) -> [CGPoint] {
        guard points.count > 1 else { return [] }
        let sortedPoints = points.sorted { $0.timestamp < $1.timestamp }
        let latitudes = sortedPoints.map(\.latitude)
        let longitudes = sortedPoints.map(\.longitude)
        guard let minLatitude = latitudes.min(),
              let maxLatitude = latitudes.max(),
              let minLongitude = longitudes.min(),
              let maxLongitude = longitudes.max() else { return [] }

        let latitudeSpan = maxLatitude - minLatitude
        let longitudeSpan = maxLongitude - minLongitude
        let epsilon = 0.000_000_1
        let rawPoints = sortedPoints.map { point in
            CGPoint(
                x: longitudeSpan > epsilon ? (point.longitude - minLongitude) / longitudeSpan : 0.5,
                y: latitudeSpan > epsilon ? 1 - ((point.latitude - minLatitude) / latitudeSpan) : 0.5
            )
        }
        return aspectFit(rawPoints, inset: inset)
    }

    nonisolated private static func aspectFit(_ points: [CGPoint], inset: CGFloat) -> [CGPoint] {
        guard points.count > 1 else { return [] }
        let inset = min(max(inset, 0), 0.35)
        let available = 1 - (inset * 2)
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 0
        let width = maxX - minX
        let height = maxY - minY
        let epsilon: CGFloat = 0.000_001

        if width <= epsilon, height <= epsilon {
            return points.map { _ in CGPoint(x: 0.5, y: 0.5) }
        }

        if width <= epsilon {
            return points.map { point in
                CGPoint(x: 0.5, y: clamp(inset + ((point.y - minY) / max(height, epsilon)) * available))
            }
        }

        if height <= epsilon {
            return points.map { point in
                CGPoint(x: clamp(inset + ((point.x - minX) / max(width, epsilon)) * available), y: 0.5)
            }
        }

        let scale = min(available / width, available / height)
        let scaledWidth = width * scale
        let scaledHeight = height * scale
        let xOffset = (1 - scaledWidth) / 2
        let yOffset = (1 - scaledHeight) / 2

        return points.map { point in
            CGPoint(
                x: clamp(xOffset + (point.x - minX) * scale),
                y: clamp(yOffset + (point.y - minY) * scale)
            )
        }
    }

    nonisolated private static func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
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
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 46, height: 46)
                    Text("Pulsar")
                        .font(.system(size: 28, weight: .bold, design: .default))
                    Spacer()
                    Text(content.startedAt.formatted(.dateTime.day().month(.abbreviated).year()))
                        .font(.system(size: 20, weight: .semibold, design: .serif))
                }
                .foregroundStyle(.white)

                Spacer()

                VStack(alignment: .leading, spacing: 18) {
                    Label(content.workoutLabel.uppercased(), systemImage: content.symbolName)
                        .font(.system(size: 17, weight: .bold, design: .default))
                        .foregroundStyle(.white.opacity(0.74))
                        .tracking(4)

                    if content.routePoints.count > 1 {
                        PulsarShareRouteLine(points: content.routePoints, accent: content.tint)
                            .frame(height: 120)
                    }

                    Text(content.title)
                        .font(.system(size: 44, weight: .semibold, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.62)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(content.primaryMetrics) { metric in
                            shareMetric(metric.title, metric.value)
                        }
                    }

                    Label("\(content.startedAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())) · \(content.sourceDeviceName)", systemImage: "sparkles")
                        .font(.system(size: 18, weight: .semibold, design: .default))
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
                PulsarShareRouteLine(points: content.routePoints, accent: content.tint, lineWidth: 11)
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
                .font(.system(size: 34, weight: .bold, design: .default))
                .minimumScaleFactor(0.72)
                .lineLimit(1)
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .default))
                .foregroundStyle(.white.opacity(0.68))
        }
        .foregroundStyle(.white)
    }
}

struct PulsarShareRouteLine: View {
    var points: [CGPoint]
    var accent: Color
    var lineWidth: CGFloat = 9

    var body: some View {
        Canvas { context, size in
            guard points.count > 1 else { return }
            var path = Path()
            let inset = max(lineWidth * 2.4, min(size.width, size.height) * 0.025)
            let rect = CGRect(
                x: inset,
                y: inset,
                width: max(1, size.width - inset * 2),
                height: max(1, size.height - inset * 2)
            )
            let scaled = points.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
            path.move(to: scaled[0])
            for point in scaled.dropFirst() {
                path.addLine(to: point)
            }
            context.stroke(path, with: .color(accent.opacity(0.24)), style: StrokeStyle(lineWidth: lineWidth * 3.1, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(.white.opacity(0.14)), style: StrokeStyle(lineWidth: lineWidth * 1.8, lineCap: .round, lineJoin: .round))
            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [.white.opacity(0.96), Color(red: 1.0, green: 0.46, blue: 0.34), accent]),
                    startPoint: scaled.first ?? .zero,
                    endPoint: scaled.last ?? CGPoint(x: size.width, y: size.height)
                ),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
            if let first = scaled.first {
                context.fill(Path(ellipseIn: CGRect(x: first.x - 12, y: first.y - 12, width: 24, height: 24)), with: .color(.white.opacity(0.25)))
                context.fill(Path(ellipseIn: CGRect(x: first.x - 7, y: first.y - 7, width: 14, height: 14)), with: .color(.white))
            }
            if let last = scaled.last {
                context.fill(Path(ellipseIn: CGRect(x: last.x - 14, y: last.y - 14, width: 28, height: 28)), with: .color(accent.opacity(0.30)))
                context.fill(Path(ellipseIn: CGRect(x: last.x - 9, y: last.y - 9, width: 18, height: 18)), with: .color(accent))
            }
        }
    }
}

private enum PulsarWorkoutShareFallbackRenderer {
    static func image(for content: PulsarWorkoutShareContent, size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.systemOrange.withAlphaComponent(0.9).setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: 18))

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 74, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            let bodyAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 38, weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.82)
            ]

            NSString(string: content.title).draw(
                in: CGRect(x: 72, y: 150, width: size.width - 144, height: 180),
                withAttributes: titleAttributes
            )
            NSString(string: content.primaryMetrics.map { "\($0.title) \($0.value)" }.joined(separator: "   ")).draw(
                in: CGRect(x: 72, y: 360, width: size.width - 144, height: 160),
                withAttributes: bodyAttributes
            )
            NSString(string: "Pulsar").draw(
                in: CGRect(x: 72, y: size.height - 150, width: size.width - 144, height: 60),
                withAttributes: bodyAttributes
            )
        }
    }
}

private enum PulsarShareDebugLogger {
    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[PulsarShare] \(message())")
        #endif
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
