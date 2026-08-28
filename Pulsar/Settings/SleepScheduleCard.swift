import SwiftUI

struct SleepScheduleCard: View {
    @Binding var schedule: SleepSchedule
    var bedtimeText: String
    var wakeText: String
    var onEditBedtime: () -> Void
    var onEditWakeTime: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("SLEEP SCHEDULE")
                .sleepSectionLabel()

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    timeTiles
                }

                VStack(spacing: 10) {
                    timeTiles
                }
            }

            SleepScheduleDialView(schedule: $schedule)
                .frame(maxWidth: 420)
                .padding(.horizontal, 2)
                .padding(.vertical, 4)

            Text("Drag the handles to adjust, or tap the time cards for exact times.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
        }
        .padding(SleepPreferencesDesign.cardPadding)
        .sleepPreferencesCardSurface()
    }

    @ViewBuilder
    private var timeTiles: some View {
        SleepScheduleTimeTile(
            title: "Bedtime",
            value: bedtimeText,
            symbol: "moon.stars.fill",
            tint: .black,
            backgroundTint: .black,
            action: onEditBedtime
        )

        SleepScheduleTimeTile(
            title: "Wake",
            value: wakeText,
            symbol: "sun.max.fill",
            tint: .black,
            backgroundTint: .black,
            action: onEditWakeTime
        )
    }
}

struct SleepScheduleTimeTile: View {
    var title: String
    var value: String
    var symbol: String
    var tint: Color
    var backgroundTint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(SettingsMonochromeDesign.primary)
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(value)
                        .font(.title2)
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
            .background(SettingsMonochromeDesign.subtleFill, in: RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .stroke(SettingsMonochromeDesign.border, lineWidth: 0.75)
            }
        }
        .buttonStyle(SleepSettingsPressButtonStyle())
        .accessibilityLabel("\(title), \(value)")
        .accessibilityHint("Opens an exact time picker")
    }
}

struct SleepSettingsPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .brightness(configuration.isPressed ? -0.015 : 0)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.22),
                value: configuration.isPressed
            )
    }
}
