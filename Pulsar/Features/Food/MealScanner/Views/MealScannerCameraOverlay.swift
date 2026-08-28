//
//  MealScannerCameraOverlay.swift
//  Pulsar
//

import SwiftUI

struct MealScannerCameraOverlay: View {
    enum CapturePhase: Equatable {
        case photo
        case lidar
    }

    struct Guidance: Equatable, Identifiable {
        var symbolName: String
        var title: String
        var subtitle: String

        var id: String {
            "\(symbolName)|\(title)|\(subtitle)"
        }
    }

    struct Model: Equatable {
        var currentStep: Int
        var selectedPhase: CapturePhase
        var isLiDARAvailable: Bool
        var guidance: Guidance
        var scanProgress: Double
        var isAnalyzing: Bool
        var captureAccessibilityLabel: String

        init(
            currentStep: Int,
            selectedPhase: CapturePhase,
            isLiDARAvailable: Bool,
            guidance: Guidance,
            scanProgress: Double,
            isAnalyzing: Bool,
            captureAccessibilityLabel: String
        ) {
            self.currentStep = min(max(currentStep, 1), 3)
            self.selectedPhase = selectedPhase
            self.isLiDARAvailable = isLiDARAvailable
            self.guidance = guidance
            self.scanProgress = min(max(scanProgress, 0), 1)
            self.isAnalyzing = isAnalyzing
            self.captureAccessibilityLabel = captureAccessibilityLabel
        }
    }

    var model: Model
    var onClose: () -> Void
    var onCapture: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTipsPresented = false

    var body: some View {
        GeometryReader { proxy in
            let screenWidth = proxy.size.width

            ZStack {
                MealScannerCameraHeader(
                    currentStep: model.currentStep,
                    onClose: onClose
                )
                .zIndex(2)

                VStack(spacing: 0) {
                    Spacer(minLength: 160)

                    PulsarGlassEffectGroup(spacing: 10) {
                        VStack(spacing: 8) {
                            MealScannerInstructionCard(guidance: model.guidance)
                                .frame(width: screenWidth * 0.82)

                            MealScannerCapturePhaseControl(
                                selectedPhase: model.selectedPhase,
                                isLiDARAvailable: model.isLiDARAvailable
                            )
                            .frame(width: screenWidth * 0.66)

                            MealScannerBottomControlSurface(
                                scanProgress: model.scanProgress,
                                isAnalyzing: model.isAnalyzing,
                                captureAccessibilityLabel: model.captureAccessibilityLabel,
                                onTips: showTips,
                                onCapture: onCapture
                            )
                            .frame(width: screenWidth * 0.90)
                        }
                        .frame(width: screenWidth)
                    }
                }
                .frame(width: screenWidth)
                .padding(.bottom, 7)

                if isTipsPresented {
                    MealScannerTipsPanel(onDismiss: dismissTips)
                        .frame(width: screenWidth * 0.82)
                        .zIndex(3)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .offset(y: 6))
                        )
                }
            }
            .animation(.smooth(duration: reduceMotion ? 0.16 : 0.26), value: isTipsPresented)
            .animation(.smooth(duration: reduceMotion ? 0.16 : 0.24), value: model.currentStep)
        }
    }

    private func showTips() {
        isTipsPresented = true
    }

    private func dismissTips() {
        isTipsPresented = false
    }
}

#Preview("Meal scanner camera overlay", traits: .fixedLayout(width: 430, height: 932)) {
    ZStack {
        Image(.strainNatureBackground)
            .resizable()
            .scaledToFill()
            .frame(width: 430, height: 932)
            .clipped()
        MealScannerCameraOverlay(
            model: .init(
                currentStep: 1,
                selectedPhase: .photo,
                isLiDARAvailable: true,
                guidance: .init(
                    symbolName: "camera.metering.center.weighted",
                    title: "Capture the plate",
                    subtitle: "Center the entire plate in good light."
                ),
                scanProgress: 0,
                isAnalyzing: false,
                captureAccessibilityLabel: "Capture Photo"
            ),
            onClose: {},
            onCapture: {}
        )
    }
    .ignoresSafeArea()
    .preferredColorScheme(.dark)
}

#Preview("Meal scanner camera overlay — compact", traits: .fixedLayout(width: 375, height: 667)) {
    ZStack {
        Image(.strainNatureBackground)
            .resizable()
            .scaledToFill()
            .frame(width: 375, height: 667)
            .clipped()
        MealScannerCameraOverlay(
            model: .init(
                currentStep: 2,
                selectedPhase: .lidar,
                isLiDARAvailable: true,
                guidance: .init(
                    symbolName: "move.3d",
                    title: "Scan around the plate",
                    subtitle: "Move slowly around the meal."
                ),
                scanProgress: 0.58,
                isAnalyzing: false,
                captureAccessibilityLabel: "Finish Scan"
            ),
            onClose: {},
            onCapture: {}
        )
    }
    .ignoresSafeArea()
    .preferredColorScheme(.dark)
}
