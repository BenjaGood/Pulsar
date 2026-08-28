import SwiftUI

struct RecoveryDriverRow: View {
    var driver: RecoveryDriver
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: RecoveryDetailsDesign.rowSpacing) {
                        icon

                        labels
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(driver.value)
                            .pulsarMonospacedMetric(.label)
                            .foregroundStyle(driver.value == "No data" ? .secondary : .primary)

                        statusPill
                    }
                    .padding(.leading, 40)
                }
            } else {
                HStack(spacing: RecoveryDetailsDesign.rowSpacing) {
                    icon

                    labels

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(driver.value)
                            .pulsarMonospacedMetric(.label)
                            .foregroundStyle(driver.value == "No data" ? .secondary : .primary)
                            .lineLimit(1)

                        statusPill
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(driver.kind.title)
        .accessibilityValue("\(driver.value). \(driver.context). \(driver.status)")
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(driver.kind.title)
                .pulsarTextStyle(.label)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.74)

            Text(driver.context)
                .pulsarTextStyle(.metadata)
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var icon: some View {
        Image(systemName: driver.kind.systemImage)
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(accent)
            .frame(width: 34, height: 34)
            .background(accent.opacity(0.10), in: Circle())
            .accessibilityHidden(true)
    }

    private var statusPill: some View {
        HStack(spacing: 3) {
            Image(systemName: driver.statusSymbol)
                .accessibilityHidden(true)

            Text(driver.status)
        }
        .pulsarTextStyle(.captionEmphasis)
        .foregroundStyle(accent)
        .lineLimit(1)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(accent.opacity(0.09), in: Capsule())
        .fixedSize(horizontal: true, vertical: false)
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .accessibilityLabel(driver.status)
    }

    private var accent: Color {
        switch driver.kind {
        case .hrv, .restingHeartRate:
            RecoveryDetailsDesign.wellnessGreen
        case .sleep:
            RecoveryDetailsDesign.sleepViolet
        case .strain:
            RecoveryDetailsDesign.strainBlue
        }
    }
}
