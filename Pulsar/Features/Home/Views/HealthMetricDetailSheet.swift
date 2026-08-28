//
//  HealthMetricDetailSheet.swift
//  Pulsar
//

import SwiftUI

struct HealthMetricDetailSheet: View {
    var metric: HealthMetricModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let pagePadding: CGFloat = 16

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                header
                whatIsItCard
                importanceCard
                factorsCard
                dataCard
                dailyInsightCard
            }
            .padding(.horizontal, pagePadding)
            .padding(.top, 14)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.bottom, 48, for: .scrollContent)
        .background(Color.white.ignoresSafeArea())
        .presentationBackground(Color.white)
        .preferredColorScheme(.light)
    }

    @ViewBuilder
    private var header: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    metricHeaderIcon
                    Spacer(minLength: 16)
                    closeButton
                }
                headerCopy
            }
            .padding(.vertical, 2)
        } else {
            HStack(alignment: .top, spacing: 12) {
                metricHeaderIcon
                headerCopy
                closeButton
            }
            .padding(.vertical, 2)
        }
    }

    private var metricHeaderIcon: some View {
        Image(systemName: metric.systemImageName)
            .font(.system(size: 27, weight: .semibold))
            .foregroundStyle(accent)
            .symbolRenderingMode(.hierarchical)
            .frame(width: 64, height: 64)
            .background(accent.opacity(0.075), in: Circle())
            .accessibilityHidden(true)
    }

    private var headerCopy: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(metric.title)
                .font(.system(.title2, design: .default, weight: .bold))
                .foregroundStyle(HealthMetricEducationDesign.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(metric.abbreviation)
                .font(.system(.caption, design: .default, weight: .semibold))
                .foregroundStyle(HealthMetricEducationDesign.secondaryText)

            Text(education.subtitle)
                .font(.system(.subheadline, design: .default))
                .foregroundStyle(HealthMetricEducationDesign.secondaryText)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var closeButton: some View {
        Button("Close", systemImage: "xmark", action: close)
            .labelStyle(.iconOnly)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(HealthMetricEducationDesign.secondaryText)
            .frame(width: 44, height: 44)
            .background(HealthMetricEducationDesign.chipBackground, in: Circle())
            .contentShape(Circle())
            .buttonStyle(.plain)
    }

    private var whatIsItCard: some View {
        HealthMetricEducationCard(
            title: "What is it?",
            symbol: "questionmark",
            accent: accent
        ) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    definitionText
                    HealthMetricEducationalIllustration(kind: metric.kind, accent: accent)
                        .frame(height: 80)
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    definitionText
                    HealthMetricEducationalIllustration(kind: metric.kind, accent: accent)
                        .frame(width: 96, height: 80)
                }
            }
        }
    }

    private var definitionText: some View {
        Text(education.definition)
            .font(.system(.subheadline, design: .default))
            .foregroundStyle(HealthMetricEducationDesign.secondaryText)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var importanceCard: some View {
        HealthMetricEducationCard(
            title: "Why is it important?",
            symbol: "heart",
            accent: accent
        ) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(education.highlights) { highlight in
                        HealthMetricImportanceItem(highlight: highlight, accent: accent, isHorizontal: true)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(education.highlights.enumerated(), id: \.element.id) { index, highlight in
                        if index > 0 {
                            Divider()
                                .padding(.vertical, 4)
                        }

                        HealthMetricImportanceItem(highlight: highlight, accent: accent, isHorizontal: false)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private var factorsCard: some View {
        HealthMetricEducationCard(
            title: education.factorsTitle,
            symbol: "slider.horizontal.3",
            accent: accent
        ) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(education.factors) { factor in
                        Label(factor.title, systemImage: factor.symbol)
                            .font(.system(.caption, design: .default, weight: .medium))
                            .foregroundStyle(HealthMetricEducationDesign.secondaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(HealthMetricEducationDesign.chipBackground, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            } else {
                HealthMetricFactorLayout(spacing: 6) {
                    ForEach(education.factors) { factor in
                        Label(factor.title, systemImage: factor.symbol)
                            .font(.system(.caption, design: .default, weight: .medium))
                            .foregroundStyle(HealthMetricEducationDesign.secondaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(HealthMetricEducationDesign.chipBackground, in: Capsule())
                            .fixedSize()
                    }
                }
            }
        }
    }

    private var dataCard: some View {
        HealthMetricEducationCard(
            title: "Your Data",
            symbol: "cylinder.split.1x2",
            accent: accent
        ) {
            LazyVGrid(columns: dataColumns, spacing: 6) {
                ForEach(dataItems) { item in
                    HealthMetricDataItemView(item: item, accent: accent)
                }
            }
        }
    }

    private var dailyInsightCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.max")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 42, height: 42)
                .background(accent.opacity(0.09), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Daily Insight")
                    .font(.system(.subheadline, design: .default, weight: .semibold))
                    .foregroundStyle(accent)

                Text(dailyInsight)
                    .font(.system(.subheadline, design: .default))
                    .foregroundStyle(HealthMetricEducationDesign.secondaryText)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(accent.opacity(0.045), in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(accent.opacity(0.08), lineWidth: 0.75)
        }
        .shadow(color: Color.black.opacity(0.03), radius: 12, y: 6)
        .pulsarLiquidGlass(cornerRadius: 24, isClear: true)
        .accessibilityElement(children: .combine)
    }

    private var dataColumns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 4
        return Array(repeating: GridItem(.flexible(minimum: 0), spacing: 6, alignment: .top), count: count)
    }

    private var dataItems: [HealthMetricDataItem] {
        [
            .init(symbol: "calendar", label: "Latest", value: latestReadingText),
            .init(symbol: "chart.line.uptrend.xyaxis", label: "Trend", value: recentTrendText),
            .init(symbol: "scope", label: "Reference", value: referenceText),
            .init(symbol: "shield.checkered", label: "Source", value: sourceText)
        ]
    }

    private var latestReadingText: String {
        guard metric.hasData else { return "Not available" }
        guard let lastUpdated = metric.lastUpdated else { return "Not available" }
        if Calendar.current.isDateInToday(lastUpdated) {
            return "\(lastUpdated.formatted(date: .omitted, time: .shortened))\nToday"
        }
        return lastUpdated.formatted(date: .abbreviated, time: .shortened)
    }

    private var recentTrendText: String {
        switch metric.status {
        case .normal:
            "Stable"
        case .higher:
            metric.kind == .hrv || metric.kind == .sleep ? "Above usual" : "Elevated"
        case .lower:
            metric.kind == .restingHeartRate ? "Below usual" : "Lower"
        case .noData:
            "Building trend"
        }
    }

    private var referenceText: String {
        guard let baseline = metric.baselineValue else { return "Building baseline" }

        switch metric.kind {
        case .respiratoryRate:
            return "\(baseline.formatted(.number.precision(.fractionLength(1)))) rpm"
        case .restingHeartRate:
            return "\(Int(baseline.rounded())) bpm"
        case .hrv:
            return "\(Int(baseline.rounded())) ms"
        case .oxygenSaturation:
            return "\(Int((baseline * 100).rounded()))%"
        case .wristTemperature:
            if baseline == 0 {
                return "Personal baseline"
            }
            return "\(baseline.formatted(.number.sign(strategy: .always()).precision(.fractionLength(1)))) °C"
        case .sleep:
            return Self.durationText(minutes: baseline)
        }
    }

    private var sourceText: String {
        if let source = metric.sourceResolution?.displayedRecordSource {
            switch source {
            case .appleWatch, .iPhone:
                return "Apple Health"
            case .ouraRing:
                return "Oura Ring"
            case .airPodsPro3:
                return "AirPods Pro"
            case .manual:
                return "Manual Entry"
            }
        }

        if let source = metric.sourceBadges.first {
            if source.isAppleWatchLike || source.sourceBundleIdentifier?.contains("com.apple.health") == true {
                return "Apple Health"
            }
            if source.sourceName.localizedCaseInsensitiveContains("oura") {
                return "Oura Ring"
            }
            return source.displayName
        }

        return metric.hasData ? "Apple Health" : "Not available"
    }

    private var dailyInsight: String {
        switch metric.status {
        case .normal:
            education.insights.stable
        case .higher:
            education.insights.higher
        case .lower:
            education.insights.lower
        case .noData:
            education.insights.unavailable
        }
    }

    private var education: HealthMetricEducation {
        metric.kind.education
    }

    private func close() {
        dismiss()
    }

    private var accent: Color {
        HealthMetricEducationDesign.accent(for: metric.kind)
    }

    private static func durationText(minutes: Double) -> String {
        let totalMinutes = max(0, Int(minutes.rounded()))
        let hours = totalMinutes / 60
        let remainder = totalMinutes % 60
        if hours > 0, remainder > 0 {
            return "\(hours)h \(remainder)m"
        }
        return hours > 0 ? "\(hours)h" : "\(remainder)m"
    }
}

#Preview("Respiratory Rate Detail") {
    HealthMetricDetailSheet(
        metric: HealthMetricModel(
            kind: .respiratoryRate,
            value: 14.8,
            status: .normal,
            baselineValue: 14.5,
            comparisonText: "Close to your reference",
            sourceBadges: [.sample],
            lastUpdated: .now
        )
    )
}

#Preview("Respiratory Rate Detail — Bottom") {
    HealthMetricDetailSheet(
        metric: HealthMetricModel(
            kind: .respiratoryRate,
            value: 14.8,
            status: .normal,
            baselineValue: 14.5,
            comparisonText: "Close to your reference",
            sourceBadges: [.sample],
            lastUpdated: .now
        )
    )
    .defaultScrollAnchor(.bottom)
}
