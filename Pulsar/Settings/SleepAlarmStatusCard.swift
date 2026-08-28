import SwiftUI

struct SleepAlarmStatusCard: View {
    var schedule: SleepSchedule
    var sleepGoalDays: SleepGoalDays
    var alarmTime: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ALARM ACTIVE")
                        .sleepSectionLabel()

                    Text(alarmTime)
                        .font(.system(.largeTitle, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }

                Spacer(minLength: 12)

                Image(systemName: "alarm.fill")
                    .font(.title2)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(SettingsMonochromeDesign.primary)
                    .frame(width: 58, height: 58)
                    .accessibilityHidden(true)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) {
                    details
                }

                VStack(alignment: .leading, spacing: 14) {
                    details
                }
            }
        }
        .padding(SleepPreferencesDesign.cardPadding)
        .sleepPreferencesCardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Alarm on at \(alarmTime), sound \(schedule.alarmSoundName), haptics \(schedule.alarmHapticsEnabled ? "on" : "off"), \(sleepGoalDays.rawValue)"
        )
    }

    @ViewBuilder
    private var details: some View {
        SleepAlarmStatusDetail(title: "Sound", value: schedule.alarmSoundName)
        SleepAlarmStatusDetail(
            title: "Haptics",
            value: schedule.alarmHapticsEnabled ? "On" : "Off"
        )
        SleepAlarmStatusDetail(title: "Days", value: sleepGoalDays.rawValue)
    }
}

struct SleepAlarmStatusDetail: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.body)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Sleep Alarm Active") {
    SleepAlarmStatusCard(
        schedule: SleepSchedule(
            bedtimeMinutesFromMidnight: 23 * 60,
            wakeTimeMinutesFromMidnight: 7 * 60 + 20,
            alarmEnabled: true,
            alarmTimeMinutesFromMidnight: 3 * 60 + 25,
            alarmUsesWakeTime: false
        ),
        sleepGoalDays: .everyDay,
        alarmTime: "03:25"
    )
    .padding()
    .background(PulsarSettingsBackground())
}
