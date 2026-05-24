//
//  MindfulnessComponents.swift
//  Pulsar
//

import SwiftUI

struct PulsarMindfulnessGlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 28
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pulsarLiquidGlass(cornerRadius: cornerRadius)
    }
}

struct MindfulnessPageTitleHeader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 11) {
            Image(systemName: "figure.mind.and.body")
                .font(.system(size: 29, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .scaleEffect(isBreathing && !reduceMotion ? 1.045 : 1)
                .opacity(isBreathing && !reduceMotion ? 0.82 : 1)
                .frame(width: 34, height: 30)
                .alignmentGuide(.firstTextBaseline) { dimensions in
                    dimensions[VerticalAlignment.center] + 7
                }
                .accessibilityHidden(true)

            Text("Mindfulness")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mindfulness")
        .accessibilityAddTraits(.isHeader)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }
}

struct MindfulnessTodayCard: View {
    var dashboard: PulsarMindfulnessDashboard
    var onCheckIn: () -> Void
    var onStartBreathing: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        PulsarMindfulnessGlassCard(cornerRadius: 30) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    MindfulnessBalanceHalo(entry: dashboard.todayEntry)
                        .frame(width: 78, height: 78)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Emotional Balance")
                            .font(.title3.weight(.bold))
                        Text(balanceCopy)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 4)
                }

                HStack(spacing: 10) {
                    Button(action: onCheckIn) {
                        Label(dashboard.todayEntry == nil ? "Check in" : "Update", systemImage: "slider.horizontal.3")
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(PulsarMindfulnessActionButtonStyle(tint: balanceTint))

                    Button(action: onStartBreathing) {
                        Image(systemName: "lungs.fill")
                            .font(.headline.weight(.bold))
                            .frame(width: 52, height: 52)
                    }
                    .buttonStyle(PulsarMindfulnessIconButtonStyle(tint: .blue))
                    .accessibilityLabel("Start breathing")
                }

                HStack(spacing: 10) {
                    MindfulnessMetricPill(
                        title: "Streak",
                        value: dashboard.streak.currentStreak == 1 ? "1 day" : "\(dashboard.streak.currentStreak) days",
                        symbolName: "flame.fill",
                        tint: .orange
                    )
                    MindfulnessMetricPill(
                        title: "This week",
                        value: "\(Int(dashboard.weeklyMindfulMinutes.rounded())) min",
                        symbolName: "timer",
                        tint: .teal
                    )
                }
            }
        }
    }

    private var balanceCopy: String {
        guard let entry = dashboard.todayEntry else {
            return "A low-friction reflection is ready when your day has enough shape."
        }

        let mood = entry.moodTitle.lowercased()
        if entry.stress > 0.62 {
            return "Today feels \(mood), with stress asking for a little extra space."
        }
        if entry.gratitude > 0.68 {
            return "Today feels \(mood), with gratitude clearly present."
        }
        return "Today feels \(mood). Pulsar will keep the signal simple until patterns emerge."
    }

    private var balanceTint: Color {
        guard let entry = dashboard.todayEntry else { return .blue }
        if entry.valence >= 0.25 { return .green }
        if entry.stress > 0.62 { return .orange }
        return .blue
    }
}

struct MindfulnessBalanceHalo: View {
    var entry: PulsarDailyJournalEntry?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    var body: some View {
        ZStack {
            Circle()
                .fill(haloFill)
                .blur(radius: 8)
                .scaleEffect(phase && !reduceMotion ? 1.08 : 0.96)

            Circle()
                .stroke(haloStroke, lineWidth: 1.4)
                .padding(5)

            Image(systemName: entry == nil ? "sparkles" : "heart.text.square.fill")
                .font(.system(size: 24, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconTint)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                phase = true
            }
        }
    }

    private var iconTint: Color {
        guard let entry else { return .blue }
        return entry.valence >= 0 ? .green : .orange
    }

    private var haloFill: RadialGradient {
        RadialGradient(
            colors: [
                iconTint.opacity(0.34),
                iconTint.opacity(0.14),
                Color.white.opacity(0.03)
            ],
            center: .center,
            startRadius: 5,
            endRadius: 42
        )
    }

    private var haloStroke: LinearGradient {
        LinearGradient(
            colors: [.white.opacity(0.66), iconTint.opacity(0.42), .white.opacity(0.08)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct MindfulnessMetricPill: View {
    var title: String
    var value: String
    var symbolName: String
    var tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbolName)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.13), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline.weight(.bold))
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }
}

struct MindfulnessTrendCard: View {
    var points: [PulsarMindfulnessTrendPoint]

    var body: some View {
        PulsarMindfulnessGlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mood constellation")
                            .font(.headline.weight(.bold))
                        Text("Seven-day signal")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chart.xyaxis.line")
                        .font(.headline)
                        .foregroundStyle(.blue)
                }

                MoodConstellationChart(points: points)
                    .frame(height: 120)

