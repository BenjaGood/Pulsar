//
//  ECGHeartbeatView.swift
//  Pulsar
//

import SwiftUI

struct WorkoutStartPulseLineView: View {
    var drawProgress: CGFloat
    var glowAmount: Double
    var tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var energyProgress: CGFloat = 0.0
    @State private var beatBreath = false

    var body: some View {
        GeometryReader { proxy in
            let pulseLift = CGFloat(glowAmount) * 0.035 + (beatBreath ? 0.018 : 0)
            ZStack {
                CinematicHeartbeatLineShape()
                    .trim(from: 0, to: 1)
                    .stroke(
                        Color.white.opacity(0.08),
                        style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round)
                    )

                CinematicHeartbeatLineShape()
                    .trim(from: 0, to: clampedProgress)
                    .stroke(
                        tint.opacity(0.34 + glowAmount * 0.26),
                        style: StrokeStyle(lineWidth: 24, lineCap: .round, lineJoin: .round)
                    )
                    .blur(radius: 20)
                    .opacity(0.68 + glowAmount * 0.16)

                CinematicHeartbeatLineShape()
                    .trim(from: 0, to: clampedProgress)
                    .stroke(
                        Color.white.opacity(0.16 + glowAmount * 0.22),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round)
                    )
                    .blur(radius: 6)

                CinematicHeartbeatLineShape()
                    .trim(from: 0, to: clampedProgress)
                    .stroke(lineGradient, style: StrokeStyle(lineWidth: 2.15, lineCap: .round, lineJoin: .round))
                    .shadow(color: tint.opacity(0.22 + glowAmount * 0.26), radius: 14 + glowAmount * 14)
                    .shadow(color: .white.opacity(0.18 + glowAmount * 0.20), radius: 5 + glowAmount * 5)

                CinematicHeartbeatLineShape()
                    .trim(from: highlightStart, to: highlightEnd)
                    .stroke(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.24), .white, tint.opacity(0.80), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round)
                    )
                    .blur(radius: 0.35)
                    .shadow(color: .white.opacity(0.26 + glowAmount * 0.18), radius: 10)

                CinematicHeartbeatLineShape()
                    .trim(from: highlightStart, to: highlightEnd)
                    .stroke(
                        tint.opacity(0.30 + glowAmount * 0.30),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round)
                    )
                    .blur(radius: 14)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .scaleEffect(x: 1, y: 1 + pulseLift, anchor: .center)
        }
        .frame(height: 128)
        .drawingGroup()
        .onAppear {
            guard !reduceMotion else { return }
            energyProgress = 0.0
            withAnimation(.linear(duration: 1.42).repeatForever(autoreverses: false)) {
                energyProgress = 1.18
            }
            withAnimation(.easeInOut(duration: 0.86).repeatForever(autoreverses: true)) {
                beatBreath = true
            }
        }
    }

    private var clampedProgress: CGFloat {
        max(0, min(drawProgress, 1))
    }

    private var highlightStart: CGFloat {
        guard !reduceMotion else { return max(0, clampedProgress - 0.18) }
        return max(0, min(clampedProgress, energyProgress - 0.16))
    }

    private var highlightEnd: CGFloat {
        guard !reduceMotion else { return clampedProgress }
        return max(highlightStart, min(clampedProgress, energyProgress + 0.035))
    }

    private var lineGradient: LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(0.08),
                .white.opacity(0.70),
                .white,
                .white.opacity(0.76),
                .white.opacity(0.10)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct WorkoutStartAmbientBackground: View {
    var tint: Color
    var opacity: Double
    var rhythmGlow: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDrifting = false
    @State private var ribbonShift = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    tint.opacity(0.78),
                    tint.opacity(0.42),
                    Color(red: 0.02, green: 0.02, blue: 0.04),
                    .black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [tint.opacity(0.52), .clear],
                        center: .center,
                        startRadius: 12,
                        endRadius: 300
                    )
                )
                .frame(width: 620, height: 620)
                .blur(radius: 40)
                .offset(x: isDrifting ? 120 : 56, y: isDrifting ? -210 : -150)
                .scaleEffect(isDrifting ? 1.08 : 0.98)

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.14 + rhythmGlow * 0.06), tint.opacity(0.22 + rhythmGlow * 0.14), .clear],
                        center: .center,
                        startRadius: 4,
                        endRadius: 280
                    )
                )
                .frame(width: 720, height: 380)
                .blur(radius: 46)
                .rotationEffect(.degrees(ribbonShift ? -7 : 10))
                .offset(x: ribbonShift ? -58 : 48, y: ribbonShift ? 92 : 132)
                .blendMode(.screen)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.18), tint.opacity(0.18), .clear],
                        center: .center,
                        startRadius: 8,
                        endRadius: 250
                    )
                )
                .frame(width: 520, height: 520)
                .blur(radius: 54)
                .offset(x: isDrifting ? -146 : -92, y: isDrifting ? 292 : 228)
                .scaleEffect(isDrifting ? 1.04 : 0.96)

            LinearGradient(
                colors: [
                    .clear,
                    .white.opacity(0.10 + rhythmGlow * 0.08),
                    tint.opacity(0.08 + rhythmGlow * 0.10),
                    .clear
                ],
                startPoint: ribbonShift ? .topLeading : .leading,
                endPoint: ribbonShift ? .bottomTrailing : .trailing
            )
            .blur(radius: 28)
            .blendMode(.screen)

            LinearGradient(
                colors: [
                    .white.opacity(0.14),
                    .clear,
                    .white.opacity(0.05),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.screen)
            .blur(radius: 36)

            Color.black.opacity(0.18)
        }
        .opacity(opacity)
        .ignoresSafeArea()
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
                isDrifting = true
            }
            withAnimation(.easeInOut(duration: 4.8).repeatForever(autoreverses: true)) {
                ribbonShift = true
            }
        }
    }
}

