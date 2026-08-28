import SwiftUI

struct SleepBalanceIndicator: View {
    var stage: SleepStage
    var percent: Double
    var minutes: Double

    var body: some View {
        Canvas { context, size in
            let midpoint = size.height / 2
            let trackStart = CGPoint(x: 1.5, y: midpoint)
            let trackEnd = CGPoint(x: max(1.5, size.width - 1.5), y: midpoint)
            var track = Path()
            track.move(to: trackStart)
            track.addLine(to: trackEnd)
            context.stroke(
                track,
                with: .color(.secondary.opacity(0.10)),
                lineWidth: 1
            )

            for tickPosition in [CGFloat.zero, 0.5, 1] {
                let tickCenter = CGPoint(
                    x: 1.5 + ((size.width - 3) * tickPosition),
                    y: midpoint
                )
                let tick = CGRect(
                    x: tickCenter.x - 1.5,
                    y: tickCenter.y - 1.5,
                    width: 3,
                    height: 3
                )
                context.fill(
                    Path(ellipseIn: tick),
                    with: .color(.secondary.opacity(0.14))
                )
            }

            let dotRadius: CGFloat = 4
            let availableWidth = max(0, size.width - (dotRadius * 2))
            let dotCenterX = dotRadius + (availableWidth * normalizedPosition)
            let dot = CGRect(
                x: dotCenterX - dotRadius,
                y: midpoint - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            )
            context.fill(
                Path(ellipseIn: dot),
                with: .color(SleepStageVisualStyle.color(for: stage))
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: 10)
        .accessibilityLabel("\(balanceDescription) range")
    }

    private var normalizedPosition: CGFloat {
        let value: Double
        switch stage {
        case .deep:
            value = percent / 0.30
        case .rem:
            value = percent / 0.35
        case .core, .asleepUnspecified:
            value = (percent - 0.35) / 0.35
        case .awake:
            value = minutes / 60
        case .inBed:
            value = 0.5
        }
        return CGFloat(min(max(value, 0), 1))
    }

    private var balanceDescription: String {
        let lowerBound: Double
        let upperBound: Double
        let value: Double

        switch stage {
        case .deep:
            (lowerBound, upperBound, value) = (0.13, 0.23, percent)
        case .rem:
            (lowerBound, upperBound, value) = (0.20, 0.27, percent)
        case .core, .asleepUnspecified:
            (lowerBound, upperBound, value) = (0.45, 0.60, percent)
        case .awake:
            (lowerBound, upperBound, value) = (0, 30, minutes)
        case .inBed:
            return "Optimal"
        }

        if value < lowerBound { return "Low" }
        if value > upperBound { return "High" }
        return "Optimal"
    }
}