                ConsistencyStrip(points: points)
            }
        }
    }
}

struct MoodConstellationChart: View {
    var points: [PulsarMindfulnessTrendPoint]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.07))

                Path { path in
                    let midY = proxy.size.height / 2
                    path.move(to: CGPoint(x: 12, y: midY))
                    path.addLine(to: CGPoint(x: max(12, proxy.size.width - 12), y: midY))
                }
                .stroke(.secondary.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))

                ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                    let position = position(for: point, index: index, size: proxy.size)
                    Circle()
                        .fill(color(for: point))
                        .frame(width: point.hasCheckIn ? 12 : 7, height: point.hasCheckIn ? 12 : 7)
                        .shadow(color: color(for: point).opacity(0.32), radius: 8)
                        .position(position)
                }
            }
        }
        .accessibilityLabel("Seven day mood constellation")
    }

    private func position(for point: PulsarMindfulnessTrendPoint, index: Int, size: CGSize) -> CGPoint {
        let count = max(points.count - 1, 1)
        let x = 18 + (size.width - 36) * CGFloat(index) / CGFloat(count)
        let normalized = CGFloat((point.valence ?? 0) + 1) / 2
        let y = 18 + (size.height - 36) * (1 - normalized)
        return CGPoint(x: x, y: y)
    }

    private func color(for point: PulsarMindfulnessTrendPoint) -> Color {
        guard let valence = point.valence else {
            return .secondary.opacity(0.36)
        }
        if valence > 0.22 { return .green }
        if valence < -0.22 { return .orange }
        return .blue
    }
}

struct ConsistencyStrip: View {
    var points: [PulsarMindfulnessTrendPoint]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(points) { point in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fill(for: point))
                    .frame(height: 8)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(.white.opacity(point.hasCheckIn ? 0.14 : 0.06), lineWidth: 1)
                    }
                    .accessibilityLabel(point.hasCheckIn ? "Check-in logged" : "No check-in")
            }
        }
    }

    private func fill(for point: PulsarMindfulnessTrendPoint) -> Color {
        if point.hasCheckIn && point.mindfulMinutes > 0 { return .green.opacity(0.72) }
        if point.hasCheckIn { return .blue.opacity(0.62) }
        if point.mindfulMinutes > 0 { return .teal.opacity(0.52) }
        return .secondary.opacity(0.18)
    }
}

struct MindfulnessTemplateCard: View {
    var template: PulsarMeditationTemplate
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top) {
                    Image(systemName: template.category.symbolName)
                        .font(.system(size: 19, weight: .bold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(template.category.accent)
                        .frame(width: 42, height: 42)
                        .background(template.category.accent.opacity(colorScheme == .dark ? 0.20 : 0.13), in: Circle())
                    Spacer(minLength: 0)
                    Text(template.durationText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(template.category.accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(template.category.accent.opacity(colorScheme == .dark ? 0.14 : 0.10), in: Capsule())
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(template.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(template.category.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(template.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 162, alignment: .leading)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(cardBorder, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PulsarMindfulnessPressStyle(glowColor: template.category.accent))
        .accessibilityLabel("\(template.title), \(template.durationText)")
    }

    private var cardBackground: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [.white.opacity(0.09), .white.opacity(0.04), template.category.accent.opacity(0.11)]
                : [.white.opacity(0.88), Color(red: 0.96, green: 0.98, blue: 1.00).opacity(0.82), template.category.accent.opacity(0.08)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBorder: LinearGradient {
        LinearGradient(
            colors: [.white.opacity(colorScheme == .dark ? 0.18 : 0.74), template.category.accent.opacity(0.24), .black.opacity(colorScheme == .dark ? 0.18 : 0.05)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct PulsarMindfulnessInsightCard: View {
    var insight: PulsarEmotionalInsight

    var body: some View {
        PulsarMindfulnessGlassCard(cornerRadius: 24) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: insight.symbolName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(insight.tint.color)
                    .frame(width: 38, height: 38)
                    .background(insight.tint.color.opacity(0.13), in: Circle())

                VStack(alignment: .leading, spacing: 7) {
                    Text(insight.title)
                        .font(.headline.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(insight.body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(insight.evidence)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
        }
    }
}

struct PulsarMindfulnessActionButtonStyle: ButtonStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [tint.opacity(0.95), tint.opacity(0.72)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule(style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .shadow(color: tint.opacity(configuration.isPressed ? 0.28 : 0.16), radius: 18, y: 8)
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

struct PulsarMindfulnessIconButtonStyle: ButtonStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tint)
            .background(tint.opacity(0.13), in: Circle())
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.76), value: configuration.isPressed)
    }
}

struct PulsarMindfulnessPressStyle: ButtonStyle {
    var glowColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? 0.035 : 0)
            .shadow(color: glowColor.opacity(configuration.isPressed ? 0.22 : 0), radius: 18, y: 8)
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: configuration.isPressed)
    }
}
