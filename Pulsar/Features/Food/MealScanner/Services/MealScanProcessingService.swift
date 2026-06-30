//
//  MealScanProcessingService.swift
//  Pulsar
//

import ARKit
import AVFoundation
import CoreVideo
import Foundation
import UIKit

enum MealScanProcessingError: LocalizedError {
    case invalidImage
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "Meal Scanner could not read the captured image."
        case .imageEncodingFailed:
            "Meal Scanner could not prepare the image for upload."
        }
    }
}

struct MealScanProcessingService {
    private let jpegCompressionQuality: CGFloat
    private let maximumImageDimension: CGFloat

    init(
        jpegCompressionQuality: CGFloat = 0.82,
        maximumImageDimension: CGFloat = 1_600
    ) {
        self.jpegCompressionQuality = min(max(jpegCompressionQuality, 0.1), 1)
        self.maximumImageDimension = max(320, maximumImageDimension)
    }

    static var supportsLiDARDepth: Bool {
        ARWorldTrackingConfiguration.isSupported
            && (
                ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
                    || ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth)
            )
    }

    static func cameraAuthorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    static func requestCameraAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { isGranted in
                continuation.resume(returning: isGranted)
            }
        }
    }

    func makePayload(
        from image: UIImage,
        frame: ARFrame?,
        scanMode: MealScanMode,
        scanDuration: TimeInterval,
        scanSession: MealScanSessionSummary? = nil
    ) throws -> MealScanPayload {
        guard image.size.width > 0, image.size.height > 0 else {
            throw MealScanProcessingError.invalidImage
        }

        let depthStats = Self.depthStats(from: frame)
        let hasDepth = depthStats != nil
        let warnings = qualityWarnings(
            image: image,
            frame: frame,
            hasDepth: hasDepth,
            scanDuration: scanDuration,
            scanSession: scanSession
        )
        var clientHints = [
            "scanDurationSeconds": String(format: "%.2f", max(0, scanDuration)),
            "payloadPolicy": "compact_depth_statistics_only",
            "depthRawIncluded": "false",
            "scannerFlow": "photo_then_lidar_v2"
        ]
        if let scanSession {
            clientHints.merge(scanSession.clientHints) { _, new in new }
        }

        return MealScanPayload(
            metadata: MealScanCaptureMetadata(
                mode: scanMode,
                imageWidth: Int(image.size.width * image.scale),
                imageHeight: Int(image.size.height * image.scale),
                imageOrientation: image.imageOrientation.mealScanName,
                jpegQuality: Double(jpegCompressionQuality)
            ),
            quality: MealScanQuality(
                level: qualityLevel(
                    image: image,
                    hasDepth: hasDepth,
                    scanDuration: scanDuration,
                    warningCount: warnings.count,
                    scanSession: scanSession
                ),
                confidence: qualityConfidence(
                    image: image,
                    hasDepth: hasDepth,
                    scanDuration: scanDuration,
                    warningCount: warnings.count,
                    scanSession: scanSession
                ),
                hasDepth: hasDepth,
                hasLiDAR: Self.supportsLiDARDepth,
                depthSource: depthStats?.source ?? .none,
                lightingEstimate: lightingEstimate(from: frame),
                occlusionRisk: occlusionRisk(hasDepth: hasDepth, scanSession: scanSession),
                warnings: warnings
            ),
            depthStats: depthStats,
            camera: Self.cameraMetadata(from: frame),
            plateEstimate: conservativePlateEstimate(hasDepth: hasDepth),
            clientHints: clientHints
        )
    }

    func preparedJPEGBase64(from image: UIImage) throws -> String {
        let data = try preparedJPEGData(from: image)
        return data.base64EncodedString()
    }

    func preparedJPEGData(from image: UIImage) throws -> Data {
        guard image.size.width > 0, image.size.height > 0 else {
            throw MealScanProcessingError.invalidImage
        }

        let normalizedImage = image.normalizedForMealScan()
        let resizedImage = normalizedImage.resizedForMealScan(maximumDimension: maximumImageDimension)

        guard let data = resizedImage.jpegData(compressionQuality: jpegCompressionQuality), !data.isEmpty else {
            throw MealScanProcessingError.imageEncodingFailed
        }
        return data
    }

    private func qualityWarnings(
        image: UIImage,
        frame: ARFrame?,
        hasDepth: Bool,
        scanDuration: TimeInterval,
        scanSession: MealScanSessionSummary?
    ) -> [String] {
        var warnings: [String] = []
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale

        if min(pixelWidth, pixelHeight) < 720 {
            warnings.append("Image resolution is low; portion estimates should be reviewed.")
        }
        if scanDuration < 0.8 {
            warnings.append("Scan duration was short; depth and segmentation confidence may be limited.")
        }
        if !hasDepth {
            warnings.append("Depth was unavailable; estimates use image-only portion heuristics.")
        }
        if let scanSession, !scanSession.photoCaptured {
            warnings.append("Photo phase did not complete before analysis.")
        }
        if let scanSession, hasDepth, !scanSession.depthScanCompleted {
            warnings.append("Depth scan coverage was incomplete; portion estimates should be reviewed.")
        }
        if let frame, case .limited(let reason) = frame.camera.trackingState {
            warnings.append("AR tracking was limited: \(reason.mealScanName).")
        }

        return warnings
    }

    private func qualityLevel(
        image: UIImage,
        hasDepth: Bool,
        scanDuration: TimeInterval,
        warningCount: Int,
        scanSession: MealScanSessionSummary?
    ) -> MealScanQualityLevel {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale

        guard min(pixelWidth, pixelHeight) >= 480 else { return .insufficient }
        if let scanSession, hasDepth, scanSession.depthScanCompleted, scanSession.coveredCellRatio >= 0.62 {
            return warningCount <= 1 ? .good : .usable
        }
        if hasDepth, scanDuration >= 1.2, warningCount == 0 { return .good }
        if hasDepth, scanDuration >= 0.8 { return .usable }
        if warningCount <= 1 { return .usable }
        return .limited
    }

    private func qualityConfidence(
        image: UIImage,
        hasDepth: Bool,
        scanDuration: TimeInterval,
        warningCount: Int,
        scanSession: MealScanSessionSummary?
    ) -> Double {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let resolutionScore = min(1, max(0.25, min(pixelWidth, pixelHeight) / 1_200))
        let durationScore = min(1, max(0.25, scanDuration / 1.5))
        let depthScore = hasDepth ? 0.2 : 0
        let coverageScore = scanSession.map { ($0.coverageRatio * 0.12) + ($0.coveredCellRatio * 0.18) } ?? 0
        let warningPenalty = min(0.35, Double(warningCount) * 0.08)
        return min(max((resolutionScore * 0.40) + (durationScore * 0.25) + depthScore + coverageScore - warningPenalty, 0.1), 0.9)
    }

    private func occlusionRisk(hasDepth: Bool, scanSession: MealScanSessionSummary?) -> Double {
        guard hasDepth else { return 0.58 }
        guard let scanSession else { return 0.35 }
        let coverage = (scanSession.coverageRatio * 0.45) + (scanSession.coveredCellRatio * 0.55)
        return min(max(0.56 - (coverage * 0.42), 0.16), 0.56)
    }

    private func lightingEstimate(from frame: ARFrame?) -> Double? {
        guard let ambientIntensity = frame?.lightEstimate?.ambientIntensity else { return nil }
        return min(max(ambientIntensity / 1_000, 0), 1)
    }

    private func conservativePlateEstimate(hasDepth: Bool) -> MealPlateEstimate {
        MealPlateEstimate(
            diameterCentimeters: 24,
            areaSquareCentimeters: 452,
            volumeMilliliters: nil,
            confidence: hasDepth ? 0.42 : 0.24,
            source: hasDepth ? "default_plate_with_depth_context" : "default_plate_photo_only"
        )
    }

    private static func cameraMetadata(from frame: ARFrame?) -> MealScanCameraMetadata? {
        guard let frame else { return nil }
        let resolution = frame.camera.imageResolution
        let intrinsics = frame.camera.intrinsics

        return MealScanCameraMetadata(
            trackingState: frame.camera.trackingState.mealScanName,
            cameraIntrinsics: [
                intrinsics.columns.0.x, intrinsics.columns.0.y, intrinsics.columns.0.z,
                intrinsics.columns.1.x, intrinsics.columns.1.y, intrinsics.columns.1.z,
                intrinsics.columns.2.x, intrinsics.columns.2.y, intrinsics.columns.2.z
            ],
            imageResolutionWidth: Int(resolution.width),
            imageResolutionHeight: Int(resolution.height)
        )
    }

    private static func depthStats(from frame: ARFrame?) -> MealScanDepthStats? {
        guard let frame else { return nil }

        if let smoothedSceneDepth = frame.smoothedSceneDepth,
           let stats = depthStats(from: smoothedSceneDepth, source: .smoothedSceneDepth) {
            return stats
        }
        if let sceneDepth = frame.sceneDepth,
           let stats = depthStats(from: sceneDepth, source: .sceneDepth) {
            return stats
        }
        return nil
    }

    private static func depthStats(
        from sceneDepth: ARDepthData,
        source: MealScanDepthSource
    ) -> MealScanDepthStats? {
        let depthMap = sceneDepth.depthMap
        let confidenceMap = sceneDepth.confidenceMap
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        if let confidenceMap {
            CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        }
        defer {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
            if let confidenceMap {
                CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
            }
        }

        guard CVPixelBufferGetPixelFormatType(depthMap) == kCVPixelFormatType_DepthFloat32,
              let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return nil
        }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let rowStride = bytesPerRow / MemoryLayout<Float32>.stride
        let sampleStride = max(1, min(width, height) / 80)
        let typedAddress = baseAddress.assumingMemoryBound(to: Float32.self)
        var values: [Float] = []
        values.reserveCapacity((width / sampleStride) * (height / sampleStride))

        var highConfidenceSamples = 0
        var confidenceSamples = 0

        for y in stride(from: 0, to: height, by: sampleStride) {
            let row = typedAddress.advanced(by: y * rowStride)
            for x in stride(from: 0, to: width, by: sampleStride) {
                let value = row[x]
                guard value.isFinite, value > 0, value < 5 else { continue }
                values.append(value)

                if let confidence = confidenceValue(
                    from: confidenceMap,
                    depthX: x,
                    depthY: y,
                    depthWidth: width,
                    depthHeight: height
                ) {
                    confidenceSamples += 1
                    if confidence >= 2 {
                        highConfidenceSamples += 1
                    }
                }
            }
        }

        guard !values.isEmpty else { return nil }

        values.sort()
        let sum = values.reduce(0) { $0 + Double($1) }
        let highConfidenceRatio = confidenceSamples > 0
            ? Double(highConfidenceSamples) / Double(confidenceSamples)
            : nil

        return MealScanDepthStats(
            source: source,
            width: width,
            height: height,
            validSampleCount: values.count,
            sampledPixelCount: ((width + sampleStride - 1) / sampleStride) * ((height + sampleStride - 1) / sampleStride),
            minMeters: values.first ?? 0,
            maxMeters: values.last ?? 0,
            meanMeters: Float(sum / Double(values.count)),
            percentile10Meters: percentile(0.10, values: values),
            percentile50Meters: percentile(0.50, values: values),
            percentile90Meters: percentile(0.90, values: values),
            highConfidenceRatio: highConfidenceRatio
        )
    }

    private static func confidenceValue(
        from confidenceMap: CVPixelBuffer?,
        depthX: Int,
        depthY: Int,
        depthWidth: Int,
        depthHeight: Int
    ) -> UInt8? {
        guard let confidenceMap,
              let baseAddress = CVPixelBufferGetBaseAddress(confidenceMap) else {
            return nil
        }

        let confidenceWidth = CVPixelBufferGetWidth(confidenceMap)
        let confidenceHeight = CVPixelBufferGetHeight(confidenceMap)
        let confidenceX = min(confidenceWidth - 1, max(0, depthX * confidenceWidth / max(1, depthWidth)))
        let confidenceY = min(confidenceHeight - 1, max(0, depthY * confidenceHeight / max(1, depthHeight)))
        let bytesPerRow = CVPixelBufferGetBytesPerRow(confidenceMap)
        let row = baseAddress.assumingMemoryBound(to: UInt8.self).advanced(by: confidenceY * bytesPerRow)
        return row[confidenceX]
    }

    private static func percentile(_ percentile: Double, values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        let clamped = min(max(percentile, 0), 1)
        let index = Int((Double(values.count - 1) * clamped).rounded())
        return values[index]
    }
}

