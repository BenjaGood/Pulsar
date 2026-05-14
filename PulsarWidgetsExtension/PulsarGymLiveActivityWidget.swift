//
//  PulsarGymLiveActivityWidget.swift
//  PulsarWidgetsExtension
//

import ActivityKit
import SwiftUI
import WidgetKit

@available(iOSApplicationExtension 16.1, *)
struct PulsarGymLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PulsarGymLiveActivityAttributes.self) { context in
            GymLiveActivityLockScreenView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    GymLiveActivityIslandLeading(state: context.state)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(WidgetGymFormatters.duration(context.state.elapsedSeconds))
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                DynamicIslandExpandedRegion(.center) {
                    Text(WidgetGymFormatters.routineTitle(context.state.routineName))
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .layoutPriority(1)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    GymLiveActivityIslandBottom(state: context.state)
                }
            } compactLeading: {
                if let routineEmoji = context.state.routineEmoji, !routineEmoji.isEmpty {
                    Text(routineEmoji)
                        .font(.caption.weight(.black))
                } else {
                    Image(systemName: "dumbbell.fill")
                        .foregroundStyle(Color(red: 0.78, green: 0.72, blue: 1.0))
                }
            } compactTrailing: {
                Text(WidgetGymFormatters.duration(context.state.elapsedSeconds))
                    .font(.caption2.weight(.black))
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(Color(red: 0.78, green: 0.72, blue: 1.0))
            }
        }
    }
}

private struct GymLiveActivityIslandLeading: View {
    var state: PulsarGymLiveActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 4) {
            if let routineEmoji = state.routineEmoji, !routineEmoji.isEmpty {
                Text(routineEmoji)
                    .font(.caption2.weight(.black))
            } else {
                Image(systemName: "dumbbell.fill")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(Color(red: 0.78, green: 0.72, blue: 1.0))
            }

            Text(WidgetGymFormatters.compactSetProgress(completed: state.completedSets, total: state.totalSets))
                .font(.caption2.weight(.black))
                .foregroundStyle(.white.opacity(0.84))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
    }
}

private struct GymLiveActivityLockScreenView: View {
    var state: PulsarGymLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.72, green: 0.66, blue: 1.0).opacity(0.20))
                    if let routineEmoji = state.routineEmoji, !routineEmoji.isEmpty {
                        Text(routineEmoji)
                            .font(.headline.weight(.black))
                    } else {
                        Image(systemName: "dumbbell.fill")
                            .font(.headline.weight(.black))
                            .foregroundStyle(Color(red: 0.78, green: 0.72, blue: 1.0))
                    }
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(WidgetGymFormatters.routineTitle(state.routineName))
                        .font(.headline.weight(.black))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(WidgetGymFormatters.exerciseTitle(state.currentExerciseName))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .layoutPriority(1)

                Spacer(minLength: 0)

                Text(WidgetGymFormatters.duration(state.elapsedSeconds))
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)
            }

            GymLiveActivityProgressLine(state: state, style: .lockScreen)
        }
        .padding(16)
        .activityBackgroundTint(Color(red: 0.04, green: 0.03, blue: 0.08))
        .activitySystemActionForegroundColor(Color(red: 0.78, green: 0.72, blue: 1.0))
    }
}

private struct GymLiveActivityIslandBottom: View {
    var state: PulsarGymLiveActivityAttributes.ContentState

    var body: some View {
        GymLiveActivityProgressLine(state: state, style: .dynamicIsland)
            .padding(.top, 1)
    }
}

private struct GymLiveActivityProgressLine: View {
    enum Style {
        case dynamicIsland
        case lockScreen
    }

    var state: PulsarGymLiveActivityAttributes.ContentState
    var style: Style = .dynamicIsland

