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
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.state.routineName)
                            .font(.caption.weight(.black))
                            .lineLimit(1)
                        Text(context.state.progressText)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(WidgetGymFormatters.duration(context.state.elapsedSeconds))
                            .font(.caption.weight(.black))
                            .monospacedDigit()
                        Label(WidgetGymFormatters.heartRate(context.state.heartRate), systemImage: "heart.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.56))
                        Label(WidgetGymFormatters.calories(context.state.activeEnergyKilocalories), systemImage: "flame.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.34))
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    GymLiveActivityProgressLine(state: context.state)
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(Color(red: 0.78, green: 0.72, blue: 1.0))
            } compactTrailing: {
                Text(WidgetGymFormatters.heartRate(context.state.heartRate))
                    .font(.caption2.weight(.black))
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "heart.fill")
                    .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.56))
            }
        }
    }
}

private struct GymLiveActivityLockScreenView: View {
    var state: PulsarGymLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.72, green: 0.66, blue: 1.0).opacity(0.20))
                    Image(systemName: "dumbbell.fill")
                        .font(.headline.weight(.black))
                        .foregroundStyle(Color(red: 0.78, green: 0.72, blue: 1.0))
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text(state.routineName)
                        .font(.headline.weight(.black))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(state.currentExerciseName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(WidgetGymFormatters.duration(state.elapsedSeconds))
                        .font(.headline.weight(.black))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Label(WidgetGymFormatters.heartRate(state.heartRate), systemImage: "heart.fill")
                        .font(.caption.weight(.black))
                        .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.56))
                    Label(WidgetGymFormatters.calories(state.activeEnergyKilocalories), systemImage: "flame.fill")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.34))
                }
            }

            GymLiveActivityProgressLine(state: state)
        }
        .padding(16)
        .activityBackgroundTint(Color(red: 0.04, green: 0.03, blue: 0.08))
        .activitySystemActionForegroundColor(Color(red: 0.78, green: 0.72, blue: 1.0))
    }
}

private struct GymLiveActivityProgressLine: View {
    var state: PulsarGymLiveActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(state.progressText)
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                Text(restText ?? state.exerciseProgressText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.58))
            }

            Spacer(minLength: 0)

            if let restText {
                Text(restText)
                    .font(.caption.weight(.black))
                    .foregroundStyle(Color(red: 0.78, green: 0.72, blue: 1.0))
                    .monospacedDigit()
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
    }

    private var restText: String? {
        guard let remaining = state.restRemainingSeconds, remaining > 0 else { return nil }
        return "Rest \(WidgetGymFormatters.duration(remaining))"
    }
}

private enum WidgetGymFormatters {
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

    static func heartRate(_ bpm: Double?) -> String {
        guard let bpm, bpm > 0 else { return "--" }
        return "\(Int(bpm.rounded()))"
    }

    static func calories(_ activeEnergyKilocalories: Double?) -> String {
        guard let activeEnergyKilocalories, activeEnergyKilocalories > 0 else { return "-- kcal" }
        return "\(Int(activeEnergyKilocalories.rounded())) kcal"
    }
}
