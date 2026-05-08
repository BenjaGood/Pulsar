//
//  ECGHeartbeatView.swift
//  Pulsar
//

import SwiftUI

struct ECGHeartbeatView: View {
    var drawProgress: CGFloat
    var spikeGlow: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Circle()
                .fill(radialCore)
                .frame(width: 240, height: 240)
                .blur(radius: 6)

            Circle()
                .stroke(.white.opacity(0.08), lineWidth: 1)
                .frame(width: 226, height: 226)

            Image(systemName: "heart.fill")
                .font(.system(size: 142, weight: .black))
                .foregroundStyle(.white.opacity(colorScheme == .dark ? 0.075 : 0.10))
                .scaleEffect(spikeGlow ? 1.035 : 1)
                .animation(.spring(response: 0.24, dampingFraction: 0.62), value: spikeGlow)

            ECGLineShape()
                .trim(from: 0, to: max(0, min(drawProgress, 1)))
                .stroke(lineGradient, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                .frame(width: 250, height: 110)
                .shadow(color: Color(red: 1.0, green: 0.16, blue: 0.18).opacity(spikeGlow ? 0.95 : 0.46), radius: spikeGlow ? 20 : 10)
                .shadow(color: .white.opacity(spikeGlow ? 0.36 : 0.12), radius: spikeGlow ? 9 : 4)

            if spikeGlow {
                Circle()
                    .stroke(
                        Color(red: 1.0, green: 0.32, blue: 0.34).opacity(0.72),
                        style: StrokeStyle(lineWidth: 2)
                    )
                    .frame(width: 118, height: 118)
                    .blur(radius: 0.4)
                    .transition(.scale(scale: 0.55).combined(with: .opacity))
            }
        }
        .frame(width: 280, height: 280)
        .drawingGroup()
    }

    private var radialCore: RadialGradient {
        RadialGradient(
            colors: [
                Color.white.opacity(0.16),
                Color(red: 1.0, green: 0.12, blue: 0.16).opacity(0.24),
                Color(red: 0.30, green: 0.02, blue: 0.04).opacity(0.02)
            ],
            center: .center,
            startRadius: 12,
            endRadius: 124
        )
    }

    private var lineGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.72, blue: 0.70),
                .white,
                Color(red: 1.0, green: 0.17, blue: 0.22),
                Color(red: 1.0, green: 0.68, blue: 0.62)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

private struct ECGLineShape: Shape {
    func path(in rect: CGRect) -> Path {
        let points = [
            CGPoint(x: 0.00, y: 0.58),
            CGPoint(x: 0.17, y: 0.58),
            CGPoint(x: 0.22, y: 0.54),
            CGPoint(x: 0.27, y: 0.62),
            CGPoint(x: 0.32, y: 0.58),
            CGPoint(x: 0.42, y: 0.58),
            CGPoint(x: 0.49, y: 0.18),
            CGPoint(x: 0.54, y: 0.84),
            CGPoint(x: 0.60, y: 0.46),
            CGPoint(x: 0.66, y: 0.58),
            CGPoint(x: 1.00, y: 0.58)
        ]

        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: rect.minX + first.x * rect.width, y: rect.minY + first.y * rect.height))

        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height))
        }

        return path
    }
}

#Preview {
    ECGHeartbeatView(drawProgress: 1, spikeGlow: true)
        .padding()
        .background(Color.red)
}
