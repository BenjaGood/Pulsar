import Foundation

enum StressInsightFactory {
    static func insights(for summary: StressSummary) -> [StressInsight] {
        var insights = [primaryInsight(for: summary)]

        if let recovery = recoveryInsight(for: summary) {
            insights.append(recovery)
        }

        if let movement = movementInsight(for: summary) {
            insights.append(movement)
        }

        if let availability = availabilityInsight(for: summary) {
            insights.append(availability)
        }

        if insights.count < 2, let driver = summary.driverInsights.first {
            insights.append(
                StressInsight(
                    id: "current-driver",
                    symbol: "waveform.path.ecg",
                    title: "What is shaping today",
                    description: driver,
                    tone: .signal
                )
            )
        }

        if insights.count < 2 {
            insights.append(signalCoverageInsight(for: summary))
        }

        return Array(insights.prefix(4))
    }

    private static func primaryInsight(for summary: StressSummary) -> StressInsight {
        guard let level = summary.level else {
            return unavailablePrimaryInsight(for: summary)
        }

        switch level {
        case .low:
            return StressInsight(
                id: "physiological-load",
                symbol: "leaf.fill",
                title: "Your body appears relaxed",
                description: "Your available heart and recovery signals are producing a low physiological stress estimate relative to your personal baseline. This is generally a good time for focused work, recovery, or light activity.",
                tone: .calm
            )
        case .balanced:
            return StressInsight(
                id: "physiological-load",
                symbol: "water.waves",
                title: "Your physiology looks steady",
                description: "Today’s available signals are sitting in a balanced range relative to your personal baseline, without a strong indication of unusually low or elevated physiological load.",
                tone: .calm
            )
        case .elevated:
            return StressInsight(
                id: "physiological-load",
                symbol: "waveform.path.ecg",
                title: "Your body is carrying more load",
                description: "Your current physiology is producing an elevated stress estimate compared with your usual baseline. A quieter period, hydration, or gentle recovery may help the trend settle.",
                tone: .caution
            )
        case .high:
            return StressInsight(
                id: "physiological-load",
                symbol: "waveform.path.ecg",
                title: "Your physiological load is high",
                description: "Several available signals are contributing to a higher stress estimate today. Consider creating space for recovery and watching whether the pattern eases with rest.",
                tone: .caution
            )
        }
    }

    private static func unavailablePrimaryInsight(for summary: StressSummary) -> StressInsight {
        switch summary.state {
        case .buildingBaseline:
            let dayText = summary.baselineWindowDays == 1 ? "day" : "days"
            return StressInsight(
                id: "baseline-progress",
                symbol: "chart.line.uptrend.xyaxis",
                title: "Your baseline is still learning",
                description: "Pulsar currently has \(summary.baselineWindowDays) baseline \(dayText). Continued overnight wear will make future interpretations more personal and reliable.",
                tone: .neutral
            )
        case .workoutPaused:
            return StressInsight(
                id: "activity-pause",
                symbol: "figure.run",
                title: "Stress is paused during activity",
                description: "Workout-related heart-rate elevation is being kept out of the estimate so exercise is not mistaken for physiological stress.",
                tone: .movement
            )
        case .cooldown:
            return StressInsight(
                id: "activity-pause",
                symbol: "figure.cooldown",
                title: "Your body is cooling down",
                description: "Pulsar is waiting for post-workout physiology to settle before presenting a new stress estimate.",
                tone: .movement
            )
        case .lowConfidence:
            return StressInsight(
                id: "confidence",
                symbol: "waveform.badge.magnifyingglass",
                title: "Today’s estimate is still settling",
                description: "Motion or limited signal quality is making the current interpretation less certain. A fresh reading during a quieter period may improve confidence.",
                tone: .neutral
            )
        case .noData, .ready:
            return StressInsight(
                id: "no-current-estimate",
                symbol: "heart.text.clipboard",
                title: "Your physiology is still coming into view",
                description: "A current stress interpretation needs recent wearable signals and a personal baseline. Pulsar will update this section as new data becomes available.",
                tone: .neutral
            )
        }
    }

