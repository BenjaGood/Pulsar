//
//  MealScanFrameAccumulator.swift
//  Pulsar
//

import ARKit
import Foundation
import simd

/// Collects key ARFrames during a guided LiDAR scan and fuses per-frame
/// volume estimates into a median-based multi-frame result.
///
/// Key-frame selection uses a translation + yaw distance threshold so that
/// only frames representing meaningfully different viewpoints are stored.
/// At analysis time, `fuse(scanSession:depthStats:)` runs `MealVolumeEstimator`
/// on each key frame and combines the results robustly.
struct MealScanFrameAccumulator {

    // MARK: - Types

    struct FusionResult {
        var estimate: MealVolumeEstimate?
        /// Relative standard deviation across per-frame volume estimates.
        /// High values (> 0.35) indicate inconsistent depth across viewpoints.
        var relativeStdDev: Double
    }

    // ARFrame is a class; @unchecked Sendable is safe because the accumulator
    // is always accessed on @MainActor.
    private struct KeyFrame: @unchecked Sendable {
        let frame: ARFrame
    }

    // MARK: - Configuration

    static let maxKeyFrames = 8
    private static let minDistanceMeters: Float = 0.035
    private static let minYawRadians: Float = 0.055

    // MARK: - State

    private var keyFrames: [KeyFrame] = []
    private var lastPosition: SIMD3<Float>?
    private var lastYaw: Float?

    // MARK: - Public interface

    var frameCount: Int { keyFrames.count }
    var isEmpty: Bool { keyFrames.isEmpty }

    /// Records `frame` as a potential key frame.
    /// Silently drops frames that are too close to the last accepted key frame,
    /// that have no depth data, or that exceed `maxKeyFrames`.
    mutating func record(_ frame: ARFrame) {
        guard keyFrames.count < Self.maxKeyFrames else { return }
        guard case .normal = frame.camera.trackingState else { return }
        guard frame.smoothedSceneDepth != nil || frame.sceneDepth != nil else { return }

        let t = frame.camera.transform
        let pos = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        let fwd = SIMD3<Float>(-t.columns.2.x, -t.columns.2.y, -t.columns.2.z)
        let yaw = atan2(fwd.x, fwd.z)

        if let last = lastPosition, let lastYaw {
            let distance = simd_length(pos - last)
            let rawDelta = abs(yaw - lastYaw)
            let yawDelta = min(rawDelta, 2 * .pi - rawDelta)
            guard distance >= Self.minDistanceMeters || yawDelta >= Self.minYawRadians else {
                return
            }
        }

        lastPosition = pos
        lastYaw = yaw
        keyFrames.append(KeyFrame(frame: frame))
    }

    mutating func reset() {
        keyFrames = []
        lastPosition = nil
        lastYaw = nil
    }

    /// Runs `MealVolumeEstimator` on each stored key frame and fuses the valid
    /// results into a single `MealVolumeEstimate`.  Returns `nil` estimate when
    /// no key frame produces a usable geometry result.
    func fuse(
        scanSession: MealScanSessionSummary?,
        depthStats: MealScanDepthStats?
    ) -> FusionResult {
        var estimates: [MealVolumeEstimate] = []
        for keyFrame in keyFrames {
            if let e = MealVolumeEstimator.estimate(
                from: keyFrame.frame,
                scanSession: scanSession,
                depthStats: depthStats
            ) {
                estimates.append(e)
            }
        }
        return Self.fusedResult(from: estimates)
    }

    // MARK: - Testable pure fusion math

    /// Fuses a pre-computed array of estimates.  Exposed `internal` for unit tests.
    static func fusedResult(from estimates: [MealVolumeEstimate]) -> FusionResult {
        let valid = estimates.filter { $0.volumeMilliliters > 0 }
        guard !valid.isEmpty else { return FusionResult(estimate: nil, relativeStdDev: 0) }

        guard valid.count >= 2 else {
            let e = valid[0]
            return FusionResult(
                estimate: MealVolumeEstimate(
                    volumeMilliliters: e.volumeMilliliters,
                    method: e.method,
                    supportPlaneConfidence: e.supportPlaneConfidence,
                    coverage: e.coverage,
                    uncertaintyMlLow: e.uncertaintyMlLow,
                    uncertaintyMlHigh: e.uncertaintyMlHigh,
                    frameCount: 1
                ),
                relativeStdDev: 0
            )
        }

        let volumes = valid.map(\.volumeMilliliters).sorted()
        let medianVolume = median(of: volumes)
        let meanVolume = volumes.reduce(0, +) / Double(volumes.count)
        let variance = volumes.reduce(0.0) { $0 + pow($1 - meanVolume, 2) } / Double(volumes.count)
        let stdDev = variance.squareRoot()
        let relativeStdDev = meanVolume > 0 ? stdDev / meanVolume : 0

        let meanCoverage = valid.map(\.coverage).reduce(0, +) / Double(valid.count)
        let meanPlaneConf = valid.map(\.supportPlaneConfidence).reduce(0, +) / Double(valid.count)

        // Base uncertainty: mean of per-frame relative half-range, expanded by inter-frame variance.
        let baseRelativeUnc = valid.map { e -> Double in
            let range = e.uncertaintyMlHigh - e.uncertaintyMlLow
            return e.volumeMilliliters > 0 ? range / (2 * e.volumeMilliliters) : 0.35
        }.reduce(0, +) / Double(valid.count)
        let coveragePenalty = (1 - meanCoverage) * 0.18
        let planePenalty = (1 - meanPlaneConf) * 0.10
        let relativeUncertainty = min(
            max(baseRelativeUnc + (relativeStdDev * 0.5) + coveragePenalty + planePenalty, 0.15),
            0.75
        )

        let fused = MealVolumeEstimate(
            volumeMilliliters: medianVolume,
            method: "multi_frame_depth_mask_v1",
            supportPlaneConfidence: meanPlaneConf,
            coverage: meanCoverage,
            uncertaintyMlLow: medianVolume * (1 - relativeUncertainty),
            uncertaintyMlHigh: medianVolume * (1 + relativeUncertainty),
            frameCount: valid.count
        )

        return FusionResult(estimate: fused, relativeStdDev: relativeStdDev)
    }

    private static func median(of sortedValues: [Double]) -> Double {
        guard !sortedValues.isEmpty else { return 0 }
        let midpoint = sortedValues.count / 2
        if sortedValues.count.isMultiple(of: 2) {
            return (sortedValues[midpoint - 1] + sortedValues[midpoint]) / 2
        }
        return sortedValues[midpoint]
    }
}
