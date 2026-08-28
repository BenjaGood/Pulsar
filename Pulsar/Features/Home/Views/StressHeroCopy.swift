import SwiftUI

struct StressHeroCopy: View {
    var summary: StressSummary

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var scoreFontSize = 62.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Current Stress")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)

            Text(summary.displayScoreText)
                .font(scoreFont)
                .foregroundStyle(scoreColor)
                .monospacedDigit()
                .kerning(summary.score == nil ? 0 : -1)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.22), value: summary.score)
                .padding(.top, 2)

            statusCapsule
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Current stress")
        .accessibilityValue("\(summary.displayScoreText), \(summary.displayLevelText)")
    }

    private var statusCapsule: some View {
        Label {
            Text(summary.displayLevelText)
        } icon: {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
        }
        .labelStyle(StressHeroCapsuleLabelStyle())
        .font(.system(size: 14.5, weight: .medium))
        .foregroundStyle(statusColor)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .padding(.horizontal, 13)
        .frame(minHeight: 30)
        .background(statusColor.opacity(0.10), in: Capsule())
        .glassEffect(
            reduceTransparency ? .identity : .clear.tint(statusColor.opacity(0.04)),
            in: .capsule
        )
        .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
        .contentTransition(.opacity)
        .animation(.easeInOut(duration: 0.22), value: summary.displayLevelText)
    }

    private var scoreFont: Font {
        if summary.score == nil {
            return .system(.title2, design: .default, weight: .light)
        }

        return .system(size: min(scoreFontSize, 68), weight: .thin)
    }

    private var labelColor: Color {
        colorScheme == .dark
            ? .white.opacity(0.88)
            : Color(red: 0.13, green: 0.15, blue: 0.19)
    }

    private var scoreColor: Color {
        colorScheme == .dark
            ? .white.opacity(0.96)
            : Color(red: 0.07, green: 0.09, blue: 0.12)
    }

    private var statusColor: Color {
        StressHeroPalette.statusColor(for: summary.score)
    }
}

private struct StressHeroCapsuleLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
            configuration.title
        }
    }
}

struct StressHeroTimestamp: View {
    var summary: StressSummary

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "clock")
                .font(.system(size: 10.5, weight: .medium))

            Text(updatedText)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .foregroundStyle(
            colorScheme == .dark
                ? Color.white.opacity(0.44)
                : Color(red: 0.62, green: 0.65, blue: 0.70)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(updatedText)
    }

    private var updatedText: String {
        guard let updated = summary.lastUpdated ?? summary.queryEnd else {
            return "Update pending"
        }

        return "Updated \(updated.formatted(date: .omitted, time: .shortened))"
    }
}
