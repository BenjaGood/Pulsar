//
//  FitnessBodyMapView.swift
//  Pulsar
//

import SwiftUI

private let showBodyZoneDebugOutlines = false

struct FitnessBodyMapSection: View {
    var analysis: BodyMapAnalysis
    var avatarType: BodyMapAvatarType = .male

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedBodySide: BodyViewSide = .front

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(viewportBackground)
                    .overlay(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(.white.opacity(colorScheme == .dark ? 0.035 : 0.055))
                            .frame(height: 1)
                            .padding(.horizontal, 48)
                            .padding(.bottom, 30)
                    }

                BodyMapAnimatedScanView(analysis: analysis, side: selectedBodySide, avatarType: avatarType)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)

                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.caption.weight(.bold))
                        Text(selectedBodySide.scanLabel)
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.white.opacity(0.74))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.24), in: Capsule(style: .continuous))
                    .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    }

                    BodyMapPerspectiveToggle(selection: $selectedBodySide)
                }
                .padding(12)
            }
            .frame(height: 384)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(modelBorder, lineWidth: 1)
            }

            BodyMapLegendRow()

            insightCard
        }
        .padding(18)
        .background(sectionBackground, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(sectionBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.08), radius: 22, y: 12)
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: analysis)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: avatarType)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Body Map")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(primaryText)

                Text("Weekly training zones")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(secondaryText)
            }

            Spacer()

            HStack(spacing: 7) {
                Circle()
                    .fill(analysis.isTrainingActive ? Color.green : secondaryText.opacity(0.42))
                    .frame(width: 8, height: 8)
                    .shadow(color: (analysis.isTrainingActive ? Color.green : .clear).opacity(0.55), radius: 8)

                Text(analysis.isTrainingActive ? "Active" : "Inactive")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(analysis.isTrainingActive ? Color.green : secondaryText)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(statusBackground, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(statusBorder, lineWidth: 1)
            }
        }
    }

    private var insightCard: some View {
        HStack(alignment: .top, spacing: 13) {
            ZStack {
                Circle()
                    .fill(insightAccent.opacity(analysis.isTrainingActive ? 0.18 : 0.08))
                    .frame(width: 46, height: 46)

                Image(systemName: insightSymbol)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(analysis.isTrainingActive ? insightAccent : secondaryText)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(insightTitle)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(primaryText)

                Text(insightText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(insightBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(colorScheme == .dark ? 0.12 : 0.70), lineWidth: 1)
        }
    }

    private var insightText: String {
        let strengthZones = analysis.topStrengthZones.prefix(3).map { trainedZone in
            "\(trainedZone.zone.displayName) \(WeeklyMuscleLoadCalculator.intensityLabel(for: trainedZone.score).lowercased())"
        }

        if !strengthZones.isEmpty, analysis.cardioSessions > 0 {
            let duration = FitnessWeekFormatters.duration(analysis.cardioDuration)
            return "Strength focus: \(strengthZones.joined(separator: ", ")). Cardio adds \(duration) this week."
        }

        if !strengthZones.isEmpty {
            return "Strength focus: \(strengthZones.joined(separator: ", "))."
        }

        guard analysis.cardioSessions > 0 else {
            return "Finish a workout to light up the muscles trained this week."
        }

        let sessionCopy = analysis.cardioSessions == 1 ? "session" : "sessions"
        let duration = FitnessWeekFormatters.duration(analysis.cardioDuration)
        return "You completed \(analysis.cardioSessions) cardio \(sessionCopy) this week - \(duration) total."
    }

    private var insightTitle: String {
        if !analysis.strengthZones.isEmpty { return "Muscles trained" }
        return analysis.isCardioActive ? "Cardio active" : "No training logged"
    }

    private var insightSymbol: String {
        if !analysis.strengthZones.isEmpty { return "figure.strengthtraining.traditional" }
        return analysis.isCardioActive ? "heart.fill" : "heart"
    }

    private var insightAccent: Color {
        if !analysis.strengthZones.isEmpty { return Color(red: 0.72, green: 0.66, blue: 1.0) }
        return BodyZone.heart.accent
    }

    private var viewportBackground: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.030, green: 0.035, blue: 0.048),
                    Color(red: 0.018, green: 0.024, blue: 0.036),
                    Color.black.opacity(0.90)
                ]
                : [
                    Color(red: 0.075, green: 0.095, blue: 0.125),
                    Color(red: 0.052, green: 0.064, blue: 0.090),
                    Color(red: 0.030, green: 0.038, blue: 0.055)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var sectionBackground: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color.white.opacity(0.10),
                    Color(red: 0.06, green: 0.08, blue: 0.12).opacity(0.86),
                    insightAccent.opacity(analysis.isTrainingActive ? 0.10 : 0.035)
                ]
                : [
                    Color.white.opacity(0.92),
                    Color(red: 0.95, green: 0.98, blue: 1.00).opacity(0.76),
                    insightAccent.opacity(analysis.isTrainingActive ? 0.08 : 0.025)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var insightBackground: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.white.opacity(0.09), Color.white.opacity(0.035), insightAccent.opacity(analysis.isTrainingActive ? 0.09 : 0.025)]
                : [Color.white.opacity(0.86), Color(red: 0.96, green: 0.98, blue: 1.00).opacity(0.68), insightAccent.opacity(analysis.isTrainingActive ? 0.06 : 0.02)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var statusBackground: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.white.opacity(0.11), Color.white.opacity(0.04), insightAccent.opacity(analysis.isTrainingActive ? 0.10 : 0)]
                : [Color.white.opacity(0.84), Color(red: 0.95, green: 0.98, blue: 1.00).opacity(0.62), insightAccent.opacity(analysis.isTrainingActive ? 0.06 : 0)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var sectionBorder: LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(colorScheme == .dark ? 0.18 : 0.82),
                insightAccent.opacity(analysis.isTrainingActive ? 0.24 : 0.08),
                .black.opacity(colorScheme == .dark ? 0.22 : 0.04)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var statusBorder: Color {
        analysis.isTrainingActive
            ? insightAccent.opacity(colorScheme == .dark ? 0.30 : 0.22)
            : .white.opacity(colorScheme == .dark ? 0.12 : 0.68)
    }

    private var modelBorder: LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(colorScheme == .dark ? 0.13 : 0.70),
                insightAccent.opacity(analysis.isTrainingActive ? 0.24 : 0.06),
                .cyan.opacity(colorScheme == .dark ? 0.18 : 0.12)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.97) : Color(red: 0.07, green: 0.10, blue: 0.14)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.60) : Color(red: 0.36, green: 0.40, blue: 0.48)
    }
}