    var body: some View {
        VStack(alignment: .leading, spacing: style == .dynamicIsland ? 5 : 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(WidgetGymFormatters.exerciseTitle(state.currentExerciseName))
                    .font(style == .dynamicIsland ? .caption2.weight(.black) : .caption.weight(.black))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .layoutPriority(1)

                Spacer(minLength: 4)

                Text(WidgetGymFormatters.setProgress(completed: state.completedSets, total: state.totalSets))
                    .font(.caption2.weight(.black))
                    .foregroundStyle(Color(red: 0.78, green: 0.72, blue: 1.0))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            GymLiveActivityProgressBar(progress: WidgetGymFormatters.progress(completed: state.completedSets, total: state.totalSets))

            if showsMetricsRow {
                metricsRow
            }
        }
        .padding(style == .dynamicIsland ? 8 : 10)
        .background(Color.white.opacity(style == .dynamicIsland ? 0.06 : 0.08), in: RoundedRectangle(cornerRadius: style == .dynamicIsland ? 14 : 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: style == .dynamicIsland ? 14 : 16, style: .continuous)
                .stroke(Color.white.opacity(style == .dynamicIsland ? 0.10 : 0.12), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var metricsRow: some View {
        HStack(spacing: 6) {
            if let restText {
                GymLiveActivityMetricPill(symbol: "timer", text: restText, tint: Color(red: 0.78, green: 0.72, blue: 1.0))
            } else if state.totalExercises > 0 {
                Text(state.exerciseProgressText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 2)

            if let heartRateText = WidgetGymFormatters.heartRateText(state.heartRate) {
                GymLiveActivityMetricPill(symbol: "heart.fill", text: heartRateText, tint: Color(red: 1.0, green: 0.42, blue: 0.56))
            }

            if let caloriesText = WidgetGymFormatters.caloriesText(state.activeEnergyKilocalories) {
                GymLiveActivityMetricPill(symbol: "flame.fill", text: caloriesText, tint: Color(red: 1.0, green: 0.72, blue: 0.34))
            }
        }
        .frame(minHeight: 18)
    }

    private var showsMetricsRow: Bool {
        restText != nil ||
            state.totalExercises > 0 ||
            WidgetGymFormatters.heartRateText(state.heartRate) != nil ||
            WidgetGymFormatters.caloriesText(state.activeEnergyKilocalories) != nil
    }

    private var restText: String? {
        guard let remaining = state.restRemainingSeconds, remaining > 0 else { return nil }
        return "Rest \(WidgetGymFormatters.duration(remaining))"
    }
}

private struct GymLiveActivityProgressBar: View {
    var progress: Double

    var body: some View {
        GeometryReader { proxy in
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.14))
                .overlay(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.78, green: 0.72, blue: 1.0),
                                    Color(red: 0.52, green: 0.84, blue: 1.0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: progress > 0 ? max(4, proxy.size.width * progress) : 0)
                }
        }
        .frame(height: 4)
    }
}

private struct GymLiveActivityMetricPill: View {
    var symbol: String
    var text: String
    var tint: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption2.weight(.black))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .labelStyle(.titleAndIcon)
    }
}

private enum WidgetGymFormatters {
    static func routineTitle(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Gym Workout" }
        if trimmed.localizedCaseInsensitiveContains("empty gym") {
            return "Gym Workout"
        }
        return trimmed
    }

    static func exerciseTitle(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Open gym session" }
        if trimmed.localizedCaseInsensitiveContains("open gym") {
            return "Open gym session"
        }
        return trimmed
    }

    static func duration(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3_600
        let minutes = (clamped % 3_600) / 60
        let seconds = clamped % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func setProgress(completed: Int, total: Int) -> String {
        let completed = max(0, completed)
        let total = max(0, total)
        guard total > 0 else { return "\(completed) sets" }
        return "\(min(completed, total))/\(total) sets"
    }

    static func compactSetProgress(completed: Int, total: Int) -> String {
        let completed = max(0, completed)
        let total = max(0, total)
        guard total > 0 else { return completed > 0 ? "\(completed)" : "Gym" }
        return "\(min(completed, total))/\(total)"
    }

    static func progress(completed: Int, total: Int) -> Double {
        let total = max(0, total)
        guard total > 0 else { return 0 }
        return min(max(Double(completed) / Double(total), 0), 1)
    }

    static func heartRateText(_ bpm: Double?) -> String? {
        guard let bpm, bpm > 0 else { return nil }
        return "\(Int(bpm.rounded())) bpm"
    }

    static func caloriesText(_ activeEnergyKilocalories: Double?) -> String? {
        guard let activeEnergyKilocalories, activeEnergyKilocalories > 0 else { return nil }
        return "\(Int(activeEnergyKilocalories.rounded())) kcal"
    }
}
