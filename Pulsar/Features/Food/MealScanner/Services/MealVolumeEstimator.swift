//
//  MealVolumeEstimator.swift
//  Pulsar
//

import ARKit
import CoreVideo
import Foundation
import Vision

struct MealVolumeEstimator {
    struct DepthGrid: Sendable {
        var width: Int
        var height: Int
        var depthsMeters: [Float]
        var maskValues: [UInt8]
        var confidenceValues: [UInt8]?

        init(
            width: Int,
            height: Int,
            depthsMeters: [Float],
            maskValues: [UInt8],
            confidenceValues: [UInt8]? = nil
        ) {
            self.width = max(0, width)
            self.height = max(0, height)
            self.depthsMeters = depthsMeters
            self.maskValues = maskValues
            self.confidenceValues = confidenceValues
        }
    }

    struct CameraCalibration: Sendable {
        var fx: Float
        var fy: Float
        var cx: Float
        var cy: Float
        var imageWidth: Int
        var imageHeight: Int
        var cameraTransform: simd_float4x4

        init(
            fx: Float,
            fy: Float,
            cx: Float,
            cy: Float,
            imageWidth: Int,
            imageHeight: Int,
            cameraTransform: simd_float4x4 = matrix_identity_float4x4
        ) {
            self.fx = fx
            self.fy = fy
            self.cx = cx
            self.cy = cy
            self.imageWidth = max(1, imageWidth)
            self.imageHeight = max(1, imageHeight)
            self.cameraTransform = cameraTransform
        }
    }

    private struct Plane {
        var normal: SIMD3<Float>
        var offset: Float

        func signedDistance(to point: SIMD3<Float>) -> Float {
            simd_dot(normal, point) + offset
        }
    }

    private struct SamplePoint {
        var point: SIMD3<Float>
        var depthMeters: Float
        var confidence: UInt8?
    }

    static func estimate(
        from frame: ARFrame?,
        scanSession: MealScanSessionSummary?,
        depthStats: MealScanDepthStats?
    ) -> MealVolumeEstimate? {
        guard let frame,
              let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth,
              let mask = foregroundMask(from: frame) else {
            return nil
        }

        return estimate(
            from: depthData,
            mask: mask,
            camera: frame.camera,
            scanSession: scanSession,
            depthStats: depthStats
        )
    }

    static func estimate(
        grid: DepthGrid,
        calibration: CameraCalibration,
        scanCoverage: Double? = nil,
        highConfidenceRatio: Double? = nil
    ) -> MealVolumeEstimate? {
        guard grid.width > 0,
              grid.height > 0,
              grid.depthsMeters.count >= grid.width * grid.height,
              grid.maskValues.count >= grid.width * grid.height,
              calibration.fx > 0,
              calibration.fy > 0 else {
            return nil
        }

        let bounds = maskBounds(maskValues: grid.maskValues, width: grid.width, height: grid.height)
        guard let bounds else { return nil }

        let foodSamples = collectFoodSamples(
            grid: grid,
            calibration: calibration,
            bounds: bounds
        )
        guard foodSamples.count >= 24 else { return nil }

        let supportSamples = collectSupportSamples(
            grid: grid,
            calibration: calibration,
            bounds: bounds
        )
        guard supportSamples.count >= 24,
              var plane = fittedSupportPlane(from: supportSamples) else {
            return nil
        }

        orient(&plane, toward: foodSamples)

        var integratedVolumeCubicMeters: Double = 0
        var contributingPixels = 0

        for sample in foodSamples {
            let height = Double(max(0, min(plane.signedDistance(to: sample.point), 0.24)))
            guard height >= 0.003 else { continue }
            let pixelArea = Double(sample.depthMeters * sample.depthMeters / (calibration.fx * calibration.fy))
            integratedVolumeCubicMeters += height * pixelArea
            contributingPixels += 1
        }

        guard contributingPixels >= 12 else { return nil }

        let volumeMilliliters = integratedVolumeCubicMeters * 1_000_000
        guard volumeMilliliters >= 8, volumeMilliliters <= 4_000 else {
            return nil
        }

        let maskPixelCount = max(1, grid.maskValues.filter { $0 >= 128 }.count)
        let depthCoverage = min(Double(contributingPixels) / Double(maskPixelCount), 1)
        let sessionCoverage = scanCoverage ?? depthCoverage
        let supportConfidence = supportPlaneConfidence(
            supportSamples: supportSamples,
            plane: plane,
            highConfidenceRatio: highConfidenceRatio
        )
        let coverage = min(max((depthCoverage * 0.65) + (sessionCoverage * 0.35), 0), 1)
        let relativeUncertainty = min(max(0.18 + ((1 - supportConfidence) * 0.28) + ((1 - coverage) * 0.24), 0.22), 0.70)

        return MealVolumeEstimate(
            volumeMilliliters: volumeMilliliters,
            method: "single_frame_depth_mask_v1",
            supportPlaneConfidence: supportConfidence,
            coverage: coverage,
            uncertaintyMlLow: volumeMilliliters * (1 - relativeUncertainty),
            uncertaintyMlHigh: volumeMilliliters * (1 + relativeUncertainty)
        )
    }