private struct BodyMapLegendRow: View {
    private let items: [(title: String, color: Color, opacity: Double)] = [
        ("Not trained", .white, 0.18),
        ("Light", Color(red: 0.72, green: 0.66, blue: 1.0), 0.34),
        ("Medium", Color(red: 0.72, green: 0.66, blue: 1.0), 0.68),
        ("High", Color(red: 0.72, green: 0.66, blue: 1.0), 1.0)
    ]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(items, id: \.title) { item in
                HStack(spacing: 6) {
                    Circle()
                        .fill(item.color.opacity(item.opacity))
                        .frame(width: 8, height: 8)
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.18), lineWidth: 1)
                        }
                    Text(item.title)
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(.white.opacity(0.62))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.055), in: Capsule(style: .continuous))
            }
        }
    }
}

private struct BodyMapAnimatedScanView: View {
    var analysis: BodyMapAnalysis
    var side: BodyViewSide
    var avatarType: BodyMapAvatarType

    var body: some View {
        TimelineView(.animation) { timeline in
            GeometryReader { proxy in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let scanProgress = time.truncatingRemainder(dividingBy: 3.4) / 3.4
                let scanY = proxy.size.height * scanProgress

                ZStack {
                    BodyMapGrid(time: time)
                        .opacity(0.72)

                    BodyMapAnatomyPlateView(analysis: analysis, side: side, avatarType: avatarType, time: time)
                        .padding(.top, 10)
                        .padding(.bottom, 8)
                        .id("\(avatarType.id)-\(side.id)")
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96)),
                            removal: .opacity.combined(with: .scale(scale: 1.02))
                        ))

                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    .cyan.opacity(0.00),
                                    .cyan.opacity(0.34),
                                    .white.opacity(0.40),
                                    .cyan.opacity(0.18),
                                    .clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 1)
                        .shadow(color: .cyan.opacity(0.32), radius: 10)
                        .offset(y: scanY - proxy.size.height / 2)

                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Circle()
                                .fill(analysis.isTrainingActive ? scanAccent : .white.opacity(0.35))
                                .frame(width: 6, height: 6)
                                .shadow(color: (analysis.isTrainingActive ? scanAccent : .clear).opacity(0.65), radius: 8)

                            Text(analysis.isTrainingActive ? "Active zones glow" : "Weekly body scan")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white.opacity(0.62))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.18), in: Capsule(style: .continuous))
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(.white.opacity(0.09), lineWidth: 1)
                        }
                    }
                    .padding(.bottom, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .drawingGroup()
                .animation(.spring(response: 0.42, dampingFraction: 0.86), value: side)
            }
        }
    }

    private var scanAccent: Color {
        if !analysis.strengthZones.isEmpty { return Color(red: 0.72, green: 0.66, blue: 1.0) }
        return BodyZone.heart.accent
    }
}

