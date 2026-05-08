//
//  HealthMonitorSection.swift
//  Pulsar
//

import SwiftUI

struct HealthMonitorSection: View {
    var summary: HealthMonitorSummary

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedMetric: HealthMetricModel?

    private let columns = [
        GridItem(.flexible(), spacing: 12, alignment: .top),
        GridItem(.flexible(), spacing: 12, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(summary.metrics) { metric in
                    HealthMetricCard(metric: metric) {
                        selectedMetric = metric
                    }
                }
            }
        }
        .sheet(item: $selectedMetric) { metric in
            HealthMetricDetailSheet(metric: metric)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Health Monitor")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(primaryText)
                Text("Vitals and sleep signals for the selected day.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Text(summary.availableMetricCount > 0 ? "\(summary.availableMetricCount) live" : "Waiting")
                .font(.caption.weight(.bold))
                .foregroundStyle(summary.availableMetricCount > 0 ? Color.green.opacity(0.92) : secondaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(summary.availableMetricCount > 0 ? Color.green.opacity(colorScheme == .dark ? 0.14 : 0.10) : Color.white.opacity(colorScheme == .dark ? 0.06 : 0.58))
                )
        }
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.97) : Color(red: 0.08, green: 0.10, blue: 0.15)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.62) : Color(red: 0.34, green: 0.38, blue: 0.46)
    }
}

struct HealthMetricCard: View {
    var metric: HealthMetricModel
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: metric.systemImageName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(accentGradient)
                            .frame(width: 38, height: 38)
                            .background(iconBackground, in: Circle())

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(secondaryText.opacity(0.75))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(metric.abbreviation)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(primaryText)
                        Text(metric.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(secondaryText)
                            .lineLimit(2)
                    }

                    valueBlock

                    HStack(spacing: 6) {
                        Image(systemName: metric.status.systemImageName)
                            .font(.caption.weight(.bold))
                        Text(metric.status.rawValue)
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(statusColor.opacity(colorScheme == .dark ? 0.13 : 0.10), in: Capsule())

                    Text(metric.comparisonText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VerticalHealthIndicator(metric: metric)
                    .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 184, alignment: .leading)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(cardBorder)
            .shadow(color: shadowColor, radius: colorScheme == .dark ? 18 : 12, y: 8)
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(HealthMetricCardButtonStyle(glowColor: statusColor))
        .accessibilityLabel(metric.accessibilityLabel)
        .accessibilityHint("Show more details")
    }

    @ViewBuilder
    private var valueBlock: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(metric.displayValueText)
                .font(metric.hasData ? .system(size: 26, weight: .bold, design: .rounded) : .system(.headline, design: .rounded).weight(.semibold))
                .foregroundStyle(primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            if let unitText = metric.unitText {
                Text(unitText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.97) : Color(red: 0.08, green: 0.10, blue: 0.15)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.62) : Color(red: 0.34, green: 0.38, blue: 0.46)
    }

    private var statusColor: Color {
        palette.accent
    }

