//
//  MealScannerBottomControlSurface.swift
//  Pulsar
//

import SwiftUI

struct MealScannerBottomControlSurface: View {
    var scanProgress: Double
    var isAnalyzing: Bool
    var captureAccessibilityLabel: String
    var onTips: () -> Void
    var onCapture: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: onTips) {
                VStack(spacing: 5) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.48), radius: 2, y: 1)
                        .frame(width: 46, height: 46)
                        .pulsarLiquidGlass(cornerRadius: 23, interactive: true, isClear: true)

                    Text("Tips")
                        .font(.caption)
                        .bold()
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.48), radius: 2, y: 1)

                    Text("0%")
                        .font(.caption)
                        .hidden()
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows brief scanning guidance")

            Button(action: onCapture) {
                ZStack {
                    Circle()
                        .fill(.clear)
                        .frame(width: 84, height: 84)
                        .pulsarLiquidGlass(cornerRadius: 42, interactive: true, isClear: true)

                    Circle()
                        .fill(.white.opacity(0.97))
                        .frame(width: 66, height: 66)
                        .overlay {
                            Circle()
                                .stroke(.white, lineWidth: 1.5)
                        }
                        .shadow(color: .black.opacity(0.10), radius: 6, y: 3)

                    if isAnalyzing {
                        ProgressView()
                            .tint(.black.opacity(0.72))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(MealScannerShutterButtonStyle())
            .disabled(isAnalyzing)
            .accessibilityLabel(captureAccessibilityLabel)

            VStack(spacing: 5) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.48), radius: 2, y: 1)
                    .frame(width: 46, height: 46)
                    .pulsarLiquidGlass(cornerRadius: 23, isClear: true)
                    .accessibilityHidden(true)

                Text("3D Map")
                    .font(.caption)
                    .bold()
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.48), radius: 2, y: 1)

                Text(scanProgress, format: .percent.precision(.fractionLength(0)))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.68))
                    .shadow(color: .black.opacity(0.48), radius: 2, y: 1)
                    .contentTransition(.numericText(value: scanProgress))
                    .animation(.smooth(duration: 0.22), value: scanProgress)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("3D map progress")
            .accessibilityValue(scanProgress.formatted(.percent.precision(.fractionLength(0))))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 116)
        .mealScannerGlassSurface(cornerRadius: 32)
    }
}