    static func resampledMaskValues(
        from maskValues: [UInt8],
        maskWidth: Int,
        maskHeight: Int,
        depthWidth: Int,
        depthHeight: Int
    ) -> [UInt8] {
        guard maskWidth > 0, maskHeight > 0, depthWidth > 0, depthHeight > 0 else { return [] }
        var values: [UInt8] = []
        values.reserveCapacity(depthWidth * depthHeight)
        for y in 0..<depthHeight {
            for x in 0..<depthWidth {
                values.append(
                    maskValue(
                        atDepthX: x,
                        depthY: y,
                        depthWidth: depthWidth,
                        depthHeight: depthHeight,
                        maskValues: maskValues,
                        maskWidth: maskWidth,
                        maskHeight: maskHeight
                    )
                )
            }
        }
        return values
    }

    private static func estimate(
        from depthData: ARDepthData,
        mask: CVPixelBuffer,
        camera: ARCamera,
        scanSession: MealScanSessionSummary?,
        depthStats: MealScanDepthStats?
    ) -> MealVolumeEstimate? {
        let depthMap = depthData.depthMap
        let confidenceMap = depthData.confidenceMap
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        if let confidenceMap {
            CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        }
        defer {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
            CVPixelBufferUnlockBaseAddress(mask, .readOnly)
            if let confidenceMap {
                CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
            }
        }

        guard CVPixelBufferGetPixelFormatType(depthMap) == kCVPixelFormatType_DepthFloat32,
              let depthBaseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return nil
        }

        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        let depthStride = CVPixelBufferGetBytesPerRow(depthMap) / MemoryLayout<Float32>.stride
        let depthAddress = depthBaseAddress.assumingMemoryBound(to: Float32.self)
        var depths: [Float] = Array(repeating: 0, count: depthWidth * depthHeight)
        for y in 0..<depthHeight {
            let row = depthAddress.advanced(by: y * depthStride)
            for x in 0..<depthWidth {
                depths[(y * depthWidth) + x] = row[x]
            }
        }

        let maskWidth = CVPixelBufferGetWidth(mask)
        let maskHeight = CVPixelBufferGetHeight(mask)
        let maskValues = resampledMaskValues(
            from: pixelValues(from: mask),
            maskWidth: maskWidth,
            maskHeight: maskHeight,
            depthWidth: depthWidth,
            depthHeight: depthHeight
        )
        let confidenceValues = confidenceValues(
            from: confidenceMap,
            depthWidth: depthWidth,
            depthHeight: depthHeight
        )
        let intrinsics = camera.intrinsics
        let resolution = camera.imageResolution
        let scaleX = Float(depthWidth) / max(Float(resolution.width), 1)
        let scaleY = Float(depthHeight) / max(Float(resolution.height), 1)
        let calibration = CameraCalibration(
            fx: intrinsics.columns.0.x * scaleX,
            fy: intrinsics.columns.1.y * scaleY,
            cx: intrinsics.columns.2.x * scaleX,
            cy: intrinsics.columns.2.y * scaleY,
            imageWidth: depthWidth,
            imageHeight: depthHeight,
            cameraTransform: camera.transform
        )

