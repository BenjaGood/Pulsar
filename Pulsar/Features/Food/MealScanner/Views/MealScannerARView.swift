//
//  MealScannerARView.swift
//  Pulsar
//

import ARKit
import CoreImage
import CoreVideo
import RealityKit
import SwiftUI
import UIKit

@MainActor
final class MealScannerARCaptureController {
    fileprivate var currentFrame: ARFrame?
    private let imageContext = CIContext()

    func captureImage() -> (image: UIImage, frame: ARFrame)? {
        guard let currentFrame else { return nil }
        let pixelBuffer = currentFrame.capturedImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = imageContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return (UIImage(cgImage: cgImage, scale: 1, orientation: .right), currentFrame)
    }

    func currentFrameSnapshot() -> ARFrame? {
        currentFrame
    }
}

enum MealScannerDepthGrid {
    static let columns = 7
    static let rows = 5
    static let cellCount = columns * rows
}

struct MealScannerDepthPoint: Hashable {
    var x: Double
    var y: Double
    var z: Double
    var confidence: Double

    var normalizedDepth: Double {
        min(max((z - 0.12) / 1.45, 0), 1)
    }

    func offset(x deltaX: Double, y deltaY: Double) -> MealScannerDepthPoint {
        MealScannerDepthPoint(
            x: min(max(x + deltaX, -1.35), 1.35),
            y: min(max(y + deltaY, -1.35), 1.35),
            z: z,
            confidence: confidence
        )
    }
}

struct MealScannerCameraPose: Hashable {
    var x: Double
    var y: Double
    var z: Double
    var yaw: Double

    func distance(to other: MealScannerCameraPose) -> Double {
        let deltaX = x - other.x
        let deltaY = y - other.y
        let deltaZ = z - other.z
        return (deltaX * deltaX + deltaY * deltaY + deltaZ * deltaZ).squareRoot()
    }

    func yawDelta(to other: MealScannerCameraPose) -> Double {
        let rawDelta = abs(yaw - other.yaw)
        return min(rawDelta, (2 * .pi) - rawDelta)
    }
}

struct MealScannerLiveFrameFeedback: Equatable {
    var isTrackingReady: Bool
    var hasDepth: Bool
    var depthCoverage: Double
    var depthCoverageGrid: [Double]
    var depthPoints: [MealScannerDepthPoint]
    var cameraPose: MealScannerCameraPose?
    var lightingLevel: Double?
    var trackingMessage: String
    var lightingMessage: String

    init(
        isTrackingReady: Bool = false,
        hasDepth: Bool = false,
        depthCoverage: Double = 0,
        depthCoverageGrid: [Double] = Array(repeating: 0, count: MealScannerDepthGrid.cellCount),
        depthPoints: [MealScannerDepthPoint] = [],
        cameraPose: MealScannerCameraPose? = nil,
        lightingLevel: Double? = nil,
        trackingMessage: String = "Finding plate surface",
        lightingMessage: String = "Checking light"
    ) {
        self.isTrackingReady = isTrackingReady
        self.hasDepth = hasDepth
        self.depthCoverage = min(max(depthCoverage, 0), 1)
        self.depthCoverageGrid = Self.normalizedGrid(depthCoverageGrid)
        self.depthPoints = Array(depthPoints.prefix(240))
        self.cameraPose = cameraPose
        self.lightingLevel = lightingLevel
        self.trackingMessage = trackingMessage
        self.lightingMessage = lightingMessage
    }

    init(frame: ARFrame) {
        let lighting = frame.lightEstimate.map { min(max(Double($0.ambientIntensity) / 1_000, 0), 1) }
        let depthAnalysis = Self.depthAnalysis(from: frame.smoothedSceneDepth ?? frame.sceneDepth)
        self.init(
            isTrackingReady: frame.camera.trackingState.mealScanIsReady,
            hasDepth: depthAnalysis.hasDepth,
            depthCoverage: depthAnalysis.coverage,
            depthCoverageGrid: depthAnalysis.grid,
            depthPoints: depthAnalysis.points,
            cameraPose: Self.cameraPose(from: frame.camera.transform),
            lightingLevel: lighting.map { ($0 * 20).rounded() / 20 },
            trackingMessage: frame.camera.trackingState.mealScanGuidance,
            lightingMessage: Self.lightingMessage(for: lighting)
        )
    }

