//
//  HealthMonitorGlassSection.swift
//  Pulsar
//

import SwiftUI

struct HealthMonitorGlassSection: View {
    var summary: HealthMonitorSummary

    @State private var selectedMetric: HealthMetricModel?

    private let columns = [
        GridItem(.flexible(minimum: 0), spacing: 16, alignment: .top),
        GridItem(.flexible(minimum: 0), spacing: 16, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            glassMetricsGrid
        }
        .sheet(item: $selectedMetric) { metric in
            HealthMetricDetailSheet(metric: metric)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(34)
                .presentationContentInteraction(.scrolls)
                .presentationSizing(.page)
        }
    }

    @ViewBuilder
    private var glassMetricsGrid: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 16) {
                metricsGrid
            }
        } else {
            metricsGrid
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(summary.metrics) { metric in
                HealthMonitorGlassMetricCard(metric: metric) {
                    selectedMetric = metric
                }
            }
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                headerCopy
                Spacer(minLength: 4)
                signalBadge
            }

            VStack(alignment: .leading, spacing: 10) {
                headerCopy
                signalBadge
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var headerCopy: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Health Monitor")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)

            Text("Vitals and sleep signals")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var signalBadge: some View {
        HealthMonitorSignalBadge(
            availableCount: summary.availableMetricCount,
            totalCount: summary.metrics.count
        )
    }
}

private struct HealthMonitorSignalBadge: View {
    var availableCount: Int
    var totalCount: Int

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var tint: Color {
        availableCount > 0 ? Color(red: 0.12, green: 0.61, blue: 0.43) : .secondary
    }

    var body: some View {
        Text("\(availableCount)/\(totalCount) signals")
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        reduceTransparency
                            ? Color(.secondarySystemBackground)
                            : Color.white.opacity(colorScheme == .dark ? 0.07 : 0.56)
                    )
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.20 : 0.88),
                                tint.opacity(contrast == .increased ? 0.34 : 0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: contrast == .increased ? 1.2 : 0.75
                    )
            }
            .modifier(HealthMonitorBadgeGlassEffect(tint: tint, reduceTransparency: reduceTransparency))
            .accessibilityLabel("\(availableCount) of \(totalCount) health signals available")
    }
}

private struct HealthMonitorBadgeGlassEffect: ViewModifier {
    var tint: Color
    var reduceTransparency: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content.glassEffect(.regular.tint(tint.opacity(0.055)), in: .capsule)
        } else if !reduceTransparency {
            content.background(.thinMaterial, in: Capsule(style: .continuous))
        } else {
            content
        }
    }
}

private struct HealthMonitorGlassMetricCard: View {
    var metric: HealthMetricModel
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var identity: HealthMonitorMetricIdentity {
        HealthMonitorMetricIdentity(kind: metric.kind)
    }

    private var cardHeight: CGFloat {
        if dynamicTypeSize.isAccessibilitySize { return 224 }
        if dynamicTypeSize > .large { return 190 }
        return 172
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .trailing) {
                metricGlow

                VStack(alignment: .leading, spacing: 10) {
                    metricHeader
                    Spacer(minLength: 0)
                    valueRow
                    if metric.hasData {
                        statusRow
                    }
                }
                .padding(.trailing, 36)

                HealthMonitorVerticalIndicator(metric: metric, accent: identity.accent)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight, alignment: .topLeading)
            .contentShape(.rect(cornerRadius: 27))
            .modifier(HealthMonitorMetricGlassSurface(accent: identity.accent, cornerRadius: 27))
        }
        .buttonStyle(HealthMonitorGlassButtonStyle(glowColor: identity.accent))
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.accessibilityLabel)
        .accessibilityHint("Show more details")
    }

    private var metricHeader: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(identity.accent.opacity(colorScheme == .dark ? 0.18 : 0.10))

                Image(systemName: metric.systemImageName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(identity.iconGradient(colorScheme: colorScheme))
            }
            .frame(width: 36, height: 36)
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.64), lineWidth: 0.75)
            }

            Text(metric.abbreviation)
                .font(.headline.weight(.semibold))
                .foregroundStyle(metric.hasData ? Color.primary : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private var valueRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(metric.displayValueText)
                .font(metric.hasData ? .title2.weight(.semibold) : .headline.weight(.semibold))
                .foregroundStyle(metric.hasData ? Color.primary : Color.secondary.opacity(0.74))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.56)

            if metric.hasData, let unitText = metric.unitText {
                Text(unitText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            Image(systemName: metric.status.systemImageName)
                .font(.caption.weight(.bold))

            Text(metric.status.rawValue)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(metric.hasData ? identity.accent : Color.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.68)
    }

    private var metricGlow: some View {
        Circle()
            .fill(identity.accent.opacity(colorScheme == .dark ? 0.11 : 0.075))
            .frame(width: 92, height: 92)
            .blur(radius: 26)
            .offset(x: -34, y: -34)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct HealthMonitorMetricGlassSurface: ViewModifier {
    var accent: Color
    var cornerRadius: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                if reduceTransparency {
                    shape.fill(Color(.secondarySystemGroupedBackground))
                } else {
                    shape.fill(baseFill)
                }
            }
            .overlay {
                shape.fill(specularHighlight)
                    .allowsHitTesting(false)
            }
            .overlay {
                shape.stroke(borderGradient, lineWidth: contrast == .increased ? 1.25 : 0.8)
                    .allowsHitTesting(false)
            }
            .shadow(
                color: colorScheme == .dark ? .black.opacity(0.28) : .black.opacity(0.075),
                radius: colorScheme == .dark ? 18 : 14,
                y: 8
            )
            .modifier(
                HealthMonitorNativeGlassEffect(
                    accent: accent,
                    cornerRadius: cornerRadius,
                    reduceTransparency: reduceTransparency
                )
            )
    }

    private var baseFill: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.11, green: 0.13, blue: 0.18).opacity(0.78),
                    Color(red: 0.055, green: 0.07, blue: 0.11).opacity(0.70),
                    accent.opacity(0.055)
                ]
                : [
                    Color.white.opacity(0.76),
                    Color.white.opacity(0.56),
                    accent.opacity(0.035)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var specularHighlight: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.14 : 0.56),
                Color.white.opacity(colorScheme == .dark ? 0.025 : 0.10),
                accent.opacity(colorScheme == .dark ? 0.045 : 0.025)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.22 : 0.90),
                accent.opacity(contrast == .increased ? 0.34 : 0.17),
                Color.black.opacity(colorScheme == .dark ? 0.18 : 0.055)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct HealthMonitorNativeGlassEffect: ViewModifier {
    var accent: Color
    var cornerRadius: CGFloat
    var reduceTransparency: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content.glassEffect(
                .regular.tint(accent.opacity(0.055)).interactive(),
                in: .rect(cornerRadius: cornerRadius)
            )
        } else if !reduceTransparency {
            content.background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            content
        }
    }
}

