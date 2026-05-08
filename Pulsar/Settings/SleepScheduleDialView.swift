import SwiftUI
import UIKit

struct SleepScheduleDialView: View {
    @Binding var schedule: SleepSchedule

    @State private var lastBedtimeHapticBucket: Int?
    @State private var lastWakeHapticBucket: Int?

    private let snapIntervalMinutes = 5
    private let hapticIntervalMinutes = 15

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let ringWidth = max(26, size * 0.125)
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
                    tint: Color.indigo,
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
                    tint: Color.cyan,
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep schedule dial")
        .accessibilityValue("\(durationText(minutes: schedule.targetSleepDurationMinutes)), bedtime \(timeText(minutesFromMidnight: schedule.bedtimeMinutesFromMidnight)), wake \(timeText(minutesFromMidnight: schedule.wakeTimeMinutesFromMidnight))")
    }

    private func dialBackdrop(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.16),
                            Color.white.opacity(0.04),
                            Color.black.opacity(0.18)
                        ],
                        center: .center,
                        startRadius: size * 0.06,
                        endRadius: size * 0.58
                    )
                )
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            Color.indigo.opacity(0.30),
                            Color.blue.opacity(0.18),
                            Color.yellow.opacity(0.14),
                            Color.orange.opacity(0.10),
                            Color.indigo.opacity(0.30)
                        ],
                        center: .center
                    )
                )
                .blur(radius: 10)
            Circle()
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }

    private func dialTicks(radius: CGFloat, ringWidth: CGFloat) -> some View {
        ForEach(0..<48, id: \.self) { tick in
            let isMajor = tick.isMultiple(of: 12)
            let isMedium = tick.isMultiple(of: 6)
            Capsule(style: .continuous)
                .fill(.white.opacity(isMajor ? 0.42 : (isMedium ? 0.22 : 0.12)))
                .frame(width: isMajor ? 3 : 2, height: isMajor ? 16 : (isMedium ? 10 : 6))
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

            referenceSymbol("moon.stars.fill", angle: .degrees(-54), radius: radius - 18, tint: .indigo)
            referenceSymbol("sun.max.fill", angle: .degrees(126), radius: radius - 18, tint: .yellow)
        }
    }

    private func referenceLabel(_ text: String, angle: Angle, radius: CGFloat) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .offset(x: CGFloat(cos(angle.radians)) * radius, y: CGFloat(sin(angle.radians)) * radius)
    }

    private func referenceSymbol(_ symbol: String, angle: Angle, radius: CGFloat, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.caption.weight(.bold))
            .foregroundStyle(tint.opacity(0.82))
            .offset(x: CGFloat(cos(angle.radians)) * radius, y: CGFloat(sin(angle.radians)) * radius)
    }

    private func dialTrack(radius: CGFloat, ringWidth: CGFloat) -> some View {
        Circle()
            .stroke(
                LinearGradient(
                    colors: [
                        .white.opacity(0.12),
                        .white.opacity(0.04),
                        .black.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: ringWidth
            )
            .frame(width: radius * 2, height: radius * 2)
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
    }

    private func dialArc(ringWidth: CGFloat) -> some View {
        let durationFraction = max(0.01, CGFloat(schedule.targetSleepDurationMinutes) / CGFloat(24 * 60))
        return Circle()
            .trim(from: 0, to: durationFraction)
            .stroke(
                AngularGradient(
                    colors: [
                        Color.indigo.opacity(0.80),
                        Color.cyan.opacity(0.94),
                        Color.white.opacity(0.95)
                    ],
                    center: .center
                ),
                style: StrokeStyle(lineWidth: ringWidth, lineCap: .round, lineJoin: .round)
            )
            .shadow(color: Color.indigo.opacity(0.20), radius: 10, y: 4)
            .shadow(color: Color.cyan.opacity(0.12), radius: 14, y: 8)
    }

    private func handle(
        title: String,
        symbol: String,
        tint: Color,
        point: CGPoint,
        ringRadius: CGFloat,
        center: CGPoint,
        lastBucket: Binding<Int?>,
        onMinutesChanged: @escaping (Int) -> Void
    ) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.96), .white.opacity(0.92)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .stroke(.white.opacity(0.62), lineWidth: 1.2)
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.72))
        }
        .frame(width: 28, height: 28)
        .shadow(color: tint.opacity(0.22), radius: 10, y: 4)
        .position(point)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let minutes = snappedMinutes(for: value.location, center: center)
                    onMinutesChanged(minutes)
                    triggerHapticIfNeeded(for: minutes, lastBucket: lastBucket)
                }
                .onEnded { _ in
                    lastBucket.wrappedValue = nil
                }
        )
        .accessibilityLabel(title)
    }

    private func dialCenter(size: CGFloat) -> some View {
        VStack(spacing: 5) {
            Text("Target Sleep")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(durationText(minutes: schedule.targetSleepDurationMinutes))
                .font(.system(size: size * 0.12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.72)
            Text(durationStatusText(minutes: schedule.targetSleepDurationMinutes))
                .font(.footnote.weight(.medium))
                .foregroundStyle(schedule.targetSleepDurationMinutes >= Int(PulsarSharedSleepCalculator.defaultTargetSleepHours * 60) ? .cyan : .secondary)
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

    private func triggerHapticIfNeeded(for minutes: Int, lastBucket: Binding<Int?>) {
        let bucket = minutes / hapticIntervalMinutes
        guard lastBucket.wrappedValue != bucket else { return }
        lastBucket.wrappedValue = bucket
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func durationText(minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 {
            return "\(hours) hr"
        }
        return "\(hours) hr \(remainder)m"
    }

    private func durationStatusText(minutes: Int) -> String {
        minutes >= Int(PulsarSharedSleepCalculator.defaultTargetSleepHours * 60) ? "Meets your sleep goal" : "Below your sleep goal"
    }

    private func timeText(minutesFromMidnight: Int) -> String {
        let components = DateComponents(hour: minutesFromMidnight / 60, minute: minutesFromMidnight % 60)
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
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
            .background(PulsarSectionBackground())
    }
}

#Preview("Sleep Dial Light") {
    SleepScheduleDialPreviewContainer()
}

#Preview("Sleep Dial Dark") {
    SleepScheduleDialPreviewContainer()
        .preferredColorScheme(.dark)
}
