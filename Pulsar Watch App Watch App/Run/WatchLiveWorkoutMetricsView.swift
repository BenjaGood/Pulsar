//
//  WatchLiveWorkoutMetricsView.swift
//  Pulsar Watch App Watch App
//

import SwiftUI
import WatchKit

struct WatchLiveWorkoutMetricsView: View {
    var presentation: PulsarWatchLiveWorkoutPresentation
    var displayTitle: String
    var onShowNowPlaying: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let layout = WatchLiveWorkoutLayout(size: proxy.size)

            VStack(alignment: .leading, spacing: layout.sectionSpacing) {
                WatchLiveWorkoutHeader(
                    symbolName: presentation.workoutSymbolName,
                    layout: layout,
                    onShowNowPlaying: onShowNowPlaying
                )

                Text(displayTitle)
                    .font(.system(size: layout.titleSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .frame(height: layout.titleLineHeight, alignment: .leading)

                WatchLiveWorkoutTimer(
                    elapsedTimeText: presentation.elapsedTimeText,
                    statusText: presentation.statusText,
                    state: presentation.timerState,
                    layout: layout
                )

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: layout.gridSpacing), GridItem(.flexible(), spacing: layout.gridSpacing)],
                    spacing: layout.gridSpacing
                ) {
                    ForEach(presentation.metrics) { metric in
                        if case .heartRateZone(let zone) = metric.kind {
                            WatchLiveHeartRateZoneCard(metric: metric, activeZone: zone, layout: layout)
                        } else {
                            WatchLiveMetricCard(metric: metric, layout: layout)
                        }
                    }
                }
            }
            .padding(.horizontal, layout.horizontalInset)
            .padding(.top, layout.topBreathingRoom)
            .padding(.bottom, layout.bottomBreathingRoom)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct WatchLiveWorkoutLayout {
    var size: CGSize

    var isCompact: Bool {
        size.width < 180 || size.height < 215
    }

    var horizontalInset: CGFloat { isCompact ? 8 : 10 }
    private var isExpansive: Bool {
        size.height > 270
    }

    var topBreathingRoom: CGFloat { isCompact ? 3 : 5 }
    var bottomBreathingRoom: CGFloat { isCompact ? 14 : 18 }
    var sectionSpacing: CGFloat { isCompact ? 4 : (isExpansive ? 8 : 6) }
    var gridSpacing: CGFloat { isCompact ? 5 : (isExpansive ? 8 : 7) }
    var controlDiameter: CGFloat { isCompact ? 25 : 27 }
    var titleSize: CGFloat { isCompact ? 19 : 21 }
    var titleLineHeight: CGFloat { isCompact ? 23 : 25 }
    var timerSize: CGFloat { isCompact ? 27 : 30 }
    var timerLineHeight: CGFloat { isCompact ? 32 : 35 }
    var cardCornerRadius: CGFloat { isCompact ? 13 : 14 }
    var cardPadding: CGFloat { isCompact ? 6 : 7 }
    var cardLabelSize: CGFloat { isCompact ? 9 : 10 }
    var cardValueSize: CGFloat { isCompact ? 19 : 21 }
    var cardUnitSize: CGFloat { isCompact ? 9 : 10 }

    var cardHeight: CGFloat {
        let chromeHeight = controlDiameter + titleLineHeight + timerLineHeight + (sectionSpacing * 3) + gridSpacing + topBreathingRoom + bottomBreathingRoom
        let availableCardHeight = (size.height - chromeHeight) / 2
        if isCompact {
            return max(38, availableCardHeight)
        }
        return max(44, availableCardHeight)
    }

    var accentLime: Color {
        Color(red: 0.70, green: 0.95, blue: 0.12)
    }
}

private struct WatchLiveWorkoutHeader: View {
    var symbolName: String
    var layout: WatchLiveWorkoutLayout
    var onShowNowPlaying: () -> Void

    var body: some View {
        HStack {
            Image(systemName: symbolName)
                .font(.system(size: layout.isCompact ? 14 : 15, weight: .bold))
                .foregroundStyle(layout.accentLime)
                .frame(width: layout.controlDiameter, height: layout.controlDiameter)
                .background(layout.accentLime.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            Spacer()

            Button("Now Playing", systemImage: "ellipsis", action: onShowNowPlaying)
                .labelStyle(.iconOnly)
                .font(.system(size: layout.isCompact ? 13 : 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.74))
                .buttonStyle(.plain)
                .frame(width: layout.controlDiameter, height: layout.controlDiameter)
                .background(.white.opacity(0.06), in: Circle())
                .overlay {
                    Circle().stroke(.white.opacity(0.08), lineWidth: 0.5)
                }
                .accessibilityHint("Opens Now Playing")
        }
        .frame(height: layout.controlDiameter)
    }
}

private struct WatchLiveWorkoutTimer: View {
    var elapsedTimeText: String
    var statusText: String
    var state: PulsarWatchLiveWorkoutPresentation.TimerState
    var layout: WatchLiveWorkoutLayout

    private var tint: Color {
        switch state {
        case .active: layout.accentLime
        case .paused: .orange
        case .pending: .secondary
        }
    }