private struct HealthMonitorVerticalIndicator: View {
    var metric: HealthMetricModel
    var accent: Color

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let trackTop: CGFloat = 13
            let trackHeight = max(1, proxy.size.height - trackTop * 2)

            ZStack {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.11 : 0.055))

                Capsule(style: .continuous)
                    .fill(metric.hasData ? accent.opacity(0.70) : Color.secondary.opacity(0.20))
                    .frame(width: 8, height: trackHeight)

                VStack(spacing: 0) {
                    indicatorCap
                    Spacer(minLength: 0)
                    indicatorCap
                }
                .padding(.vertical, 7)

                if metric.hasData {
                    Circle()
                        .fill(colorScheme == .dark ? Color(red: 0.10, green: 0.11, blue: 0.15) : .white)
                        .frame(width: 15, height: 15)
                        .overlay {
                            Circle().stroke(accent, lineWidth: 3)
                        }
                        .shadow(color: accent.opacity(0.34), radius: 7)
                        .position(
                            x: proxy.size.width / 2,
                            y: trackTop + trackHeight * positionFraction
                        )
                }
            }
        }
        .frame(width: 28, height: 112)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var indicatorCap: some View {
        Capsule(style: .continuous)
            .fill(metric.hasData ? accent.opacity(0.26) : Color.secondary.opacity(0.14))
            .frame(width: 13, height: 5)
    }

    private var positionFraction: CGFloat {
        switch metric.status {
        case .higher:
            0.18
        case .normal:
            0.50
        case .lower:
            0.82
        case .noData:
            0.50
        }
    }
}

private struct HealthMonitorMetricIdentity {
    var accent: Color
    var secondaryAccent: Color

    init(kind: HealthMetricKind) {
        switch kind {
        case .respiratoryRate:
            accent = Color(red: 0.24, green: 0.72, blue: 0.58)
            secondaryAccent = Color(red: 0.53, green: 0.89, blue: 0.77)
        case .restingHeartRate:
            accent = Color(red: 0.08, green: 0.64, blue: 0.37)
            secondaryAccent = Color(red: 0.42, green: 0.84, blue: 0.57)
        case .hrv:
            accent = Color(red: 0.31, green: 0.43, blue: 0.91)
            secondaryAccent = Color(red: 0.51, green: 0.46, blue: 0.94)
        case .oxygenSaturation:
            accent = Color(red: 0.04, green: 0.64, blue: 0.69)
            secondaryAccent = Color(red: 0.28, green: 0.84, blue: 0.79)
        case .wristTemperature:
            accent = Color(red: 0.94, green: 0.42, blue: 0.17)
            secondaryAccent = Color(red: 1.00, green: 0.66, blue: 0.34)
        case .sleep:
            accent = Color(red: 0.37, green: 0.34, blue: 0.87)
            secondaryAccent = Color(red: 0.59, green: 0.50, blue: 0.96)
        }
    }

    func iconGradient(colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [
                colorScheme == .dark ? secondaryAccent : accent,
                secondaryAccent
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct HealthMonitorGlassButtonStyle: ButtonStyle {
    var glowColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.982 : 1)
            .brightness(configuration.isPressed ? 0.025 : 0)
            .shadow(color: glowColor.opacity(configuration.isPressed ? 0.16 : 0), radius: 14, y: 7)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

#Preview("Health Monitor — Light") {
    ScrollView {
        HealthMonitorGlassSection(summary: MockHealthData.healthMonitorSummary)
            .padding(22)
    }
    .background(Color(.systemGroupedBackground))
    .preferredColorScheme(.light)
}

#Preview("Health Monitor — Dark") {
    ScrollView {
        HealthMonitorGlassSection(summary: MockHealthData.healthMonitorSummary)
            .padding(22)
    }
    .background(Color(.systemGroupedBackground))
    .preferredColorScheme(.dark)
}

#Preview("Health Monitor — Compact", traits: .fixedLayout(width: 375, height: 667)) {
    ScrollView {
        HealthMonitorGlassSection(summary: MockHealthData.healthMonitorSummary)
            .padding(22)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Health Monitor — Pro Max", traits: .fixedLayout(width: 430, height: 932)) {
    ScrollView {
        HealthMonitorGlassSection(summary: MockHealthData.healthMonitorSummary)
            .padding(22)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Health Monitor — No Data") {
    ScrollView {
        HealthMonitorGlassSection(summary: .missing())
            .padding(22)
    }
    .background(Color(.systemGroupedBackground))
}
