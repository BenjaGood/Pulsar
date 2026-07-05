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
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.green.opacity(colorScheme == .dark ? 0.10 : 0.08))

            IsometricCubeScannerGlyph(
                progress: isBreathing && !reduceMotion ? 1 : 0,
                tint: .green
            )
            .padding(7)
        }
        .frame(width: 72, height: 72)
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
                    Color.cyan.opacity(0.035),
                    Color.green.opacity(0.032),
                    Color.clear
                ]
                : [
                    Color.white.opacity(0.18),
                    Color.cyan.opacity(0.045),
                    Color.green.opacity(0.04)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct IsometricCubeScannerGlyph: View {
    var progress: Double
    var tint: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let center = CGPoint(x: width * 0.5, y: height * 0.52)
            let top = CGPoint(x: center.x, y: height * 0.24)
            let left = CGPoint(x: width * 0.24, y: height * 0.40)
            let right = CGPoint(x: width * 0.76, y: height * 0.40)
            let bottom = CGPoint(x: center.x, y: height * 0.72)
            let pulseOpacity = 0.18 + progress * 0.24

            ZStack {
                scannerCorner(at: .topLeading, width: width, height: height)
                scannerCorner(at: .topTrailing, width: width, height: height)
                scannerCorner(at: .bottomLeading, width: width, height: height)
                scannerCorner(at: .bottomTrailing, width: width, height: height)

                Path { path in
                    path.move(to: top)
                    path.addLine(to: right)
                    path.addLine(to: bottom)
                    path.addLine(to: left)
                    path.closeSubpath()
                }
                .stroke(
                    LinearGradient(colors: [tint, .cyan.opacity(0.88)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 3, lineJoin: .round)
                )

                Path { path in
                    path.move(to: top)
                    path.addLine(to: center)
                    path.addLine(to: bottom)
                    path.move(to: left)
                    path.addLine(to: center)
                    path.addLine(to: right)
                }
                .stroke(tint.opacity(0.78), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

                Path { path in
                    path.move(to: center)
                    path.addLine(to: CGPoint(x: center.x, y: height * 0.90))
                }
                .stroke(tint.opacity(pulseOpacity), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .scaleEffect(x: 1, y: 1 + progress * 0.08, anchor: .top)
            }
        }
    }

    private enum Corner {
        case topLeading
        case topTrailing
        case bottomLeading
        case bottomTrailing
    }

    private func scannerCorner(at corner: Corner, width: CGFloat, height: CGFloat) -> some View {
        Path { path in
            let inset = min(width, height) * 0.08
            let length = min(width, height) * 0.17
            switch corner {
            case .topLeading:
                path.move(to: CGPoint(x: inset, y: inset + length))
                path.addLine(to: CGPoint(x: inset, y: inset))
                path.addLine(to: CGPoint(x: inset + length, y: inset))
            case .topTrailing:
                path.move(to: CGPoint(x: width - inset - length, y: inset))
                path.addLine(to: CGPoint(x: width - inset, y: inset))
                path.addLine(to: CGPoint(x: width - inset, y: inset + length))
            case .bottomLeading:
                path.move(to: CGPoint(x: inset, y: height - inset - length))
                path.addLine(to: CGPoint(x: inset, y: height - inset))
                path.addLine(to: CGPoint(x: inset + length, y: height - inset))
            case .bottomTrailing:
                path.move(to: CGPoint(x: width - inset - length, y: height - inset))
                path.addLine(to: CGPoint(x: width - inset, y: height - inset))
                path.addLine(to: CGPoint(x: width - inset, y: height - inset - length))
            }
        }
        .stroke(.white.opacity(0.82), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
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
