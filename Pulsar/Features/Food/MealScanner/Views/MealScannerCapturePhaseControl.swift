//
//  MealScannerCapturePhaseControl.swift
//  Pulsar
//

import SwiftUI

struct MealScannerCapturePhaseControl: View {
    var selectedPhase: MealScannerCameraOverlay.CapturePhase
    var isLiDARAvailable: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 0) {
            phaseLabel(
                title: "1 Photo",
                systemImage: "camera.fill",
                phase: .photo,
                isAvailable: true
            )

            Rectangle()
                .fill(.white.opacity(0.22))
                .frame(width: 1, height: 24)
                .accessibilityHidden(true)

            phaseLabel(
                title: "LiDAR",
                systemImage: "circle.grid.3x3.fill",
                phase: .lidar,
                isAvailable: isLiDARAvailable
            )
        }
        .padding(3)
        .frame(height: dynamicTypeSize.isAccessibilitySize ? 68 : 48)
        .mealScannerGlassSurface(cornerRadius: 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private func phaseLabel(
        title: String,
        systemImage: String,
        phase: MealScannerCameraOverlay.CapturePhase,
        isAvailable: Bool
    ) -> some View {
        let isSelected = selectedPhase == phase

        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 2) {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .medium))
                    Text(title)
                        .font(.subheadline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)
                }
            } else {
                Label(title, systemImage: systemImage)
                    .font(.footnote)
            }
        }
        .bold(isSelected)
        .foregroundStyle(.white.opacity(isAvailable ? (isSelected ? 1 : 0.68) : 0.34))
        .shadow(color: .black.opacity(0.44), radius: 2, y: 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .mealScannerSelectionGlass(isSelected: isSelected)
        .animation(.smooth(duration: 0.22), value: selectedPhase)
    }

    private var accessibilityLabel: String {
        switch selectedPhase {
        case .photo:
            "Capture stage: one photo"
        case .lidar:
            "Capture stage: LiDAR"
        }
    }
}