private struct BodyMapPerspectiveToggle: View {
    @Binding var selection: BodyViewSide

    var body: some View {
        HStack(spacing: 3) {
            ForEach(BodyViewSide.allCases) { side in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        selection = side
                    }
                } label: {
                    Text(side.title)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(selection == side ? .white : .white.opacity(0.58))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background {
                            if selection == side {
                                Capsule(style: .continuous)
                                    .fill(.white.opacity(0.16))
                                    .overlay {
                                        Capsule(style: .continuous)
                                            .stroke(.cyan.opacity(0.26), lineWidth: 1)
                                    }
                                    .shadow(color: .cyan.opacity(0.18), radius: 10)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(.black.opacity(0.22), in: Capsule(style: .continuous))
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(.white.opacity(0.11), lineWidth: 1)
        }
        .accessibilityLabel("Body map view")
    }
}

private struct BodyMapGrid: View {
    var time: TimeInterval

    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 28
            let drift = CGFloat(time.truncatingRemainder(dividingBy: 2.8) / 2.8) * step
            var path = Path()

            var x = -step + drift
            while x <= size.width + step {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }

            var y = -step + drift * 0.55
            while y <= size.height + step {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }

            context.stroke(path, with: .color(.cyan.opacity(0.045)), lineWidth: 0.7)

            var centerLine = Path()
            centerLine.move(to: CGPoint(x: size.width / 2, y: 20))
            centerLine.addLine(to: CGPoint(x: size.width / 2, y: size.height - 20))
            context.stroke(centerLine, with: .color(.white.opacity(0.035)), style: StrokeStyle(lineWidth: 1, dash: [5, 8]))
        }
    }
}

private struct BodyMapAnatomyPlateView: View {
    var analysis: BodyMapAnalysis
    var side: BodyViewSide
    var avatarType: BodyMapAvatarType
    var time: TimeInterval

    private let plateHeight: CGFloat = 336

    var body: some View {
        GeometryReader { proxy in
            let aspectRatio = avatarType.aspectRatio(for: side)
            let availableHeight = min(plateHeight, proxy.size.height - 30)
            let availableWidth = proxy.size.width * 0.80
            let figureHeight = min(availableHeight, availableWidth / aspectRatio)
            let figureWidth = figureHeight * aspectRatio
            let overlays = BodyMapOverlayCatalog.overlays(for: avatarType, side: side)

            ZStack {
                bodyGlow(width: figureWidth, height: figureHeight)

                Image(avatarType.imageName(for: side))
                    .resizable()
                    .scaledToFit()
                    .opacity(0.95)
                    .shadow(color: .white.opacity(0.16), radius: 12)
                    .shadow(color: .cyan.opacity(0.16), radius: 20)

                BodyMapImageOverlayLayer(
                    analysis: analysis,
                    overlays: overlays,
                    side: side,
                    time: time
                )
                .frame(width: figureWidth, height: figureHeight)
            }
            .frame(width: figureWidth, height: figureHeight)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func bodyGlow(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 120, style: .continuous)
            .fill(
                RadialGradient(
                    colors: [
                        .white.opacity(0.11),
                        .cyan.opacity(0.12),
                        .cyan.opacity(0.03),
                        .clear
                    ],
                    center: .center,
                    startRadius: 6,
                    endRadius: 170
                )
            )
            .frame(width: width * 1.22, height: height * 0.96)
            .blur(radius: 20)
            .opacity(0.80)
    }
}

private struct BodyMapImageOverlayLayer: View {
    var analysis: BodyMapAnalysis
    var overlays: [BodyZoneOverlay]
    var side: BodyViewSide
    var time: TimeInterval

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(visibleOverlays) { overlay in
                    let frame = overlayFrame(overlay, in: proxy.size)

                    if overlay.zone == .heart, side == .front {
                        HeartZonePulse(
                            isActive: analysis.isCardioActive,
                            intensity: analysis.trainedZone(matching: .heart)?.intensity ?? 0.2,
                            time: time
                        )
                        .frame(width: frame.width * 2.2, height: frame.height * 2.2)
                        .position(x: frame.midX, y: frame.midY)
                    } else if let trainedZone = analysis.trainedZone(matching: overlay.zone) {
                        BodyZoneImageHighlight(overlay: overlay, intensity: trainedZone.intensity, time: time)
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                    }
                }

