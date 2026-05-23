import SwiftUI
import WidgetKit

struct PulsarMainMetricsWidgetView: View {
    let entry: PulsarWidgetEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        PulsarWidgetSurface(accent: Color(red: 0.42, green: 0.56, blue: 0.98)) {
            if entry.snapshot.hasMetricData {
                switch family {
                case .systemSmall:
                    MainMetricsSmallLayout(snapshot: entry.snapshot)
                case .systemMedium:
                    MainMetricsMediumLayout(snapshot: entry.snapshot)
                default:
                    MainMetricsLargeLayout(snapshot: entry.snapshot)
                }
            } else {
                PulsarWidgetEmptyStateView(
                    usesBrandMark: true,
                    title: "Pulsar Metrics",
                    message: entry.snapshot.emptyMessage
                )
            }
        }
    }
}

struct PulsarStressWidgetView: View {
    let entry: PulsarWidgetEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        let snapshot = entry.snapshot.stress
        let accent = WidgetStressPalette.tint(for: snapshot.score)

        PulsarWidgetSurface(accent: accent) {
            if entry.snapshot.hasStressData {
                switch family {
                case .systemSmall:
                    StressSmallLayout(snapshot: snapshot)
                case .systemMedium:
                    StressMediumLayout(snapshot: snapshot)
                default:
                    StressLargeLayout(snapshot: snapshot)
                }
            } else {
                PulsarWidgetEmptyStateView(
                    systemIcon: "waveform.path.ecg",
                    title: "Stress",
                    message: entry.snapshot.emptyMessage
                )
            }
        }
    }
}

private struct MainMetricsSmallLayout: View {
    let snapshot: PulsarWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(title: "Metrics", updatedAt: snapshot.lastUpdated)

