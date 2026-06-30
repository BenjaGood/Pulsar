//
//  MealScannerEntryCard.swift
//  Pulsar
//

import SwiftUI

struct MealScannerEntryCard: View {
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    private var scanMode: MealScanMode {
        MealScanProcessingService.supportsLiDARDepth ? .depthAssisted : .photoOnly
    }

    var body: some View {
        Button(action: action) {
            PulsarNutritionGlassCard(cornerRadius: 30, padding: 0) {
                HStack(alignment: .center, spacing: 16) {
                    scannerGlyph

                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 8) {
                            Text("3D Meal Scanner")
                                .pulsarTextStyle(.cardTitle)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)

                            Text("Premium")
                                .pulsarTextStyle(.overline)
                                .foregroundStyle(.white.opacity(0.92))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.green.opacity(0.74), in: Capsule(style: .continuous))
                        }

                        Text(subtitle)
                            .pulsarTextStyle(.captionEmphasis)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            MealScannerCapabilityPill(
                                title: scanMode == .depthAssisted ? "LiDAR depth enabled" : "Photo AI estimation mode",
                                symbolName: scanMode == .depthAssisted ? "viewfinder.circle.fill" : "camera.fill",
                                tint: scanMode == .depthAssisted ? .cyan : .orange
                            )

                            MealScannerCapabilityPill(
                                title: "Estimated nutrition",
                                symbolName: "chart.pie.fill",
                                tint: .green
                            )
                        }
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .pulsarTextStyle(.label)
                        .foregroundStyle(.tertiary)
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(colorScheme == .dark ? 0.08 : 0.54), in: Circle())
                }
                .padding(16)
                .background(cardGlow)
            }
        }
        .buttonStyle(MealScannerEntryButtonStyle())
        .accessibilityLabel("3D Meal Scanner")
        .accessibilityHint("Scans food with camera, depth when available, and AI nutrition estimation.")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }

    private var scannerGlyph: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.cyan.opacity(colorScheme == .dark ? 0.28 : 0.18),
                            Color.green.opacity(colorScheme == .dark ? 0.22 : 0.16),
                            Color.white.opacity(colorScheme == .dark ? 0.06 : 0.70)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .stroke(.white.opacity(colorScheme == .dark ? 0.18 : 0.70), lineWidth: 1)

            Image(systemName: "viewfinder")
                .font(.system(size: 25, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.94), .cyan.opacity(0.82))

            Circle()
                .stroke(.green.opacity(isBreathing ? 0.46 : 0.16), lineWidth: 2)
                .scaleEffect(isBreathing && !reduceMotion ? 1.13 : 0.96)
        }
        .frame(width: 58, height: 58)
        .accessibilityHidden(true)
    }

    private var subtitle: String {
        if scanMode == .depthAssisted {
            return "Scan your food with LiDAR and AI to estimate grams, macros, micros, and nutrients."
        }
        return "Scan your food with camera AI to estimate grams, macros, micros, and nutrients."
    }

    private var cardGlow: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color.cyan.opacity(0.075),
                    Color.green.opacity(0.070),
                    Color.clear
                ]
                : [
                    Color.white.opacity(0.32),
                    Color.cyan.opacity(0.10),
                    Color.green.opacity(0.09)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct MealScannerCapabilityPill: View {
    var title: String
    var symbolName: String
    var tint: Color

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Label(title, systemImage: symbolName)
            .pulsarTextStyle(.overline)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .foregroundStyle(tint.opacity(colorScheme == .dark ? 0.92 : 0.96))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(colorScheme == .dark ? 0.14 : 0.11), in: Capsule(style: .continuous))
    }
}

private struct MealScannerEntryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .brightness(configuration.isPressed ? 0.04 : 0)
            .animation(.spring(response: 0.26, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

#Preview {
    MealScannerEntryCard {}
        .padding()
        .background(PulsarSectionBackground())
}