    private var symbolName: String {
        switch state {
        case .active: "play.fill"
        case .paused: "pause.fill"
        case .pending: "clock.fill"
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: layout.isCompact ? 5 : 6) {
            Image(systemName: symbolName)
                .font(.system(size: layout.isCompact ? 12 : 13, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: layout.isCompact ? 18 : 20, height: layout.isCompact ? 18 : 20)
                .background(tint.opacity(0.13), in: Circle())
                .accessibilityHidden(true)
            Text(elapsedTimeText)
                .font(.system(size: layout.timerSize, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Elapsed time \(elapsedTimeText), \(statusText)")
        .frame(height: layout.timerLineHeight, alignment: .leading)
    }
}

private struct WatchLiveMetricCard: View {
    var metric: PulsarWatchLiveWorkoutMetric
    var layout: WatchLiveWorkoutLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader
            Spacer(minLength: 1)
            Text(metric.value)
                .font(.system(size: layout.cardValueSize, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.54)
            if let unit = metric.unit {
                Text(unit)
                    .font(.system(size: layout.cardUnitSize, weight: .semibold, design: .default))
                    .foregroundStyle(metric.accent.color.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(layout.cardPadding)
        .frame(maxWidth: .infinity, minHeight: layout.cardHeight, maxHeight: layout.cardHeight, alignment: .leading)
        .watchLiveCardSurface(accent: metric.accent.color, radius: layout.cardCornerRadius)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var cardHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(metric.title.uppercased())
                .font(.system(size: layout.cardLabelSize, weight: .semibold, design: .default))
                .tracking(0.35)
                .foregroundStyle(.white.opacity(0.54))
                .lineLimit(1)
                .minimumScaleFactor(0.62)
            Spacer(minLength: 1)
            Image(systemName: metric.symbolName)
                .font(.system(size: layout.isCompact ? 11 : 12, weight: .semibold))
                .foregroundStyle(metric.accent.color.opacity(0.92))
                .accessibilityHidden(true)
        }
    }

    private var accessibilityLabel: String {
        [metric.title, metric.value, metric.unit].compactMap { $0 }.joined(separator: " ")
    }
}

private struct WatchLiveHeartRateZoneCard: View {
    var metric: PulsarWatchLiveWorkoutMetric
    var activeZone: PulsarLiveHeartRateZoneProfile.Zone?
    var layout: WatchLiveWorkoutLayout

    private var accent: Color {
        activeZone.map { color(for: $0.number) } ?? .blue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("ZONE")
                    .font(.system(size: layout.cardLabelSize, weight: .semibold, design: .default))
                    .tracking(0.35)
                    .foregroundStyle(.white.opacity(0.54))
                Spacer(minLength: 1)
                Image(systemName: metric.symbolName)
                    .font(.system(size: layout.isCompact ? 11 : 12, weight: .semibold))
                    .foregroundStyle(accent.opacity(0.92))
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 1)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(metric.value)
                    .font(.system(size: layout.cardValueSize, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.56)
                Text(metric.detail ?? "Unavailable")
                    .font(.system(size: layout.cardUnitSize, weight: .semibold, design: .default))
                    .foregroundStyle(accent.opacity(0.86))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { number in
                    Capsule()
                        .fill(color(for: number).opacity(activeZone?.number == number ? 1 : 0.22))
                        .frame(maxWidth: .infinity, minHeight: activeZone?.number == number ? 8 : 4)
                        .accessibilityHidden(true)
                }
            }
            .padding(.top, layout.isCompact ? 2 : 3)
        }
        .padding(layout.cardPadding)
        .frame(maxWidth: .infinity, minHeight: layout.cardHeight, maxHeight: layout.cardHeight, alignment: .leading)
        .watchLiveCardSurface(accent: accent, radius: layout.cardCornerRadius)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate zone \(metric.value), \(metric.detail ?? "Unavailable")")
    }

    private func color(for zone: Int) -> Color {
        switch zone {
        case 1: Color(red: 0.40, green: 0.72, blue: 1.00)
        case 2: Color(red: 0.35, green: 0.84, blue: 0.39)
        case 3: Color(red: 1.00, green: 0.58, blue: 0.10)
        case 4: Color(red: 1.00, green: 0.35, blue: 0.18)
        default: Color(red: 0.96, green: 0.16, blue: 0.31)
        }
    }
}

private extension View {
    func watchLiveCardSurface(accent: Color, radius: CGFloat) -> some View {
        background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: radius))
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(accent.opacity(0.16))
                    .blur(radius: 11)
                    .frame(width: 42, height: 42)
                    .offset(x: 8, y: -8)
                    .accessibilityHidden(true)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .stroke(.white.opacity(0.07), lineWidth: 0.75)
            }
    }
}

private extension PulsarLiveWorkoutMetricAccent {
    var color: Color {
        switch self {
        case .activity, .time: Color(red: 0.70, green: 0.95, blue: 0.12)
        case .energy: Color(red: 1.00, green: 0.34, blue: 0.12)
        case .heartRate: Color(red: 1.00, green: 0.25, blue: 0.18)
        case .zone: Color(red: 0.40, green: 0.72, blue: 1.00)
        case .distance: .cyan
        case .pace, .cadence: .mint
        }
    }
}