    var isLightingReady: Bool {
        guard let lightingLevel else { return true }
        return lightingLevel >= 0.24
    }

    var isCaptureReady: Bool {
        isTrackingReady && isLightingReady
    }

    var depthTitle: String {
        guard hasDepth else { return "Depth pending" }
        return "\(Int((depthCoverage * 100).rounded()))% mapped"
    }

    var lightingTitle: String {
        isLightingReady ? "Light OK" : "Need more light"
    }

    var trackingTitle: String {
        isTrackingReady ? "Tracking OK" : "Hold steady"
    }

    private static func lightingMessage(for lightingLevel: Double?) -> String {
        guard let lightingLevel else { return "Light OK" }
        if lightingLevel < 0.24 {
            return "Move to brighter light"
        }
        if lightingLevel < 0.38 {
            return "Good, avoid shadows"
        }
        return "Light OK"
    }

    private static func normalizedGrid(_ grid: [Double]) -> [Double] {
        let normalized = grid.prefix(MealScannerDepthGrid.cellCount).map { min(max($0, 0), 1) }
        if normalized.count == MealScannerDepthGrid.cellCount {
            return normalized
        }
        return normalized + Array(repeating: 0, count: MealScannerDepthGrid.cellCount - normalized.count)
    }

    private static func cameraPose(from transform: simd_float4x4) -> MealScannerCameraPose {
        let position = transform.columns.3
        let forward = SIMD3<Float>(
            -transform.columns.2.x,
            -transform.columns.2.y,
            -transform.columns.2.z
        )
        return MealScannerCameraPose(
            x: Double(position.x),
            y: Double(position.y),
            z: Double(position.z),
            yaw: atan2(Double(forward.x), Double(forward.z))
        )
    }

    private static func depthAnalysis(from depthData: ARDepthData?) -> (hasDepth: Bool, coverage: Double, grid: [Double], points: [MealScannerDepthPoint]) {
        guard let depthData else {
            return (false, 0, Array(repeating: 0, count: MealScannerDepthGrid.cellCount), [])
        }

        let depthMap = depthData.depthMap
        let confidenceMap = depthData.confidenceMap
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
            return (true, 0, Array(repeating: 0, count: MealScannerDepthGrid.cellCount), [])
        }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let rowStride = CVPixelBufferGetBytesPerRow(depthMap) / MemoryLayout<Float32>.stride
        let sampleStride = max(1, min(width, height) / 48)
        let typedAddress = baseAddress.assumingMemoryBound(to: Float32.self)
        let minX = max(0, Int(Double(width) * 0.10))
        let maxX = min(width, Int(Double(width) * 0.90))
        let minY = max(0, Int(Double(height) * 0.12))
        let maxY = min(height, Int(Double(height) * 0.88))
        let sampleWidth = max(1, maxX - minX)
        let sampleHeight = max(1, maxY - minY)

        var sampledCells = Array(repeating: 0, count: MealScannerDepthGrid.cellCount)
        var validCells = Array(repeating: 0, count: MealScannerDepthGrid.cellCount)
        var points: [MealScannerDepthPoint] = []
        var sampled = 0
        var valid = 0

        for y in stride(from: minY, to: maxY, by: sampleStride) {
            let row = typedAddress.advanced(by: y * rowStride)
            for x in stride(from: minX, to: maxX, by: sampleStride) {
                let cellX = min(MealScannerDepthGrid.columns - 1, max(0, (x - minX) * MealScannerDepthGrid.columns / sampleWidth))
                let cellY = min(MealScannerDepthGrid.rows - 1, max(0, (y - minY) * MealScannerDepthGrid.rows / sampleHeight))
                let cellIndex = (cellY * MealScannerDepthGrid.columns) + cellX
                sampledCells[cellIndex] += 1
                sampled += 1

                let value = row[x]
                let confidence = confidenceValue(
                    from: confidenceMap,
                    depthX: x,
                    depthY: y,
                    depthWidth: width,
                    depthHeight: height
                )
                guard value.isFinite, value > 0.08, value < 2.4, (confidence ?? 2) >= 1 else { continue }

                validCells[cellIndex] += 1
                valid += 1
                if points.count < 240 {
                    let normalizedX = ((Double(x - minX) / Double(sampleWidth)) - 0.5) * 2
                    let normalizedY = ((Double(y - minY) / Double(sampleHeight)) - 0.5) * 2
                    let confidenceScore = min(max(Double(confidence ?? 2) / 2, 0), 1)
                    points.append(
                        MealScannerDepthPoint(
                            x: normalizedX,
                            y: normalizedY,
                            z: Double(value),
                            confidence: confidenceScore
                        )
                    )
                }
            }
        }