    private var accentGradient: LinearGradient {
        LinearGradient(
            colors: [
                colorScheme == .dark ? Color.white.opacity(0.94) : Color(red: 0.12, green: 0.15, blue: 0.22),
                palette.accent
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var iconBackground: LinearGradient {
        LinearGradient(
            colors: [
                palette.accent.opacity(colorScheme == .dark ? 0.22 : 0.12),
                Color.white.opacity(colorScheme == .dark ? 0.08 : 0.72)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [
                            Color(red: 0.10, green: 0.12, blue: 0.19).opacity(0.88),
                            Color(red: 0.05, green: 0.07, blue: 0.12).opacity(0.92),
                            palette.accent.opacity(0.12)
                        ]
                        : [
                            Color.white.opacity(0.92),
                            Color(red: 0.95, green: 0.97, blue: 1.00).opacity(0.88),
                            palette.accent.opacity(0.08)
                        ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.18 : 0.88),
                        palette.accent.opacity(colorScheme == .dark ? 0.16 : 0.22),
                        Color.black.opacity(colorScheme == .dark ? 0.16 : 0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    private var shadowColor: Color {
        colorScheme == .dark ? .black.opacity(0.23) : .black.opacity(0.08)
    }

    private var palette: HealthMetricPalette {
        HealthMetricPalette(metric: metric, colorScheme: colorScheme)
    }
}

struct VerticalHealthIndicator: View {
    var metric: HealthMetricModel

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: alignment) {
            Capsule(style: .continuous)
                .fill(trackFill)
                .frame(width: 12, height: 88)
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(colorScheme == .dark ? 0.12 : 0.42), lineWidth: 1)
                }

            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            palette.accent.opacity(0.92),
                            palette.accent.opacity(0.54)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 6, height: metric.status == .noData ? 14 : 24)
                .padding(.vertical, 8)
                .shadow(color: palette.accent.opacity(colorScheme == .dark ? 0.36 : 0.18), radius: 8, y: 0)
        }
        .accessibilityHidden(true)
    }

    private var alignment: Alignment {
        switch metric.status {
        case .higher:
            .top
        case .lower:
            .bottom
        case .normal, .noData:
            .center
        }
    }

    private var trackFill: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.08 : 0.76),
                Color.black.opacity(colorScheme == .dark ? 0.18 : 0.04)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var palette: HealthMetricPalette {
        HealthMetricPalette(metric: metric, colorScheme: colorScheme)
    }
}

private struct HealthMetricDetailSheet: View {
    var metric: HealthMetricModel

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Capsule(style: .continuous)
                    .fill(.secondary.opacity(colorScheme == .dark ? 0.34 : 0.20))
                    .frame(width: 42, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)

                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: metric.systemImageName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(accentGradient)
                        .frame(width: 52, height: 52)
                        .background(iconBackground, in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(metric.title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(primaryText)
                        Text(metric.abbreviation)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(secondaryText)
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 6) {
                        Image(systemName: metric.status.systemImageName)
                            .font(.caption.weight(.bold))
                        Text(metric.status.rawValue)
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(palette.accent.opacity(colorScheme == .dark ? 0.13 : 0.10), in: Capsule())
                }

                Text(metric.detailValueText)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(primaryText)
                    .monospacedDigit()

                Text(metric.descriptionText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HealthMetricDetailCard(title: "Trend", value: metric.comparisonText)

                if let referenceValueText = metric.referenceValueText {
                    HealthMetricDetailCard(title: "Reference", value: referenceValueText)
                }

                if let lastUpdated = metric.lastUpdated {
                    HealthMetricDetailCard(
                        title: "Latest Sample",
                        value: lastUpdated.formatted(date: .abbreviated, time: .shortened)
                    )
                }

                HealthMetricDetailCard(
                    title: "Data Source",
                    value: metric.sourceBadges.isEmpty ? "HealthKit" : metric.sourceBadges.map(\.displayName).joined(separator: ", ")
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(sheetBackground)
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.97) : Color(red: 0.08, green: 0.10, blue: 0.15)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.62) : Color(red: 0.34, green: 0.38, blue: 0.46)
    }

    private var sheetBackground: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.06, green: 0.08, blue: 0.14),
                    Color(red: 0.03, green: 0.05, blue: 0.10)
                ]
                : [
                    Color.white,
                    Color(red: 0.95, green: 0.97, blue: 1.00)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var accentGradient: LinearGradient {
        LinearGradient(
            colors: [
                colorScheme == .dark ? Color.white.opacity(0.94) : Color(red: 0.12, green: 0.15, blue: 0.22),
                palette.accent
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var iconBackground: LinearGradient {
        LinearGradient(
            colors: [
                palette.accent.opacity(colorScheme == .dark ? 0.22 : 0.12),
                Color.white.opacity(colorScheme == .dark ? 0.08 : 0.72)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var palette: HealthMetricPalette {
        HealthMetricPalette(metric: metric, colorScheme: colorScheme)
    }
}

private struct HealthMetricDetailCard: View {
    var title: String
    var value: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.94) : Color(red: 0.08, green: 0.10, blue: 0.15))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.70))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(colorScheme == .dark ? 0.10 : 0.30), lineWidth: 1)
        }
    }
}

private struct HealthMetricCardButtonStyle: ButtonStyle {
    var glowColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .brightness(configuration.isPressed ? 0.03 : 0)
            .shadow(color: glowColor.opacity(configuration.isPressed ? 0.20 : 0), radius: 14, y: 8)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

private struct HealthMetricPalette {
    var accent: Color

    init(metric: HealthMetricModel, colorScheme: ColorScheme) {
        switch metric.status {
        case .noData:
            self.accent = colorScheme == .dark ? Color.white.opacity(0.32) : Color(red: 0.52, green: 0.56, blue: 0.64)
        case .normal:
            self.accent = Color(red: 0.36, green: 0.86, blue: 0.58)
        case .higher:
            switch metric.kind {
            case .hrv, .sleep:
                self.accent = Color(red: 0.40, green: 0.74, blue: 1.00)
            case .wristTemperature:
                self.accent = Color(red: 1.00, green: 0.54, blue: 0.38)
            default:
                self.accent = Color(red: 1.00, green: 0.67, blue: 0.34)
            }
        case .lower:
            switch metric.kind {
            case .restingHeartRate:
                self.accent = Color(red: 0.40, green: 0.74, blue: 1.00)
            case .oxygenSaturation:
                self.accent = Color(red: 1.00, green: 0.42, blue: 0.42)
            default:
                self.accent = Color(red: 1.00, green: 0.67, blue: 0.34)
            }
        }
    }
}

#Preview("Health Monitor") {
    ScrollView {
        HealthMonitorSection(summary: MockHealthData.healthMonitorSummary)
            .padding()
    }
    .background(
        LinearGradient(
            colors: [
                Color(red: 0.06, green: 0.08, blue: 0.14),
                Color(red: 0.03, green: 0.05, blue: 0.10)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
}