private extension UIImage {
    func normalizedForMealScan() -> UIImage {
        guard imageOrientation != .up else { return self }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func resizedForMealScan(maximumDimension: CGFloat) -> UIImage {
        let longestSide = max(size.width, size.height)
        guard longestSide > maximumDimension else { return self }

        let scaleFactor = maximumDimension / longestSide
        let targetSize = CGSize(width: size.width * scaleFactor, height: size.height * scaleFactor)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

private extension UIImage.Orientation {
    var mealScanName: String {
        switch self {
        case .up: "up"
        case .down: "down"
        case .left: "left"
        case .right: "right"
        case .upMirrored: "upMirrored"
        case .downMirrored: "downMirrored"
        case .leftMirrored: "leftMirrored"
        case .rightMirrored: "rightMirrored"
        @unknown default: "unknown"
        }
    }
}

private extension ARCamera.TrackingState {
    var mealScanName: String {
        switch self {
        case .notAvailable:
            "notAvailable"
        case .normal:
            "normal"
        case .limited(let reason):
            "limited.\(reason.mealScanName)"
        }
    }
}

private extension ARCamera.TrackingState.Reason {
    var mealScanName: String {
        switch self {
        case .initializing:
            "initializing"
        case .excessiveMotion:
            "excessiveMotion"
        case .insufficientFeatures:
            "insufficientFeatures"
        case .relocalizing:
            "relocalizing"
        @unknown default:
            "unknown"
        }
    }
}
