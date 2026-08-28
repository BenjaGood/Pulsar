//
//  HealthMetricSignalShape.swift
//  Pulsar
//

import SwiftUI

@Animatable
struct HealthMetricSignalShape: Shape {
    @AnimatableIgnored var kind: HealthMetricKind
    var phase: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        let amplitude = rect.height * (0.20 + (phase * 0.08))

        switch kind {
        case .respiratoryRate:
            path.move(to: CGPoint(x: rect.minX, y: midY))
            path.addCurve(
                to: CGPoint(x: rect.midX, y: midY),
                control1: CGPoint(x: rect.width * 0.13, y: midY - amplitude),
                control2: CGPoint(x: rect.width * 0.34, y: midY - amplitude)
            )
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: midY),
                control1: CGPoint(x: rect.width * 0.66, y: midY + amplitude),
                control2: CGPoint(x: rect.width * 0.87, y: midY + amplitude)
            )

        case .restingHeartRate:
            path.move(to: CGPoint(x: rect.minX, y: midY))
            path.addLine(to: CGPoint(x: rect.width * 0.28, y: midY))
            path.addLine(to: CGPoint(x: rect.width * 0.39, y: midY - amplitude * 0.45))
            path.addLine(to: CGPoint(x: rect.width * 0.50, y: midY + amplitude))
            path.addLine(to: CGPoint(x: rect.width * 0.61, y: midY - amplitude))
            path.addLine(to: CGPoint(x: rect.width * 0.72, y: midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: midY))

        case .hrv:
            path.move(to: CGPoint(x: rect.minX, y: midY))
            for index in 1...6 {
                let x = rect.width * CGFloat(index) / 6
                let direction: CGFloat = index.isMultiple(of: 2) ? 1 : -1
                let variation = index.isMultiple(of: 3) ? 0.55 : 1
                path.addLine(to: CGPoint(x: x, y: midY + direction * amplitude * variation))
            }

        case .oxygenSaturation:
            path.move(to: CGPoint(x: rect.minX, y: midY + amplitude * 0.35))
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: midY - amplitude * 0.35),
                control1: CGPoint(x: rect.width * 0.34, y: midY - amplitude),
                control2: CGPoint(x: rect.width * 0.66, y: midY + amplitude)
            )

        case .wristTemperature:
            path.move(to: CGPoint(x: rect.minX, y: midY + amplitude * 0.75))
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: midY - amplitude * 0.75),
                control1: CGPoint(x: rect.width * 0.30, y: midY + amplitude * 0.65),
                control2: CGPoint(x: rect.width * 0.70, y: midY - amplitude * 0.65)
            )

        case .sleep:
            path.move(to: CGPoint(x: rect.minX, y: midY - amplitude * 0.4))
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: midY + amplitude * 0.4),
                control1: CGPoint(x: rect.width * 0.24, y: midY + amplitude),
                control2: CGPoint(x: rect.width * 0.76, y: midY - amplitude)
            )
        }

        return path
    }
}