    private static func recoveryInsight(for summary: StressSummary) -> StressInsight? {
        guard hasSignal("hrv", in: summary, fallbackAvailable: summary.lastHRV != nil),
              hasSignal("resting-heart-rate", in: summary) || hasSignal("heart-rate", in: summary, fallbackAvailable: summary.lastHeartRate != nil) else {
            return nil
        }

        let hrvSignal = signal("hrv", in: summary)
        let restingSignal = signal("resting-heart-rate", in: summary)
        let hrv = summary.lastHRV ?? firstNumber(in: hrvSignal?.value)
        let hrvBaseline = firstNumber(in: hrvSignal?.baseline)
        let restingHeartRate = firstNumber(in: restingSignal?.value)
        let restingBaseline = firstNumber(in: restingSignal?.baseline)
        let hrvIsSupportive = comparison(hrv, hrvBaseline) { current, baseline in current >= baseline * 0.97 }
        let restingIsSupportive = comparison(restingHeartRate, restingBaseline) { current, baseline in current <= baseline * 1.03 }

        if hrvIsSupportive == true, restingIsSupportive == true {
            if summary.level == .low || summary.level == .balanced {
                let loadDescription = summary.level == .low ? "lower physiological load" : "balanced physiological state"
                return StressInsight(
                    id: "recovery-contribution",
                    symbol: "moon.stars.fill",
                    title: "Recovery is helping",
                    description: "Higher or stable HRV together with a steady resting heart rate is supporting today’s \(loadDescription) relative to your recent baseline.",
                    tone: .recovery
                )
            }

            return StressInsight(
                id: "recovery-contribution",
                symbol: "moon.stars.fill",
                title: "Recovery is providing support",
                description: "Higher or stable HRV together with a steady resting heart rate is a supportive signal, even while other inputs are keeping today’s stress estimate elevated.",
                tone: .recovery
            )
        }

        if summary.level == .elevated || summary.level == .high,
           hrvIsSupportive == false || restingIsSupportive == false {
            return StressInsight(
                id: "recovery-contribution",
                symbol: "moon.stars.fill",
                title: "Recovery signals are adding load",
                description: "HRV or resting heart rate is less favorable than your recent baseline and is contributing context to today’s higher stress estimate.",
                tone: .caution
            )
        }

        let values = recoveryValues(hrv: hrv, restingHeartRate: restingHeartRate)
        return StressInsight(
            id: "recovery-contribution",
            symbol: "moon.stars.fill",
            title: "Recovery signals add context",
            description: "\(values) are being compared with your recent baseline to help distinguish recovery needs from short-term activity.",
            tone: .recovery
        )
    }

    private static func movementInsight(for summary: StressSummary) -> StressInsight? {
        if summary.state == .workoutPaused || summary.state == .cooldown {
            return nil
        }

        let hasMovementSignal = hasSignal("movement-state", in: summary) ||
            hasSignal("activity-adjusted-stress", in: summary, fallbackAvailable: summary.activityAdjustedStress != nil)
        guard hasMovementSignal else { return nil }

        let movementContext = summary.movementStateText.map {
            " Current movement is classified as \($0.lowercased())."
        } ?? ""
        return StressInsight(
            id: "movement-adjustment",
            symbol: "figure.walk",
            title: "Movement adjusted",
            description: "Recent movement has been filtered from the stress estimate, allowing the score to better represent your current physiological state.\(movementContext)",
            tone: .movement
        )
    }

