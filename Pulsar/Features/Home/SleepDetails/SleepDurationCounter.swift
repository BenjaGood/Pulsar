import SwiftUI

struct SleepDurationCounter: View {
    var totalMinutes: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var metricSize = 56
    @State private var animationStart = Date.now

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(animationStart))
            let progress = reduceMotion ? 1 : min(1, elapsed / 0.82)
            let easedProgress = 1 - pow(1 - progress, 3)
            let displayedMinutes = totalMinutes * easedProgress

            Text(SleepDetailsViewModel.durationText(minutes: displayedMinutes))
                .font(.system(size: metricSize, weight: .light, design: .default))
                .monospacedDigit()
                .contentTransition(.numericText(value: displayedMinutes))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .accessibilityLabel("Total sleep")
        .accessibilityValue(SleepDetailsViewModel.durationText(minutes: totalMinutes))
        .task { animationStart = .now }
    }
}