            HStack(spacing: 6) {
                ForEach(PulsarWidgetMetricKind.allCases) { kind in
                    MetricCircleWidgetView(metric: snapshot.metric(kind), style: .compact)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

private struct MainMetricsMediumLayout: View {
    let snapshot: PulsarWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WidgetHeader(title: "Pulsar Metrics", updatedAt: snapshot.lastUpdated)

            HStack(spacing: 8) {
                ForEach(PulsarWidgetMetricKind.allCases) { kind in
                    MetricCircleWidgetView(metric: snapshot.metric(kind), style: .regular, showsPanel: true)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

private struct MainMetricsLargeLayout: View {
    let snapshot: PulsarWidgetSnapshot
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WidgetHeader(title: "Pulsar Metrics", updatedAt: snapshot.lastUpdated)

            HStack(spacing: 10) {
                ForEach(PulsarWidgetMetricKind.allCases) { kind in
                    MetricCircleWidgetView(metric: snapshot.metric(kind), style: .prominent, showsPanel: true)
                }
            }

            Text("Your three core Pulsar scores, refreshed from the latest saved Health metrics.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(WidgetTextPalette.secondary(colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}

private struct StressSmallLayout: View {
    let snapshot: PulsarWidgetStressSnapshot
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Text("Stress")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(WidgetTextPalette.primary(colorScheme))

            StressRingWidgetView(snapshot: snapshot, size: 100)

            StatusPill(text: snapshot.statusText, tint: WidgetStressPalette.tint(for: snapshot.score))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct StressMediumLayout: View {
    let snapshot: PulsarWidgetStressSnapshot
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            StressRingWidgetView(snapshot: snapshot, size: 106)

            VStack(alignment: .leading, spacing: 8) {
                WidgetHeader(title: "Stress", updatedAt: snapshot.updatedAt)

                StatusPill(text: snapshot.statusText, tint: WidgetStressPalette.tint(for: snapshot.score))

                if let insightText = snapshot.insightText {
                    Text(insightText)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(WidgetTextPalette.secondary(colorScheme))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
    }
}

private struct StressLargeLayout: View {
    let snapshot: PulsarWidgetStressSnapshot
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WidgetHeader(title: "Stress", updatedAt: snapshot.updatedAt)

            HStack(alignment: .center, spacing: 14) {
                StressRingWidgetView(snapshot: snapshot, size: 136)

                VStack(alignment: .leading, spacing: 8) {
                    StatusPill(text: snapshot.statusText, tint: WidgetStressPalette.tint(for: snapshot.score))

                    if let insightText = snapshot.insightText {
                        Text(insightText)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(WidgetTextPalette.primary(colorScheme))
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(snapshot.state == .ready ? "Estimated from the latest wearable signals and your recent baseline." : "Open Pulsar for a deeper stress breakdown and live context.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(WidgetTextPalette.tertiary(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

private struct MetricCircleWidgetView: View {
    enum Style: Equatable {
        case compact
        case regular
        case prominent

        var ringSize: CGFloat {
            switch self {
            case .compact:
                return 46
            case .regular:
                return 56
            case .prominent:
                return 62
            }
        }

        var ringWidth: CGFloat {
            switch self {
            case .compact:
                return 6
            case .regular:
                return 7
            case .prominent:
                return 8
            }
        }

        var scoreFontSize: CGFloat {
            switch self {
            case .compact:
                return 15
            case .regular:
                return 17
            case .prominent:
                return 19
            }
        }

        var labelFontSize: CGFloat {
            switch self {
            case .compact:
                return 9
            case .regular:
                return 10
            case .prominent:
                return 11
            }
        }

        var detailFontSize: CGFloat {
            switch self {
            case .compact:
                return 0
            case .regular:
                return 11
            case .prominent:
                return 12
            }
        }

        var detailLineLimit: Int {
            switch self {
            case .compact:
                return 0
            case .regular:
                return 2
            case .prominent:
                return 2
            }
        }

        var panelPadding: CGFloat {
            switch self {
            case .compact:
                return 0
            case .regular:
                return 8
            case .prominent:
                return 9
            }
        }
    }

    let metric: PulsarWidgetMetricSnapshot
    let style: Style
    var showsPanel = false

    @Environment(\.colorScheme) private var colorScheme

    private var tint: Color {
        WidgetMetricPalette.tint(for: metric.kind)
    }

    private var progress: Double {
        Double(metric.score ?? 0) / 100
    }

    var body: some View {
        VStack(spacing: style == .compact ? 5 : 8) {
            ZStack {
                Circle()
                    .stroke(trackColor, style: StrokeStyle(lineWidth: style.ringWidth, lineCap: .round))

                if progress >= 0.995 {
                    Circle()
                        .stroke(metricGradient, style: StrokeStyle(lineWidth: style.ringWidth, lineCap: .round))
                } else {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(metricGradient, style: StrokeStyle(lineWidth: style.ringWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }

                Circle()
                    .fill(centerFill)
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.55), lineWidth: 0.8)
                    }
                    .padding(style.ringWidth + 4)

                VStack(spacing: 2) {
                    Image(systemName: metric.kind.systemImageName)
                        .font(.system(size: style.labelFontSize + 1, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint.opacity(metric.isAvailable ? 1 : 0.55))
                        .symbolRenderingMode(.hierarchical)

                    Text(metric.score.map(String.init) ?? "--")
                        .font(.system(size: style.scoreFontSize, weight: .bold, design: .rounded))
                        .foregroundStyle((metric.isAvailable ? WidgetTextPalette.primary(colorScheme) : WidgetTextPalette.secondary(colorScheme)).opacity(metric.isAvailable ? 1 : 0.86))
                        .monospacedDigit()
                        .minimumScaleFactor(0.65)
                }
            }
            .frame(width: style.ringSize, height: style.ringSize)
            .shadow(color: tint.opacity(0.22), radius: showsPanel ? 10 : 6, y: 3)

            Text(metric.kind.title)
                .font(.system(size: style.labelFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(WidgetTextPalette.primary(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if style != .compact {
                Text(metric.detailText)
                    .font(.system(size: style.detailFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(WidgetTextPalette.secondary(colorScheme))
                    .lineLimit(style.detailLineLimit)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let secondaryText = metric.secondaryText {
                    Text(secondaryText)
                        .font(.system(size: style.detailFontSize - 1, weight: .medium, design: .rounded))
                        .foregroundStyle(WidgetTextPalette.tertiary(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(showsPanel ? style.panelPadding : 0)
        .background {
            if showsPanel {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(colorScheme == .dark ? 0.18 : 0.14),
                                Color.white.opacity(colorScheme == .dark ? 0.06 : 0.22),
                                Color.black.opacity(colorScheme == .dark ? 0.12 : 0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.28), lineWidth: 1)
                    }
            }
        }
    }

    private var metricGradient: LinearGradient {
        LinearGradient(
            colors: [
                tint.opacity(0.70),
                tint,
                Color.white.opacity(0.85)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var centerFill: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.12 : 0.72),
                tint.opacity(colorScheme == .dark ? 0.10 : 0.16),
                Color.black.opacity(colorScheme == .dark ? 0.12 : 0.02)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var trackColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }
}

private struct StressRingWidgetView: View {
    let snapshot: PulsarWidgetStressSnapshot
    let size: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    private let startAngle = 128.0
    private let endAngle = 412.0

    private var tint: Color {
        WidgetStressPalette.tint(for: snapshot.score)
    }

    private var progress: Double {
        Double(snapshot.score ?? 0) / 100
    }

    private var ringWidth: CGFloat {
        size * 0.078
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            tint.opacity(0.22),
                            tint.opacity(0.05),
                            .clear
                        ],
                        center: .center,
                        startRadius: 12,
                        endRadius: size * 0.58
                    )
                )
                .blur(radius: size * 0.05)

            StressHaloArc(progress: 1, startAngle: startAngle, endAngle: endAngle, inset: ringWidth / 2)
                .stroke(trackColor, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))

            if snapshot.score != nil {
                StressHaloArc(progress: progress, startAngle: startAngle, endAngle: endAngle, inset: ringWidth / 2)
                    .stroke(
                        LinearGradient(
                            colors: WidgetStressPalette.gradient(for: snapshot.score),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                    )
                    .shadow(color: tint.opacity(0.28), radius: 10, y: 3)
            }

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.14 : 0.88),
                            tint.opacity(colorScheme == .dark ? 0.10 : 0.14),
                            Color.black.opacity(colorScheme == .dark ? 0.12 : 0.03)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.15 : 0.48), lineWidth: 1)
                }
                .frame(width: size * 0.60, height: size * 0.60)

            VStack(spacing: 4) {
                Text(centerScoreText)
                    .font(.system(size: snapshot.score == nil ? size * 0.10 : size * 0.18, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetTextPalette.primary(colorScheme))
                    .minimumScaleFactor(0.55)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(snapshot.statusText)
                    .font(.system(size: size * 0.062, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: size * 0.46)
        }
        .frame(width: size, height: size)
    }

    private var centerScoreText: String {
        if let score = snapshot.score {
            return "\(score)%"
        }
        switch snapshot.state {
        case .buildingBaseline:
            return "Baseline"
        case .paused:
            return "Paused"
        case .ready:
            return "--"
        case .noData:
            return "Open"
        }
    }

    private var trackColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }
}

private struct StatusPill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.14), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(tint.opacity(0.18), lineWidth: 0.8)
            }
    }
}

private struct PulsarWidgetEmptyStateView: View {
    var systemIcon: String?
    var usesBrandMark = false
    let title: String
    let message: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if usesBrandMark {
                Image(brandMarkAssetName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 18, height: 28)
                    .accessibilityHidden(true)
            } else if let systemIcon {
                Image(systemName: systemIcon)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetTextPalette.primary(colorScheme))
            }

            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(WidgetTextPalette.primary(colorScheme))

            Text(message)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(WidgetTextPalette.secondary(colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var brandMarkAssetName: String {
        colorScheme == .dark ? "PulsarLogoDark" : "PulsarLogo"
    }
}

private struct PulsarWidgetSurface<Content: View>: View {
    let accent: Color
    let content: Content

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetFamily) private var family

    init(accent: Color, @ViewBuilder content: () -> Content) {
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        content
            .padding(contentInsets)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(for: .widget) {
                ZStack {
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [
                                Color(red: 0.09, green: 0.11, blue: 0.17),
                                Color(red: 0.05, green: 0.07, blue: 0.12),
                                accent.opacity(0.16)
                            ]
                            : [
                                Color.white,
                                Color(red: 0.94, green: 0.96, blue: 1.00),
                                accent.opacity(0.10)
                            ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Circle()
                        .fill(accent.opacity(colorScheme == .dark ? 0.18 : 0.10))
                        .frame(width: 150, height: 150)
                        .blur(radius: 34)
                        .offset(x: 70, y: -70)

                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.36), lineWidth: 1)
                }
            }
    }

    private var contentInsets: EdgeInsets {
        switch family {
        case .systemSmall:
            return EdgeInsets(top: 6, leading: 4, bottom: 4, trailing: 4)
        case .systemMedium:
            return EdgeInsets(top: 8, leading: 6, bottom: 6, trailing: 6)
        default:
            return EdgeInsets(top: 10, leading: 8, bottom: 8, trailing: 8)
        }
    }
}

private struct StressHaloArc: Shape {
    var progress: Double
    var startAngle: Double
    var endAngle: Double
    var inset: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard progress > 0.0001 else { return path }
        let radius = max(0, min(rect.width, rect.height) / 2 - inset)
        let clamped = min(max(progress, 0), 1)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let resolvedEnd = startAngle + (endAngle - startAngle) * clamped

        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startAngle),
            endAngle: .degrees(resolvedEnd),
            clockwise: false
        )

        return path
    }
}

private enum WidgetMetricPalette {
    static func tint(for kind: PulsarWidgetMetricKind) -> Color {
        switch kind {
        case .sleep:
            return Color(red: 0.47, green: 0.57, blue: 0.98)
        case .recovery:
            return Color(red: 0.34, green: 0.84, blue: 0.58)
        case .strain:
            return Color(red: 0.98, green: 0.62, blue: 0.22)
        }
    }
}

private enum WidgetStressPalette {
    static func tint(for score: Int?) -> Color {
        guard let score else {
            return Color(red: 0.65, green: 0.70, blue: 0.82)
        }
        switch score {
        case 0..<25:
            return Color(red: 0.25, green: 0.80, blue: 0.58)
        case 25..<50:
            return Color(red: 0.35, green: 0.74, blue: 0.95)
        case 50..<75:
            return Color(red: 0.95, green: 0.68, blue: 0.25)
        default:
            return Color(red: 1.00, green: 0.40, blue: 0.30)
        }
    }

    static func gradient(for score: Int?) -> [Color] {
        let tint = tint(for: score)
        return [Color.white.opacity(0.86), tint, tint.opacity(0.72)]
    }
}

private struct WidgetHeader: View {
    let title: String
    let updatedAt: Date?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 6) {
                Image(brandMarkAssetName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 11, height: 18)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetTextPalette.primary(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)

            if let updatedAt {
                Text(updatedAt, style: .time)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetTextPalette.tertiary(colorScheme))
                    .lineLimit(1)
            }
        }
    }

    private var brandMarkAssetName: String {
        colorScheme == .dark ? "PulsarLogoDark" : "PulsarLogo"
    }
}

private enum WidgetTextPalette {
    static func primary(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white.opacity(0.96) : Color(red: 0.11, green: 0.13, blue: 0.18)
    }

    static func secondary(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white.opacity(0.76) : Color(red: 0.29, green: 0.33, blue: 0.41)
    }

    static func tertiary(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white.opacity(0.60) : Color(red: 0.42, green: 0.46, blue: 0.54)
    }
}

#Preview("Metrics Small", as: .systemSmall) {
    PulsarMainMetricsWidget()
} timeline: {
    PulsarWidgetEntry(date: .now, snapshot: .preview)
}

#Preview("Metrics Medium", as: .systemMedium) {
    PulsarMainMetricsWidget()
} timeline: {
    PulsarWidgetEntry(date: .now, snapshot: .preview)
}

#Preview("Metrics Large", as: .systemLarge) {
    PulsarMainMetricsWidget()
} timeline: {
    PulsarWidgetEntry(date: .now, snapshot: .preview)
}

#Preview("Stress Medium", as: .systemMedium) {
    PulsarStressWidget()
} timeline: {
    PulsarWidgetEntry(date: .now, snapshot: .preview)
}