    private static func availabilityInsight(for summary: StressSummary) -> StressInsight? {
        let missing = summary.signals.filter { $0.availability == .unavailable }
        let limited = summary.signals.filter { $0.availability == .limited }

        if !missing.isEmpty {
            let names = missing.map(friendlySignalName)
            return StressInsight(
                id: "signal-availability",
                symbol: "waveform.path.ecg",
                title: "More data improves accuracy",
                description: "\(availabilityPhrase(for: names, state: "unavailable")) Syncing additional HealthKit data may improve future stress estimates.",
                tone: .signal
            )
        }

        if !limited.isEmpty {
            let names = limited.map(friendlySignalName)
            return StressInsight(
                id: "signal-availability",
                symbol: "waveform.path.ecg",
                title: "Some signals are still settling",
                description: "\(availabilityPhrase(for: names, state: "limited")) More consistent wearable data can improve confidence over time.",
                tone: .signal
            )
        }

        if summary.signals.isEmpty, summary.availableSignalCount == 0 {
            return StressInsight(
                id: "signal-availability",
                symbol: "waveform.path.ecg",
                title: "More data improves accuracy",
                description: "Recent heart, recovery, and movement signals are currently unavailable. Syncing HealthKit data may improve future stress estimates.",
                tone: .signal
            )
        }

        return nil
    }

    private static func signalCoverageInsight(for summary: StressSummary) -> StressInsight {
        let count = max(summary.availableSignalCount, summary.signals.count(where: { $0.availability == .available }))
        let signalText = count == 1 ? "signal" : "signals"
        return StressInsight(
            id: "signal-coverage",
            symbol: "heart.text.clipboard",
            title: "Built from today’s signals",
            description: "Today’s interpretation currently uses \(count) available \(signalText) together with your personal baseline.",
            tone: .signal
        )
    }

    private static func signal(_ id: String, in summary: StressSummary) -> StressSignal? {
        summary.signals.first { $0.id == id }
    }

    private static func hasSignal(_ id: String, in summary: StressSummary, fallbackAvailable: Bool = false) -> Bool {
        guard let signal = signal(id, in: summary) else { return fallbackAvailable }
        return signal.availability != .unavailable
    }

    private static func firstNumber(in text: String?) -> Double? {
        text?
            .split { !$0.isNumber && $0 != "." }
            .compactMap { Double($0) }
            .first
    }

    private static func comparison(
        _ current: Double?,
        _ baseline: Double?,
        matches: (Double, Double) -> Bool
    ) -> Bool? {
        guard let current, let baseline, baseline > 0 else { return nil }
        return matches(current, baseline)
    }

    private static func recoveryValues(hrv: Double?, restingHeartRate: Double?) -> String {
        switch (hrv, restingHeartRate) {
        case let (.some(hrv), .some(restingHeartRate)):
            "HRV at \(Int(hrv.rounded())) ms and resting heart rate at \(Int(restingHeartRate.rounded())) bpm"
        case let (.some(hrv), .none):
            "HRV at \(Int(hrv.rounded())) ms and your recent heart-rate pattern"
        case let (.none, .some(restingHeartRate)):
            "Your available HRV and resting heart rate at \(Int(restingHeartRate.rounded())) bpm"
        case (.none, .none):
            "Your available HRV and heart-rate signals"
        }
    }

    nonisolated private static func friendlySignalName(_ signal: StressSignal) -> String {
        switch signal.id {
        case "recent-load": "Recent workout load"
        case "hrv": "HRV"
        case "heart-rate": "Heart rate"
        case "resting-heart-rate": "Resting heart rate"
        case "respiratory-rate": "Respiratory rate"
        case "sleep-duration": "Sleep duration"
        default: signal.title
        }
    }

    private static func availabilityPhrase(for names: [String], state: String) -> String {
        let visibleNames = Array(names.prefix(2)).formatted(.list(type: .and))
        let verb = names.count == 1 ? "is" : "are"
        let additional = names.count > 2 ? " Other supporting signals are also \(state)." : ""
        return "\(visibleNames) \(verb) currently \(state).\(additional)"
    }
}
