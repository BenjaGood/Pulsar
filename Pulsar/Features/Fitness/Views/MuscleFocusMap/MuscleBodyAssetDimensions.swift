//
//  MuscleBodyAssetDimensions.swift
//  Pulsar
//

import CoreGraphics

/// Canonical canvas dimensions for Muscle Focus Map raster assets.
/// Front and back sets use slightly different source exports; each figure locks
/// to its own aspect ratio so base and overlays scale identically.
enum MuscleBodyAssetDimensions {
    static let frontSize = CGSize(width: 822, height: 1913)
    static let backSize = CGSize(width: 821, height: 1915)

    static func aspectRatio(isBack: Bool) -> CGFloat {
        let size = isBack ? backSize : frontSize
        return size.width / size.height
    }
}
