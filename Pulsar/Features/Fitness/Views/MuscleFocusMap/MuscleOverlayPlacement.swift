//
//  MuscleOverlayPlacement.swift
//  Pulsar
//

import CoreGraphics
import SwiftUI

/// Per-muscle registration against the base body canvas.
///
/// Overlay PNGs share canvas size with the base, but their painted muscle
/// regions are oversized / shifted relative to the 3D anatomy. These values
/// shrink each overlay around its content anchor and nudge it onto the body.
///
/// Offsets are normalized to the figure frame (1.0 == full width/height).
/// Positive `offsetY` moves the overlay downward.
struct MuscleOverlayPlacement: Hashable {
    /// Uniform scale applied around `anchor`.
    var scale: CGFloat
    /// Normalized content-center of the overlay on its canvas (0...1).
    var anchor: UnitPoint
    /// Normalized X offset after scaling.
    var offsetX: CGFloat
    /// Normalized Y offset after scaling.
    var offsetY: CGFloat
    /// Pulls left/right halves toward the midline (normalized width).
    /// Use for bilateral overlays whose lobes are painted too far apart.
    var bilateralInward: CGFloat

    static let identity = MuscleOverlayPlacement(
        scale: 1,
        anchor: .center,
        offsetX: 0,
        offsetY: 0,
        bilateralInward: 0
    )

    static func placement(for muscle: MuscleMatrixGroup, isBack: Bool) -> MuscleOverlayPlacement {
        if isBack {
            return backPlacement(for: muscle)
        }
        return frontPlacement(for: muscle)
    }

    private static func frontPlacement(for muscle: MuscleMatrixGroup) -> MuscleOverlayPlacement {
        switch muscle {
        case .chest:
            // The generated pec pass is substantially wider and lower than the
            // pectoral region on this body. Keep both lobes inside the chest.
            MuscleOverlayPlacement(
                scale: 0.60,
                anchor: UnitPoint(x: 0.494, y: 0.305),
                offsetX: 0,
                offsetY: -0.048,
                bilateralInward: 0.024
            )
        case .shoulders:
            MuscleOverlayPlacement(
                scale: 0.70,
                anchor: UnitPoint(x: 0.499, y: 0.262),
                offsetX: 0,
                offsetY: -0.007,
                bilateralInward: 0.008
            )
        case .biceps:
            MuscleOverlayPlacement(
                scale: 0.80,
                anchor: UnitPoint(x: 0.501, y: 0.359),
                offsetX: 0,
                offsetY: -0.010,
                bilateralInward: 0.006
            )
        case .triceps:
            MuscleOverlayPlacement(
                scale: 0.85,
                anchor: UnitPoint(x: 0.499, y: 0.344),
                offsetX: 0,
                offsetY: -0.008,
                bilateralInward: 0.006
            )
        case .core:
            MuscleOverlayPlacement(
                scale: 0.52,
                anchor: UnitPoint(x: 0.506, y: 0.492),
                offsetX: 0,
                offsetY: -0.110,
                bilateralInward: 0
            )
        case .quads:
            MuscleOverlayPlacement(
                scale: 0.78,
                anchor: UnitPoint(x: 0.499, y: 0.552),
                offsetX: 0,
                offsetY: 0,
                bilateralInward: 0.006
            )
        case .calves:
            MuscleOverlayPlacement(
                scale: 0.62,
                anchor: UnitPoint(x: 0.500, y: 0.590),
                offsetX: 0,
                offsetY: 0.140,
                bilateralInward: 0.004
            )
        case .cardio:
            MuscleOverlayPlacement(
                scale: 0.70,
                anchor: UnitPoint(x: 0.500, y: 0.327),
                offsetX: 0,
                offsetY: -0.010,
                bilateralInward: 0
            )
        case .back, .glutes, .hamstrings:
            .identity
        }
    }

    private static func backPlacement(for muscle: MuscleMatrixGroup) -> MuscleOverlayPlacement {
        switch muscle {
        case .back:
            MuscleOverlayPlacement(
                scale: 0.72,
                anchor: UnitPoint(x: 0.498, y: 0.331),
                offsetX: 0,
                offsetY: -0.010,
                bilateralInward: 0
            )
        case .shoulders:
            MuscleOverlayPlacement(
                scale: 0.68,
                anchor: UnitPoint(x: 0.495, y: 0.320),
                offsetX: 0,
                offsetY: -0.080,
                bilateralInward: 0.006
            )
        case .triceps:
            MuscleOverlayPlacement(
                scale: 0.55,
                anchor: UnitPoint(x: 0.499, y: 0.350),
                offsetX: 0,
                offsetY: -0.040,
                bilateralInward: 0.010
            )
        case .glutes:
            MuscleOverlayPlacement(
                scale: 0.58,
                anchor: UnitPoint(x: 0.491, y: 0.550),
                offsetX: 0,
                offsetY: -0.035,
                bilateralInward: 0.006
            )
        case .hamstrings:
            MuscleOverlayPlacement(
                scale: 0.60,
                anchor: UnitPoint(x: 0.499, y: 0.650),
                offsetX: 0,
                offsetY: 0.100,
                bilateralInward: 0.005
            )
        case .calves:
            MuscleOverlayPlacement(
                scale: 0.64,
                anchor: UnitPoint(x: 0.501, y: 0.750),
                offsetX: 0,
                offsetY: 0.060,
                bilateralInward: 0.004
            )
        case .cardio:
            MuscleOverlayPlacement(
                scale: 0.68,
                anchor: UnitPoint(x: 0.500, y: 0.294),
                offsetX: 0,
                offsetY: -0.008,
                bilateralInward: 0
            )
        case .chest, .biceps, .core, .quads:
            .identity
        }
    }
}