        guard sampled > 0 else {
            return (true, 0, Array(repeating: 0, count: MealScannerDepthGrid.cellCount), [])
        }

        let grid = zip(validCells, sampledCells).map { valid, sampled in
            sampled > 0 ? min(Double(valid) / Double(sampled), 1) : 0
        }
        return (true, Double(valid) / Double(sampled), grid, points)
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
        let row = baseAddress.assumingMemoryBound(to: UInt8.self)
            .advanced(by: confidenceY * CVPixelBufferGetBytesPerRow(confidenceMap))
        return row[confidenceX]
    }
}

struct MealScannerARView: UIViewRepresentable {
    var captureController: MealScannerARCaptureController
    var scanMode: MealScanMode
    var isSessionRunning: Bool
    var showsLiDARMesh: Bool = false
    var onFrameUpdate: (MealScannerLiveFrameFeedback) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(captureController: captureController, onFrameUpdate: onFrameUpdate)
    }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.automaticallyConfigureSession = false
        view.session.delegate = context.coordinator
        view.environment.background = .cameraFeed()
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.onFrameUpdate = onFrameUpdate
        context.coordinator.configureLiDARMeshVisualization(
            on: uiView,
            enabled: showsLiDARMesh && scanMode == .depthAssisted && isSessionRunning
        )
        if isSessionRunning {
            context.coordinator.runSession(on: uiView, mode: scanMode)
        } else {
            context.coordinator.configureLiDARMeshVisualization(on: uiView, enabled: false)
            uiView.session.pause()
        }
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        uiView.session.pause()
        uiView.session.delegate = nil
    }

    final class Coordinator: NSObject, ARSessionDelegate {
        private weak var captureController: MealScannerARCaptureController?
        var onFrameUpdate: (MealScannerLiveFrameFeedback) -> Void
        private var lastMode: MealScanMode?
        private var isRunning = false
        private var isLiDARMeshVisible = false

        init(
            captureController: MealScannerARCaptureController,
            onFrameUpdate: @escaping (MealScannerLiveFrameFeedback) -> Void
        ) {
            self.captureController = captureController
            self.onFrameUpdate = onFrameUpdate
        }

        func runSession(on view: ARView, mode: MealScanMode) {
            guard !isRunning || lastMode != mode else { return }
            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = [.horizontal]
            if mode == .depthAssisted {
                var semantics: ARConfiguration.FrameSemantics = []
                if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                    semantics.insert(.sceneDepth)
                }
                if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
                    semantics.insert(.smoothedSceneDepth)
                }
                configuration.frameSemantics = semantics
                if #available(iOS 13.4, *),
                   ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
                    configuration.sceneReconstruction = .meshWithClassification
                } else if #available(iOS 13.4, *),
                          ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                    configuration.sceneReconstruction = .mesh
                }
            }
            view.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            lastMode = mode
            isRunning = true
        }

        func configureLiDARMeshVisualization(on view: ARView, enabled: Bool) {
            guard isLiDARMeshVisible != enabled else { return }
            isLiDARMeshVisible = enabled
            if #available(iOS 13.4, *) {
                if enabled {
                    view.debugOptions.insert(.showSceneUnderstanding)
                } else {
                    view.debugOptions.remove(.showSceneUnderstanding)
                }
            }
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            let feedback = MealScannerLiveFrameFeedback(frame: frame)
            Task { @MainActor [weak self] in
                self?.captureController?.currentFrame = frame
                self?.onFrameUpdate(feedback)
            }
        }
    }
}

private extension ARCamera.TrackingState {
    var mealScanIsReady: Bool {
        if case .normal = self {
            return true
        }
        return false
    }

    var mealScanGuidance: String {
        switch self {
        case .normal:
            "Tracking OK"
        case .notAvailable:
            "Move slowly until camera locks"
        case .limited(let reason):
            switch reason {
            case .initializing:
                "Hold steady while camera starts"
            case .excessiveMotion:
                "Move slower"
            case .insufficientFeatures:
                "Aim at the plate edge or table"
            case .relocalizing:
                "Hold steady"
            @unknown default:
                "Hold steady"
            }
        }
    }
}
