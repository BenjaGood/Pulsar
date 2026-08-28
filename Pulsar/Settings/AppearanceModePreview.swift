//
//  AppearanceModePreview.swift
//  Pulsar
//

import SwiftUI

struct AppearanceModePreview: View {
    var mode: HomeBackgroundMode

    var body: some View {
        ZStack {
            switch mode {
            case .automatic:
                LinearGradient(
                    stops: [
                        .init(color: .white, location: 0.00),
                        .init(color: Color(white: 0.98), location: 0.38),
                        .init(color: Color(white: 0.44), location: 0.50),
                        .init(color: Color(white: 0.09), location: 0.64),
                        .init(color: Color(white: 0.06), location: 1.00)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            case .morning, .day:
                Color.white
            case .sunset, .night, .minimalDark:
                Color(white: 0.06)
            }

            Canvas { context, size in
                var upperWave = Path()
                upperWave.move(to: CGPoint(x: -size.width * 0.08, y: size.height * 0.56))
                upperWave.addCurve(
                    to: CGPoint(x: size.width * 1.08, y: size.height * 0.66),
                    control1: CGPoint(x: size.width * 0.23, y: size.height * 0.88),
                    control2: CGPoint(x: size.width * 0.70, y: size.height * 0.34)
                )
                upperWave.addLine(to: CGPoint(x: size.width * 1.08, y: size.height * 1.08))
                upperWave.addLine(to: CGPoint(x: -size.width * 0.08, y: size.height * 1.08))
                upperWave.closeSubpath()

                context.fill(
                    upperWave,
                    with: .linearGradient(
                        Gradient(colors: upperWaveColors),
                        startPoint: CGPoint(x: 0, y: size.height * 0.45),
                        endPoint: CGPoint(x: size.width, y: size.height)
                    )
                )

                var lowerWave = Path()
                lowerWave.move(to: CGPoint(x: -size.width * 0.08, y: size.height * 0.78))
                lowerWave.addCurve(
                    to: CGPoint(x: size.width * 1.08, y: size.height * 0.72),
                    control1: CGPoint(x: size.width * 0.26, y: size.height * 0.48),
                    control2: CGPoint(x: size.width * 0.68, y: size.height * 1.02)
                )
                lowerWave.addLine(to: CGPoint(x: size.width * 1.08, y: size.height * 1.08))
                lowerWave.addLine(to: CGPoint(x: -size.width * 0.08, y: size.height * 1.08))
                lowerWave.closeSubpath()

                context.fill(
                    lowerWave,
                    with: .linearGradient(
                        Gradient(colors: lowerWaveColors),
                        startPoint: CGPoint(x: 0, y: size.height * 0.58),
                        endPoint: CGPoint(x: size.width, y: size.height)
                    )
                )
            }
            .blur(radius: 0.8)

            if mode == .automatic {
                HStack(spacing: 0) {
                    AppearanceRingMotif(diameter: 12, spacing: 5)
                        .frame(maxWidth: .infinity)

                    AppearanceRingMotif(diameter: 12, spacing: 5)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 5)
            } else {
                AppearanceRingMotif(diameter: 22, spacing: 16)
            }
        }
        .clipShape(.rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.black.opacity(mode == .automatic || mode == .day ? 0.045 : 0.16), lineWidth: 0.7)
        }
        .accessibilityHidden(true)
    }

    private var upperWaveColors: [Color] {
        switch mode {
        case .automatic:
            [
                Color.black.opacity(0.05),
                Color.white.opacity(0.035),
                Color.black.opacity(0.16)
            ]
        case .morning, .day:
            [
                Color.black.opacity(0.04),
                Color.black.opacity(0.10)
            ]
        case .sunset, .night, .minimalDark:
            [
                Color.white.opacity(0.025),
                Color.white.opacity(0.12)
            ]
        }
    }

    private var lowerWaveColors: [Color] {
        switch mode {
        case .automatic:
            [
                Color.white.opacity(0.12),
                Color.black.opacity(0.07),
                Color.white.opacity(0.045)
            ]
        case .morning, .day:
            [
                Color.black.opacity(0.08),
                Color.black.opacity(0.03)
            ]
        case .sunset, .night, .minimalDark:
            [
                Color.white.opacity(0.18),
                Color.black.opacity(0.22)
            ]
        }
    }
}
