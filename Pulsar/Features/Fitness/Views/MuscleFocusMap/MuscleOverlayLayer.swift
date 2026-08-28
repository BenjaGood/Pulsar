//
//  MuscleOverlayLayer.swift
//  Pulsar
//

import SwiftUI

struct MuscleOverlayLayer: View {
    var imageName: String
    var entry: MuscleFocusMapPresentation.Entry
    var revealProgress: Double
    var isBack: Bool
    var figureSize: CGSize

    private var presentation: MuscleIntensityPresentation {
        MuscleIntensityPresentation.presentation(for: entry.intensity, muscle: entry.muscleGroup)
    }

    private var placement: MuscleOverlayPlacement {
        MuscleOverlayPlacement.placement(for: entry.muscleGroup, isBack: isBack)
    }

    var body: some View {
        if entry.isActive, MuscleAssetNameResolver.isAvailable(named: imageName) {
            // The supplied overlay rasters already contain softened edges. A
            // second blurred copy forced an extra offscreen render for every
            // active muscle while the map revealed, for very little visible
            // contribution at its former 5–10% opacity.
            registeredOverlay
                .blendMode(.screen)
                .opacity(coreOpacity)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var registeredOverlay: some View {
        let base = MuscleBodyAlignedImage(imageName: imageName)
            .scaleEffect(placement.scale, anchor: placement.anchor)
            .offset(
                x: placement.offsetX * figureSize.width,
                y: placement.offsetY * figureSize.height
            )

        if placement.bilateralInward > 0 {
            // Pull left/right muscle lobes toward the midline independently.
            // Needed because several overlays were painted too wide for this body.
            ZStack {
                base
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: figureSize.width * 0.5)
                    }
                    .offset(x: placement.bilateralInward * figureSize.width)

                base
                    .mask(alignment: .trailing) {
                        Rectangle().frame(width: figureSize.width * 0.5)
                    }
                    .offset(x: -placement.bilateralInward * figureSize.width)
            }
        } else {
            base
        }
    }

    private var coreOpacity: Double {
        presentation.coreOpacity * revealProgress
    }
}

/// Forces every base/overlay raster to share the exact same fitted bounds.
struct MuscleBodyAlignedImage: View {
    var imageName: String

    var body: some View {
        Image(imageName)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
