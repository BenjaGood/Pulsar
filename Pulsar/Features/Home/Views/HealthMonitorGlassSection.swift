//
//  HealthMonitorGlassSection.swift
//  Pulsar
//

import SwiftUI

struct HealthMonitorGlassSection: View {
    var summary: HealthMonitorSummary

    @State private var selectedMetric: HealthMetricModel?
    @Environment(\.homeAdaptiveAppearance) private var appearance

    var body: some View {
        liquidGlassSection
            .sheet(item: $selectedMetric) { metric in
                HealthMetricDetailSheet(metric: metric)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
    }

    @ViewBuilder
    private var liquidGlassSection: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 18) {
                sectionSurface
            }
        } else {
            sectionSurface
        }
    }

    private var sectionSurface: some View {
        PremiumGlassContainer(cornerRadius: 34, tint: availabilityTint) {
            VStack(alignment: .leading, spacing: 16) {
                header
                metricsRail
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var metricsRail: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(summary.metrics) { metric in
                        HealthMonitorGlassMetricCard(metric: metric) {
                            selectedMetric = metric
                        }
                        .frame(width: 132)
                    }
                }
                .padding(.horizontal, 1)
                .padding(.bottom, 2)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            PulsarGlassIconCircle(size: 44, tint: .green, systemImage: "heart.text.square.fill", symbolScale: 0.36)

            VStack(alignment: .leading, spacing: 3) {
                Text("Health Monitor")
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                    .foregroundStyle(appearance.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text("Vitals and sleep signals")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(appearance.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 8)

            PremiumGlassPill(tint: availabilityTint, horizontalPadding: 11, verticalPadding: 7) {
                Text(summary.availableMetricCount > 0 ? "\(summary.availableMetricCount)/\(summary.metrics.count) signals" : "Waiting")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(availabilityTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
    }

    private var availabilityTint: Color {
        summary.availableMetricCount > 0 ? Color(red: 0.48, green: 0.96, blue: 0.56) : appearance.tertiaryText
    }
}

private struct HealthMonitorGlassMetricCard: View {
    var metric: HealthMetricModel
    var action: () -> Void

    @Environment(\.homeAdaptiveAppearance) private var appearance

    var body: some View {
        Button(action: action) {
            PremiumGlassContainer(cornerRadius: 24, tint: tint, isInteractive: true) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(tint.opacity(metric.hasData ? 0.08 : 0.045))
                            Image(systemName: metric.systemImageName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(metric.hasData ? tint : appearance.tertiaryText)
                        }
                        .frame(width: 34, height: 34)

                        Spacer(minLength: 4)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(appearance.tertiaryText.opacity(0.70))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(metric.abbreviation)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(appearance.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        Text(metric.title)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(appearance.secondaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)
                    }

                    valueRow

                    HStack(spacing: 6) {
                        Image(systemName: metric.status.systemImageName)
                            .font(.system(size: 10, weight: .bold))
                        Text(metric.status.rawValue)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(tint.opacity(metric.hasData ? 0.055 : 0.035), in: Capsule(style: .continuous))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(tint.opacity(0.10), lineWidth: 0.6)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
            }
        }
        .buttonStyle(HealthMonitorGlassButtonStyle(glowColor: tint))
        .accessibilityLabel(metric.accessibilityLabel)
        .accessibilityHint("Show more details")
    }

    private var valueRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(metric.displayValueText)
                .font(metric.hasData ? .system(size: 20, weight: .semibold, design: .rounded) : .system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(appearance.primaryText.opacity(metric.hasData ? 1 : 0.55))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.56)

            if metric.hasData, let unitText = metric.unitText {
                Text(unitText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(appearance.secondaryText)
                    .lineLimit(1)
            }
        }
    }

    private var tint: Color {
        switch metric.status {
        case .normal:
            return Color(red: 0.42, green: 0.92, blue: 0.58)
        case .higher:
            switch metric.kind {
            case .hrv, .sleep:
                return Color(red: 0.44, green: 0.64, blue: 1.00)
            case .wristTemperature:
                return Color(red: 1.00, green: 0.52, blue: 0.34)
            default:
                return Color(red: 1.00, green: 0.70, blue: 0.30)
            }
        case .lower:
            switch metric.kind {
            case .restingHeartRate:
                return Color(red: 0.44, green: 0.64, blue: 1.00)
            case .oxygenSaturation:
                return Color(red: 1.00, green: 0.40, blue: 0.38)
            default:
                return Color(red: 1.00, green: 0.70, blue: 0.30)
            }
        case .noData:
            return appearance.tertiaryText.opacity(0.78)
        }
    }
}

private struct HealthMonitorGlassButtonStyle: ButtonStyle {
    var glowColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.982 : 1)
            .brightness(configuration.isPressed ? 0.035 : 0)
            .shadow(color: glowColor.opacity(configuration.isPressed ? 0.18 : 0), radius: 14, y: 7)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

#Preview("Health Monitor Glass") {
    ZStack {
        StaticTimeBackgroundView(mode: .sunset)
        ScrollView {
            HealthMonitorGlassSection(summary: MockHealthData.healthMonitorSummary)
                .padding()
        }
    }
    .preferredColorScheme(.dark)
    .environment(\.homeAdaptiveAppearance, HomeAdaptiveAppearance(style: .sunset))
}
