import SwiftUI

struct SleepScheduleDialView: View {
    @Binding var schedule: SleepSchedule

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var lastBedtimeHapticBucket: Int?
    @State private var lastWakeHapticBucket: Int?

    private let snapIntervalMinutes = 5
    private let hapticIntervalMinutes = 15

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let ringWidth = max(24, size * 0.105)
            let ringRadius = size / 2 - ringWidth / 2 - 14
            let center = CGPoint(x: size / 2, y: size / 2)

            ZStack {
                dialBackdrop(size: size)
                dialTicks(radius: ringRadius, ringWidth: ringWidth)
                dialReferences(radius: ringRadius + 30)
                dialTrack(radius: ringRadius, ringWidth: ringWidth)
                dialArc(ringWidth: ringWidth)
                    .frame(width: ringRadius * 2, height: ringRadius * 2)
                    .rotationEffect(.degrees(Double(schedule.bedtimeMinutesFromMidnight) / 1440 * 360 - 90))
                handle(
                    title: "Bedtime",
                    symbol: "moon.stars.fill",
                    tint: SettingsMonochromeDesign.primary,
                    currentMinutes: schedule.bedtimeMinutesFromMidnight,
                    point: point(for: schedule.bedtimeMinutesFromMidnight, radius: ringRadius, center: center),
                    ringRadius: ringRadius,
                    center: center,
                    lastBucket: $lastBedtimeHapticBucket
                ) { minutes in
                    schedule.setBedtimeMinutes(minutes)
                }
                handle(
                    title: "Wake",
                    symbol: "sun.max.fill",
                    tint: SettingsMonochromeDesign.primary,
                    currentMinutes: schedule.wakeTimeMinutesFromMidnight,
                    point: point(for: schedule.wakeTimeMinutesFromMidnight, radius: ringRadius, center: center),
                    ringRadius: ringRadius,
                    center: center,
                    lastBucket: $lastWakeHapticBucket
                ) { minutes in
                    schedule.setWakeTimeMinutes(minutes)
                }
                dialCenter(size: size)
            }
            .frame(width: size, height: size)
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sleep schedule dial")
        .accessibilityValue(durationText(minutes: schedule.targetSleepDurationMinutes))
        .sensoryFeedback(.selection, trigger: lastBedtimeHapticBucket) { _, newValue in
            newValue != nil
        }
        .sensoryFeedback(.selection, trigger: lastWakeHapticBucket) { _, newValue in
            newValue != nil
        }
    }

    private func dialBackdrop(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: backdropColors,
                        center: .center,
                        startRadius: size * 0.08,
                        endRadius: size * 0.55
                    )
                )
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            Color.black.opacity(colorScheme == .dark ? 0.18 : 0.07),
                            Color.black.opacity(colorScheme == .dark ? 0.10 : 0.035),
                            Color.white.opacity(colorScheme == .dark ? 0.04 : 0.12),
                            Color.black.opacity(colorScheme == .dark ? 0.18 : 0.07)
                        ],
                        center: .center
                    )
                )
                .blur(radius: 18)
            Circle()
                .stroke(.primary.opacity(0.035), lineWidth: 0.75)
        }
        .shadow(color: SettingsMonochromeDesign.shadow, radius: 18, y: 8)
    }

    private func dialTicks(radius: CGFloat, ringWidth: CGFloat) -> some View {
        ForEach(0..<48, id: \.self) { tick in
            let isMajor = tick.isMultiple(of: 12)
            let isMedium = tick.isMultiple(of: 6)
            Capsule(style: .continuous)
                .fill(.primary.opacity(isMajor ? 0.24 : (isMedium ? 0.15 : 0.09)))
                .frame(width: isMajor ? 2.5 : 1.5, height: isMajor ? 14 : (isMedium ? 9 : 5))
                .offset(y: -(radius + ringWidth * 0.58))
                .rotationEffect(.degrees(Double(tick) / 48 * 360))
        }
    }

    private func dialReferences(radius: CGFloat) -> some View {
        ZStack {
            referenceLabel("0", angle: .degrees(-90), radius: radius)
            referenceLabel("6", angle: .degrees(0), radius: radius)
            referenceLabel("12", angle: .degrees(90), radius: radius)
            referenceLabel("18", angle: .degrees(180), radius: radius)

            referenceSymbol("moon.stars.fill", angle: .degrees(-54), radius: radius - 18, tint: .black)
            referenceSymbol("sun.max.fill", angle: .degrees(126), radius: radius - 18, tint: .black)
        }
    }

    private func referenceLabel(_ text: String, angle: Angle, radius: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(.secondary)
            .offset(x: CGFloat(cos(angle.radians)) * radius, y: CGFloat(sin(angle.radians)) * radius)
    }

    private func referenceSymbol(_ symbol: String, angle: Angle, radius: CGFloat, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 12))
            .bold()
            .foregroundStyle(tint.opacity(0.82))
            .offset(x: CGFloat(cos(angle.radians)) * radius, y: CGFloat(sin(angle.radians)) * radius)
    }

    private func dialTrack(radius: CGFloat, ringWidth: CGFloat) -> some View {
        Circle()
            .stroke(
                LinearGradient(
                    colors: [
                        .primary.opacity(colorScheme == .dark ? 0.13 : 0.055),
                        .primary.opacity(colorScheme == .dark ? 0.08 : 0.025),
                        .primary.opacity(colorScheme == .dark ? 0.06 : 0.02)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: ringWidth
            )
            .frame(width: radius * 2, height: radius * 2)
    }

    private func dialArc(ringWidth: CGFloat) -> some View {
        let durationFraction = max(0.01, CGFloat(schedule.targetSleepDurationMinutes) / CGFloat(24 * 60))
        return Circle()
            .trim(from: 0, to: durationFraction)
            .stroke(
                AngularGradient(
                    colors: [
                        Color.black,
                        Color.black.opacity(0.88),
                        Color.black.opacity(0.72),
                        Color.black.opacity(0.92)
                    ],
                    center: .center
                ),
                style: StrokeStyle(lineWidth: ringWidth, lineCap: .round, lineJoin: .round)
            )
            .shadow(color: SettingsMonochromeDesign.shadow, radius: 10, y: 4)
    }

    private func handle(
        title: String,
        symbol: String,
        tint: Color,
        currentMinutes: Int,
        point: CGPoint,
        ringRadius: CGFloat,
        center: CGPoint,
        lastBucket: Binding<Int?>,
        onMinutesChanged: @escaping (Int) -> Void
    ) -> some View {
        ZStack {
            Circle()
                .fill(.background.opacity(0.88))
            Circle()
                .stroke(tint.opacity(0.20), lineWidth: 0.75)
            Image(systemName: symbol)
                .font(.system(size: 16))
                .bold()
                .foregroundStyle(tint)
        }
        .frame(width: 46, height: 46)
        .pulsarLiquidGlass(
            cornerRadius: 23,
            tint: .white.opacity(0.08),
            interactive: true,
            isClear: true
        )
        .shadow(color: SettingsMonochromeDesign.shadow, radius: 9, y: 4)
        .position(point)
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: point)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let minutes = snappedMinutes(for: value.location, center: center)
                    onMinutesChanged(minutes)
                    updateHapticBucketIfNeeded(for: minutes, lastBucket: lastBucket)
                }
                .onEnded { _ in
                    lastBucket.wrappedValue = nil
                }
        )
        .accessibilityLabel(title)
        .accessibilityValue(timeText(minutesFromMidnight: currentMinutes))
        .accessibilityAdjustableAction { direction in
            let adjustment: Int
            switch direction {
            case .increment:
                adjustment = snapIntervalMinutes
            case .decrement:
                adjustment = -snapIntervalMinutes
            @unknown default:
                return
            }
            onMinutesChanged((currentMinutes + adjustment + 24 * 60) % (24 * 60))
        }
    }

    private func dialCenter(size: CGFloat) -> some View {
        VStack(spacing: 5) {
            Text("Target Sleep")
                .font(.system(size: max(11, size * 0.032), weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(durationText(minutes: schedule.targetSleepDurationMinutes))
                .font(.system(size: size * 0.13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .fixedSize(horizontal: true, vertical: false)
                .contentTransition(.numericText())
            Text(durationStatusText(minutes: schedule.targetSleepDurationMinutes))
                .font(.system(size: max(12, size * 0.035), weight: .regular))
                .foregroundStyle(
                    schedule.targetSleepDurationMinutes
                        >= Int(PulsarSharedSleepCalculator.defaultTargetSleepHours * 60)
                        ? SettingsMonochromeDesign.primary
                        : SettingsMonochromeDesign.secondary
                )
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
    }

    private func point(for minutes: Int, radius: CGFloat, center: CGPoint) -> CGPoint {
        let normalized = Double(((minutes % (24 * 60)) + 24 * 60) % (24 * 60))
        let angle = normalized / Double(24 * 60) * 360 - 90
        return CGPoint(
            x: center.x + CGFloat(cos(angle * .pi / 180)) * radius,
            y: center.y + CGFloat(sin(angle * .pi / 180)) * radius
        )
    }

    private func snappedMinutes(for location: CGPoint, center: CGPoint) -> Int {
        let dx = location.x - center.x
        let dy = location.y - center.y
        var angle = atan2(dy, dx) + .pi / 2
        if angle < 0 {
            angle += 2 * .pi
        }
        let rawMinutes = Int((angle / (2 * .pi) * Double(24 * 60)).rounded())
        let snapped = Int((Double(rawMinutes) / Double(snapIntervalMinutes)).rounded()) * snapIntervalMinutes
        let dayMinutes = 24 * 60
        let remainder = snapped % dayMinutes
        return remainder >= 0 ? remainder : remainder + dayMinutes
    }

    private func updateHapticBucketIfNeeded(for minutes: Int, lastBucket: Binding<Int?>) {
        let bucket = minutes / hapticIntervalMinutes
        guard lastBucket.wrappedValue != bucket else { return }
        lastBucket.wrappedValue = bucket
    }

    private func durationText(minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remainder)m"
    }

    private func durationStatusText(minutes: Int) -> String {
        minutes >= Int(PulsarSharedSleepCalculator.defaultTargetSleepHours * 60) ? "Meets your sleep goal" : "Below your sleep goal"
    }

    private func timeText(minutesFromMidnight: Int) -> String {
        let components = DateComponents(hour: minutesFromMidnight / 60, minute: minutesFromMidnight % 60)
        let date = Calendar.current.date(from: components) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    private var backdropColors: [Color] {
        if colorScheme == .dark {
            [
                Color.white.opacity(0.075),
                Color.black.opacity(0.055),
                Color.black.opacity(0.11)
            ]
        } else {
            [
                Color.white.opacity(0.94),
                Color.black.opacity(0.025),
                Color.black.opacity(0.04)
            ]
        }
    }
}

private struct SleepScheduleDialPreviewContainer: View {
    @State var schedule = SleepSchedule(
        bedtimeMinutesFromMidnight: 22 * 60 + 30,
        wakeTimeMinutesFromMidnight: 6 * 60 + 30,
        alarmEnabled: true,
        alarmUsesWakeTime: true
    )

    var body: some View {
        SleepScheduleDialView(schedule: $schedule)
            .frame(width: 360, height: 360)
            .padding()
            .background(PulsarSettingsBackground())
    }
}

#Preview("Sleep Dial Light") {
    SleepScheduleDialPreviewContainer()
}