        return estimate(
            grid: DepthGrid(
                width: depthWidth,
                height: depthHeight,
                depthsMeters: depths,
                maskValues: maskValues,
                confidenceValues: confidenceValues
            ),
            calibration: calibration,
            scanCoverage: scanSession?.coverageRatio,
            highConfidenceRatio: depthStats?.highConfidenceRatio
        )
    }

    private static func foregroundMask(from frame: ARFrame) -> CVPixelBuffer? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage, options: [:])
        do {
            try handler.perform([request])
            guard let observation = request.results?.first else { return nil }
            return try observation.generateScaledMaskForImage(
                forInstances: observation.allInstances,
                from: handler
            )
        } catch {
            return nil
        }
    }

    private static func pixelValues(from pixelBuffer: CVPixelBuffer) -> [UInt8] {
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return [] }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        var values: [UInt8] = Array(repeating: 0, count: width * height)

        switch pixelFormat {
        case kCVPixelFormatType_OneComponent8:
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let address = baseAddress.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                let row = address.advanced(by: y * bytesPerRow)
                for x in 0..<width {
                    values[(y * width) + x] = row[x]
                }
            }
        case kCVPixelFormatType_OneComponent32Float:
            let rowStride = CVPixelBufferGetBytesPerRow(pixelBuffer) / MemoryLayout<Float32>.stride
            let address = baseAddress.assumingMemoryBound(to: Float32.self)
            for y in 0..<height {
                let row = address.advanced(by: y * rowStride)
                for x in 0..<width {
                    values[(y * width) + x] = UInt8(min(max(row[x], 0), 1) * 255)
                }
            }
        default:
            break
        }
        return values
    }

    private static func confidenceValues(
        from confidenceMap: CVPixelBuffer?,
        depthWidth: Int,
        depthHeight: Int
    ) -> [UInt8]? {
        guard let confidenceMap,
              let baseAddress = CVPixelBufferGetBaseAddress(confidenceMap) else {
            return nil
        }

        let confidenceWidth = CVPixelBufferGetWidth(confidenceMap)
        let confidenceHeight = CVPixelBufferGetHeight(confidenceMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(confidenceMap)
        let address = baseAddress.assumingMemoryBound(to: UInt8.self)
        var values: [UInt8] = Array(repeating: 0, count: depthWidth * depthHeight)
        for y in 0..<depthHeight {
            let confidenceY = min(confidenceHeight - 1, max(0, y * confidenceHeight / max(1, depthHeight)))
            let row = address.advanced(by: confidenceY * bytesPerRow)
            for x in 0..<depthWidth {
                let confidenceX = min(confidenceWidth - 1, max(0, x * confidenceWidth / max(1, depthWidth)))
                values[(y * depthWidth) + x] = row[confidenceX]
            }
        }
        return values
    }

    private static func maskValue(
        atDepthX depthX: Int,
        depthY: Int,
        depthWidth: Int,
        depthHeight: Int,
        maskValues: [UInt8],
        maskWidth: Int,
        maskHeight: Int
    ) -> UInt8 {
        guard !maskValues.isEmpty else { return 0 }
        let maskX = min(maskWidth - 1, max(0, depthX * maskWidth / max(1, depthWidth)))
        let maskY = min(maskHeight - 1, max(0, depthY * maskHeight / max(1, depthHeight)))
        let index = (maskY * maskWidth) + maskX
        guard index >= 0, index < maskValues.count else { return 0 }
        return maskValues[index]
    }

    private static func maskBounds(maskValues: [UInt8], width: Int, height: Int) -> (minX: Int, maxX: Int, minY: Int, maxY: Int)? {
        var minX = width
        var maxX = -1
        var minY = height
        var maxY = -1
        for y in 0..<height {
            for x in 0..<width where maskValues[(y * width) + x] >= 128 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return (minX, maxX, minY, maxY)
    }

    private static func collectFoodSamples(
        grid: DepthGrid,
        calibration: CameraCalibration,
        bounds: (minX: Int, maxX: Int, minY: Int, maxY: Int)
    ) -> [SamplePoint] {
        collectSamples(
            grid: grid,
            calibration: calibration,
            minimumConfidence: 2
        ) { x, y, maskValue in
            maskValue >= 128
                && x >= bounds.minX
                && x <= bounds.maxX
                && y >= bounds.minY
                && y <= bounds.maxY
        }
    }

    private static func collectSupportSamples(
        grid: DepthGrid,
        calibration: CameraCalibration,
        bounds: (minX: Int, maxX: Int, minY: Int, maxY: Int)
    ) -> [SamplePoint] {
        let padX = max(4, (bounds.maxX - bounds.minX) / 2)
        let padY = max(4, (bounds.maxY - bounds.minY) / 2)
        let minX = max(0, bounds.minX - padX)
        let maxX = min(grid.width - 1, bounds.maxX + padX)
        let minY = max(0, bounds.minY - padY)
        let maxY = min(grid.height - 1, bounds.maxY + padY)

        return collectSamples(
            grid: grid,
            calibration: calibration,
            minimumConfidence: 1
        ) { x, y, maskValue in
            maskValue < 96 && x >= minX && x <= maxX && y >= minY && y <= maxY
        }
    }

    private static func collectSamples(
        grid: DepthGrid,
        calibration: CameraCalibration,
        minimumConfidence: UInt8,
        include: (Int, Int, UInt8) -> Bool
    ) -> [SamplePoint] {
        let step = max(1, min(grid.width, grid.height) / 96)
        var samples: [SamplePoint] = []
        for y in stride(from: 0, to: grid.height, by: step) {
            for x in stride(from: 0, to: grid.width, by: step) {
                let index = (y * grid.width) + x
                let maskValue = grid.maskValues[index]
                guard include(x, y, maskValue) else { continue }
                let confidence = grid.confidenceValues?[index]
                guard (confidence ?? 2) >= minimumConfidence else { continue }
                let depth = grid.depthsMeters[index]
                guard depth.isFinite, depth > 0.08, depth < 2.4 else { continue }
                samples.append(
                    SamplePoint(
                        point: unproject(
                            x: Float(x),
                            y: Float(y),
                            depthMeters: depth,
                            calibration: calibration
                        ),
                        depthMeters: depth,
                        confidence: confidence
                    )
                )
            }
        }
        return samples
    }

    private static func unproject(
        x: Float,
        y: Float,
        depthMeters: Float,
        calibration: CameraCalibration
    ) -> SIMD3<Float> {
        let cameraPoint = SIMD4<Float>(
            ((x - calibration.cx) * depthMeters) / calibration.fx,
            ((y - calibration.cy) * depthMeters) / calibration.fy,
            -depthMeters,
            1
        )
        let worldPoint = calibration.cameraTransform * cameraPoint
        return SIMD3(worldPoint.x, worldPoint.y, worldPoint.z)
    }

    private static func fittedSupportPlane(from samples: [SamplePoint]) -> Plane? {
        let points = downsampled(samples.map(\.point), limit: 160)
        guard points.count >= 3 else { return nil }

        var bestPlane: Plane?
        var bestInlierCount = 0
        let inlierThreshold: Float = 0.012
        let count = points.count
        let iterations = min(360, max(40, count * 2))

        for iteration in 0..<iterations {
            let i0 = iteration % count
            let i1 = (iteration * 17 + 7) % count
            let i2 = (iteration * 31 + 13) % count
            guard i0 != i1, i0 != i2, i1 != i2,
                  let plane = plane(from: points[i0], points[i1], points[i2]) else {
                continue
            }
            let inlierCount = points.reduce(0) { partial, point in
                abs(plane.signedDistance(to: point)) <= inlierThreshold ? partial + 1 : partial
            }
            if inlierCount > bestInlierCount {
                bestInlierCount = inlierCount
                bestPlane = plane
            }
        }

        guard let bestPlane, Double(bestInlierCount) / Double(points.count) >= 0.42 else {
            return nil
        }
        return bestPlane
    }

    private static func plane(from p0: SIMD3<Float>, _ p1: SIMD3<Float>, _ p2: SIMD3<Float>) -> Plane? {
        let normal = simd_cross(p1 - p0, p2 - p0)
        let length = simd_length(normal)
        guard length > 0.0001 else { return nil }
        let unitNormal = normal / length
        return Plane(normal: unitNormal, offset: -simd_dot(unitNormal, p0))
    }

    private static func orient(_ plane: inout Plane, toward foodSamples: [SamplePoint]) {
        let meanDistance = foodSamples.reduce(Float(0)) { partial, sample in
            partial + plane.signedDistance(to: sample.point)
        } / Float(max(1, foodSamples.count))
        if meanDistance < 0 {
            plane.normal = -plane.normal
            plane.offset = -plane.offset
        }
    }

    private static func supportPlaneConfidence(
        supportSamples: [SamplePoint],
        plane: Plane,
        highConfidenceRatio: Double?
    ) -> Double {
        let inliers = supportSamples.filter { abs(plane.signedDistance(to: $0.point)) <= 0.015 }.count
        let inlierRatio = Double(inliers) / Double(max(1, supportSamples.count))
        let confidenceRatio: Double
        if let highConfidenceRatio {
            confidenceRatio = highConfidenceRatio
        } else {
            let highConfidenceCount = supportSamples.filter { ($0.confidence ?? 2) >= 2 }.count
            confidenceRatio = Double(highConfidenceCount) / Double(max(1, supportSamples.count))
        }
        return min(max((inlierRatio * 0.72) + (confidenceRatio * 0.28), 0), 1)
    }

    private static func downsampled(_ points: [SIMD3<Float>], limit: Int) -> [SIMD3<Float>] {
        guard points.count > limit, limit > 0 else { return points }
        let stride = max(1, points.count / limit)
        return points.enumerated().compactMap { index, point in
            index.isMultiple(of: stride) ? point : nil
        }.prefix(limit).map { $0 }
    }
}
