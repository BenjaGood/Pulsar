import Foundation

struct NotificationContentBuilder {
    func postWorkoutContent(event: WorkoutNotificationEvent, dashboard: HomeDashboard) -> PulsarNotificationPayload {
        let duration = durationText(minutes: event.durationMinutes)
        let type = event.workoutType.lowercased()
        let strain = strainPhrase(dashboard.strain)
        let recovery = recoveryPhrase(dashboard.recovery, strain: dashboard.strain)
        let metrics = workoutMetricsPhrase(event)
        let body = compactSentence([
            "\(duration) \(type) logged",
            metrics,
            strain,
            recovery
        ])

        return .immediate(
            identifier: "pulsar.notification.postWorkout.\(event.id)",
            category: .postWorkout,
            title: "Workout complete",
            body: body
        )
    }

    func highStressContent(stress: StressSummary) -> PulsarNotificationPayload {
        let drivers = stressDrivers(from: stress)
        let driverText = drivers.isEmpty ? "Based on available wearable data." : drivers.joined(separator: " and ") + " may be contributing."
        return .immediate(
            identifier: "pulsar.notification.highStress",
            category: .highStress,
            title: "Stress is running high",
            body: "Your physiological load appears elevated. \(driverText)"
        )
    }

    func windDownContent(profile: UserProfile, dashboard: HomeDashboard) -> PulsarNotificationPayload {
        let schedule = profile.sleepSchedule
        var context: [String] = []

        if dashboard.stress.confidence != .low,
           dashboard.stress.confidence != .missing,
           let level = dashboard.stress.level,
           level == .high || level == .elevated {
            context.append("stress is \(level == .elevated ? "elevated" : "running high")")
        }

        if dashboard.strain.confidence != .missing, dashboard.strain.score >= 70 {
            context.append("strain was high today")
        } else if dashboard.strain.confidence != .missing, dashboard.strain.score >= 50 {
            context.append("strain was moderate today")
        }

        let opening = context.isEmpty ? "A steady wind-down can help tonight" : sentenceCased(context.joined(separator: " and "))
        var body = "\(opening). Aim for \(sleepGoalText(minutes: schedule.targetSleepDurationMinutes)) of sleep"

        if schedule.alarmEnabled {
            body += " - your alarm is set for \(timeText(minutesFromMidnight: schedule.resolvedAlarmTimeMinutesFromMidnight))."
        } else {
            body += "."
        }

        return PulsarNotificationPayload(
            identifier: "pulsar.notification.windDown",
            category: .windDown,
            title: "Wind down for sleep",
            body: body,
            deliveryDate: nil
        )
    }

    func sleepSummaryContent(sleep: SleepSummary, recovery: RecoverySummary) -> PulsarNotificationPayload {
        var parts = [
            "You slept \(durationText(minutes: sleep.totalSleepMinutes)) with \(Int(sleep.sleepEfficiency.rounded()))% efficiency"
        ]

        if recovery.confidence != .missing {
            parts.append(recoverySummaryPhrase(recovery))
        } else if let stagePhrase = sleepStagePhrase(sleep) {
            parts.append(stagePhrase)
        }

        return .immediate(
            identifier: "pulsar.notification.sleepSummary.\(sleepSessionIdentifier(for: sleep, calendar: .current))",
            category: .sleepSummary,
            title: "Sleep summary ready",
            body: compactSentence(parts)
        )
    }

    func timeText(minutesFromMidnight: Int) -> String {
        var calendar = Calendar.current
        calendar.locale = Locale.current
        let day = calendar.startOfDay(for: Date())
        let date = day.addingTimeInterval(TimeInterval(minutesFromMidnight * 60))
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    func sleepGoalText(minutes: Int) -> String {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remainingMinutes)m"
    }

    func sleepSessionIdentifier(for sleep: SleepSummary, calendar: Calendar) -> String {
        let date = sleep.wakeUpDate ?? sleep.wakeTime ?? sleep.lastUpdated ?? Date()
        return SleepWindowResolver.sleepDateKey(forWakeUpDate: date, calendar: calendar)
    }

    private func workoutMetricsPhrase(_ event: WorkoutNotificationEvent) -> String? {
        var metrics: [String] = []
        if let energy = event.activeEnergyKilocalories, energy > 0 {
            metrics.append("\(Int(energy.rounded())) kcal")
        }
        if let averageHeartRate = event.averageHeartRate, averageHeartRate > 0 {
            metrics.append("avg HR \(Int(averageHeartRate.rounded()))")
        }
        if let maxHeartRate = event.maxHeartRate, maxHeartRate > 0 {
            metrics.append("max \(Int(maxHeartRate.rounded()))")
        }
        return metrics.isEmpty ? nil : metrics.joined(separator: ", ")
    }

    private func strainPhrase(_ strain: StrainSummary) -> String? {
        guard strain.confidence != .missing, strain.score > 0 else { return nil }
        switch strain.score {
        case 75...:
            return "Strain is high today"
        case 55..<75:
            return "Strain is moderate today"
        default:
            return "Strain is controlled today"
        }
    }

    private func recoveryPhrase(_ recovery: RecoverySummary, strain: StrainSummary) -> String? {
        if recovery.confidence != .missing {
            switch recovery.status {
            case .excellent, .balanced:
                return "recovery looks balanced"
            case .moderate:
                return "consider a gentle cooldown"
            case .low, .needsAttention:
                return "prioritize hydration and recovery"
            case .unknown:
                break
            }
        }
        if strain.score >= 75 {
            return "prioritize hydration and recovery"
        }
        return nil
    }

    private func stressDrivers(from stress: StressSummary) -> [String] {
        let preferred = stress.drivers.map(\.title) + stress.driverInsights
        return preferred
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(2)
            .map { phrase in
                phrase.prefix(1).lowercased() + String(phrase.dropFirst())
            }
    }

    private func recoverySummaryPhrase(_ recovery: RecoverySummary) -> String {
        switch recovery.status {
        case .excellent:
            return "recovery looks strong today"
        case .balanced:
            return "recovery looks balanced today"
        case .moderate:
            return "recovery looks moderate today"
        case .low:
            return "recovery may benefit from an easier start"
        case .needsAttention, .unknown:
            return "recovery context is still building"
        }
    }

    private func sleepStagePhrase(_ sleep: SleepSummary) -> String? {
        let rem = sleep.stageBreakdown.first { $0.stage == .rem }?.minutes
        let deep = sleep.stageBreakdown.first { $0.stage == .deep }?.minutes
        if let rem, let deep, rem > 0, deep > 0 {
            return "REM \(durationText(minutes: rem)) and Deep \(durationText(minutes: deep))"
        }
        return nil
    }

    private func durationText(minutes: Double) -> String {
        let rounded = max(0, Int(minutes.rounded()))
        let hours = rounded / 60
        let minutes = rounded % 60
        if hours > 0, minutes > 0 {
            return "\(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(minutes)m"
    }

    private func compactSentence(_ parts: [String?]) -> String {
        let text = parts
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
        return text.hasSuffix(".") ? text : text + "."
    }

    private func sentenceCased(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + String(text.dropFirst())
    }
}