                if showBodyZoneDebugOutlines {
                    ForEach(overlays) { overlay in
                        let frame = overlayFrame(overlay, in: proxy.size)

                        BodyZoneDebugOverlay(overlay: overlay)
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
    }

    private var visibleOverlays: [BodyZoneOverlay] {
        overlays.filter { overlay in
            overlay.zone == .heart || analysis.isZoneActive(overlay.zone)
        }
    }

    private func overlayFrame(_ overlay: BodyZoneOverlay, in size: CGSize) -> CGRect {
        CGRect(
            x: overlay.normalizedFrame.minX * size.width,
            y: overlay.normalizedFrame.minY * size.height,
            width: overlay.normalizedFrame.width * size.width,
            height: overlay.normalizedFrame.height * size.height
        )
    }
}

private struct BodyZoneImageHighlight: View {
    var overlay: BodyZoneOverlay
    var intensity: Double
    var time: TimeInterval

    private var shimmer: Double {
        (sin(time * 2.2) + 1) / 2
    }

    private var clampedIntensity: Double {
        min(max(intensity, 0.24), 1)
    }

    var body: some View {
        Capsule(style: .continuous)
            .fill(
                RadialGradient(
                    colors: [
                        overlay.zone.accent.opacity(0.16 + clampedIntensity * 0.28 + shimmer * 0.08),
                        overlay.zone.accent.opacity(0.08 + clampedIntensity * 0.16),
                        .clear
                    ],
                    center: .center,
                    startRadius: 1,
                    endRadius: 64
                )
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(overlay.zone.accent.opacity(0.12 + clampedIntensity * 0.24), lineWidth: 1)
                    .blur(radius: 0.5)
            }
            .shadow(color: overlay.zone.accent.opacity(0.18 + clampedIntensity * 0.24), radius: 8 + clampedIntensity * 10)
            .blendMode(.screen)
            .opacity(0.55 + clampedIntensity * 0.35)
    }
}

private struct BodyZoneDebugOverlay: View {
    var overlay: BodyZoneOverlay

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(overlay.zone.accent.opacity(0.90), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

            Text(overlay.displayName)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(overlay.zone.accent)
                .padding(3)
                .background(.black.opacity(0.55), in: Capsule(style: .continuous))
        }
    }
}

private struct HeartZonePulse: View {
    var isActive: Bool
    var intensity: Double
    var time: TimeInterval

    private var pulse: Double {
        (sin(time * 2.8) + 1) / 2
    }

    private var secondaryPulse: Double {
        (sin(time * 1.55 + 1.2) + 1) / 2
    }

    private var heartColor: Color {
        BodyZone.heart.accent
    }

    var body: some View {
        let activeOpacity = 0.22 + intensity * 0.22 + pulse * 0.10

        ZStack {
            Circle()
                .stroke(heartColor.opacity(isActive ? 0.16 * (1 - pulse) : 0), lineWidth: 1)
                .frame(width: 12 + CGFloat(pulse) * 36, height: 12 + CGFloat(pulse) * 36)

            Circle()
                .stroke(heartColor.opacity(isActive ? 0.10 * (1 - secondaryPulse) : 0), lineWidth: 1)
                .frame(width: 15 + CGFloat(secondaryPulse) * 30, height: 15 + CGFloat(secondaryPulse) * 30)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            heartColor.opacity(isActive ? activeOpacity : 0.035),
                            heartColor.opacity(isActive ? 0.11 + intensity * 0.08 : 0.018),
                            .clear
                        ],
                        center: .center,
                        startRadius: 1,
                        endRadius: 30
                    )
                )
                .frame(width: isActive ? 40 + CGFloat(pulse) * 6 : 24, height: isActive ? 40 + CGFloat(pulse) * 6 : 24)
                .blur(radius: 5)
                .blendMode(.screen)

            Image(systemName: "heart.fill")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(heartColor.opacity(isActive ? 0.52 : 0.14))
                .scaleEffect(isActive ? 0.94 + CGFloat(pulse) * 0.12 : 0.92)
                .shadow(color: heartColor.opacity(isActive ? 0.44 : 0.05), radius: 6)
        }
        .frame(width: 52, height: 52)
        .animation(.easeInOut(duration: 0.28), value: isActive)
    }
}

#Preview {
    ScrollView {
        FitnessBodyMapSection(
            analysis: BodyMapAnalyzer.analyze(
                activities: [
                    WeeklyActivity(
                        id: "preview-run",
                        workoutUUID: nil,
                        workoutType: "Running",
                        displayName: "Running",
                        category: .running,
                        startDate: .now,
                        endDate: .now.addingTimeInterval(2_700),
                        duration: 2_700,
                        calories: 340,
                        distanceMeters: 6_200,
                        averageHeartRate: 142,
                        maxHeartRate: 171,
                        source: .healthKit,
                        sourceName: "Preview"
                    )
                ]
            ),
            avatarType: .male
        )
        .padding(18)
    }
    .background(FitnessWeeklyBackground())
}
