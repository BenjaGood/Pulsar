import Foundation

struct WindDownDecision: Equatable {
    var dayKey: String
    var triggerDate: Date
    var shouldDeliverImmediately: Bool
}

struct NotificationDecisionEngine {
    var highStressCooldown: TimeInterval = 5 * 60 * 60
    var windDownLeadTime: TimeInterval = 45 * 60
    var sleepSummaryCompletionDelay: TimeInterval = 20 * 60
    var calendar: Calendar = .current

    func shouldSendPostWorkout(
        event: WorkoutNotificationEvent,
        preferences: IntelligentNotificationPreferences,
        hasProcessed: Bool,
        now: Date
    ) -> Bool {
        guard preferences.intelligentNotificationsEnabled,
              preferences.postWorkoutSummaryEnabled,
              !hasProcessed,
              event.durationMinutes >= 5,
              event.endDate <= now,
              now.timeIntervalSince(event.endDate) <= 12 * 60 * 60 else {
            return false
        }
        return true
    }

    func shouldSendHighStress(
        stress: StressSummary,
        schedule: SleepSchedule,
        preferences: IntelligentNotificationPreferences,
        lastSent: Date?,
        now: Date
    ) -> Bool {
        guard preferences.intelligentNotificationsEnabled,
              preferences.highStressAlertsEnabled,
              stress.level == .high,
              stress.confidence == .moderate || stress.confidence == .high,
              stress.state == .ready,
              stress.availableSignalCount >= 3,
              stress.baselineWindowDays >= StressBaselineBuilder.minimumBaselineDays,
              hasSustainedElevatedStress(stress, now: now),
              !isInSleepWindow(schedule: schedule, date: now) else {
            return false
        }

        if let lastSent, now.timeIntervalSince(lastSent) < highStressCooldown {
            return false
        }

        return true
    }

    func windDownDecision(
        profile: UserProfile,
        preferences: IntelligentNotificationPreferences,
        lastScheduledDayKey: String?,
        now: Date
    ) -> WindDownDecision? {
        guard preferences.intelligentNotificationsEnabled,
              preferences.windDownRemindersEnabled else {
            return nil
        }

        let schedule = profile.sleepSchedule
        let nextBedtime = nextBedtimeDate(minutesFromMidnight: schedule.bedtimeMinutesFromMidnight, now: now)
        guard sleepGoalDays(profile.sleepGoalDays, includes: nextBedtime) else { return nil }

        let dayKey = PulsarDailyMetricsDateKey.dateKey(for: nextBedtime, calendar: calendar)
        guard lastScheduledDayKey != dayKey else { return nil }

        let triggerDate = nextBedtime.addingTimeInterval(-windDownLeadTime)
        let latestImmediateDelivery = nextBedtime.addingTimeInterval(15 * 60)
        if triggerDate <= now, now <= latestImmediateDelivery {
            return WindDownDecision(dayKey: dayKey, triggerDate: now.addingTimeInterval(5), shouldDeliverImmediately: true)
        }

        guard triggerDate > now else { return nil }
        return WindDownDecision(dayKey: dayKey, triggerDate: triggerDate, shouldDeliverImmediately: false)
    }

    func shouldSendSleepSummary(
        sleep: SleepSummary,
        preferences: IntelligentNotificationPreferences,
        hasProcessed: Bool,
        lastNotificationDay: String?,
        dayKey: String,
        now: Date
    ) -> Bool {
        guard preferences.intelligentNotificationsEnabled,
              preferences.sleepSummaryEnabled,
              !hasProcessed,
              lastNotificationDay != dayKey,
              sleep.confidence != .missing,
              sleep.totalSleepMinutes >= 180,
              sleep.sleepEfficiency > 0,
              sleep.analyzedSampleCount > 0,
              let wakeTime = sleep.wakeTime,
              now.timeIntervalSince(wakeTime) >= sleepSummaryCompletionDelay else {
            return false
        }
        return true
    }

    func isInSleepWindow(schedule: SleepSchedule, date: Date) -> Bool {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let bedtime = schedule.bedtimeMinutesFromMidnight
        let wake = schedule.wakeTimeMinutesFromMidnight

        if bedtime == wake {
            return false
        }
        if bedtime < wake {
            return minutes >= bedtime && minutes < wake
        }
        return minutes >= bedtime || minutes < wake
    }

    private func hasSustainedElevatedStress(_ stress: StressSummary, now: Date) -> Bool {
        let elevatedSamples = stress.dailySamples
            .filter { now.timeIntervalSince($0.timestamp) <= 2 * 60 * 60 }
            .filter { $0.score >= PulsarStressScale.highLowerBound }
            .sorted { $0.timestamp < $1.timestamp }

        if elevatedSamples.count >= 2,
           let first = elevatedSamples.first,
           let last = elevatedSamples.last,
           last.timestamp.timeIntervalSince(first.timestamp) >= 20 * 60 {
            return true
        }

        return elevatedSamples.count >= 1 && stress.analyzedSampleCount >= 8
    }

    private func nextBedtimeDate(minutesFromMidnight: Int, now: Date) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        let todayBedtime = startOfToday.addingTimeInterval(TimeInterval(minutesFromMidnight * 60))
        if todayBedtime.addingTimeInterval(15 * 60) >= now {
            return todayBedtime
        }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday.addingTimeInterval(86_400)
        return tomorrow.addingTimeInterval(TimeInterval(minutesFromMidnight * 60))
    }

    private func sleepGoalDays(_ goalDays: SleepGoalDays, includes date: Date) -> Bool {
        switch goalDays {
        case .everyDay:
            return true
        case .weekdays:
            let weekday = calendar.component(.weekday, from: date)
            return (2...6).contains(weekday)
        case .custom:
            return false
        }
    }
}