private struct CinematicHeartbeatLineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let baseline = rect.minY + rect.height * 0.56

        path.move(to: CGPoint(x: rect.minX, y: baseline))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.18, y: baseline),
            control1: CGPoint(x: rect.minX + rect.width * 0.06, y: baseline - rect.height * 0.010),
            control2: CGPoint(x: rect.minX + rect.width * 0.12, y: baseline + rect.height * 0.012)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.29, y: baseline - rect.height * 0.09),
            control1: CGPoint(x: rect.minX + rect.width * 0.22, y: baseline + rect.height * 0.006),
            control2: CGPoint(x: rect.minX + rect.width * 0.24, y: baseline - rect.height * 0.10)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.39, y: baseline),
            control1: CGPoint(x: rect.minX + rect.width * 0.33, y: baseline - rect.height * 0.09),
            control2: CGPoint(x: rect.minX + rect.width * 0.35, y: baseline)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.435, y: baseline + rect.height * 0.17),
            control1: CGPoint(x: rect.minX + rect.width * 0.408, y: baseline + rect.height * 0.02),
            control2: CGPoint(x: rect.minX + rect.width * 0.418, y: baseline + rect.height * 0.15)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.485, y: baseline - rect.height * 0.44),
            control1: CGPoint(x: rect.minX + rect.width * 0.455, y: baseline + rect.height * 0.20),
            control2: CGPoint(x: rect.minX + rect.width * 0.462, y: baseline - rect.height * 0.43)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.535, y: baseline + rect.height * 0.24),
            control1: CGPoint(x: rect.minX + rect.width * 0.505, y: baseline - rect.height * 0.42),
            control2: CGPoint(x: rect.minX + rect.width * 0.512, y: baseline + rect.height * 0.25)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.60, y: baseline),
            control1: CGPoint(x: rect.minX + rect.width * 0.552, y: baseline + rect.height * 0.22),
            control2: CGPoint(x: rect.minX + rect.width * 0.568, y: baseline)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.73, y: baseline - rect.height * 0.14),
            control1: CGPoint(x: rect.minX + rect.width * 0.642, y: baseline - rect.height * 0.02),
            control2: CGPoint(x: rect.minX + rect.width * 0.664, y: baseline - rect.height * 0.14)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.86, y: baseline),
            control1: CGPoint(x: rect.minX + rect.width * 0.79, y: baseline - rect.height * 0.14),
            control2: CGPoint(x: rect.minX + rect.width * 0.79, y: baseline)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: baseline),
            control1: CGPoint(x: rect.minX + rect.width * 0.91, y: baseline + rect.height * 0.012),
            control2: CGPoint(x: rect.minX + rect.width * 0.96, y: baseline - rect.height * 0.010)
        )

        return path
    }
}

#Preview {
    ZStack {
        WorkoutStartAmbientBackground(tint: WorkoutAccent.velocity.color, opacity: 1)
        WorkoutStartPulseLineView(drawProgress: 1, glowAmount: 0.5, tint: WorkoutAccent.velocity.color)
            .padding(.horizontal, 28)
    }
}
