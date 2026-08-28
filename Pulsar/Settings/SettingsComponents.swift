//
//  SettingsComponents.swift
//  Pulsar
//

import SwiftUI

struct SettingsSectionCard<Content: View>: View {
    var title: String
    var footer: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.caption)
                .bold()
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 1)

            VStack(spacing: 0) {
                content
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .pulsarSettingsCardSurface(cornerRadius: 26)

            if let footer {
                Text(footer)
                    .pulsarTextStyle(.metadata)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            }
        }
    }
}

struct SettingsNavigationRow: View {
    var title: String
    var subtitle: String? = nil
    var symbol: String
    var tint: Color
    var badge: String? = nil
    var status: String? = nil
    var statusTint: Color = SettingsMonochromeDesign.primary

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        SettingsIcon(symbol: symbol, tint: tint)
                        Spacer(minLength: 8)

                        if let status {
                            SettingsConnectionStatus(text: status, tint: statusTint)
                        } else if let badge {
                            SettingsValuePill(value: badge)
                        }

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .bold()
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if let subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                HStack(spacing: 14) {
                    SettingsIcon(symbol: symbol, tint: tint)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        if let subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 8)

                    if let status {
                        SettingsConnectionStatus(text: status, tint: statusTint)
                    } else if let badge {
                        SettingsValuePill(value: badge)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .bold()
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(minHeight: 70)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct SettingsIcon: View {
    var symbol: String
    var tint: Color
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: symbol)
            .font(.title3)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(SettingsMonochromeDesign.primary)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider()
            .overlay(SettingsMonochromeDesign.divider)
            .padding(.leading, 74)
            .padding(.trailing, 16)
    }
}

struct SettingsValuePill: View {
    var value: String

    var body: some View {
        Text(value)
            .font(.caption)
            .foregroundStyle(SettingsMonochromeDesign.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(SettingsMonochromeDesign.subtleFill, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(SettingsMonochromeDesign.border, lineWidth: 0.7)
            }
    }
}

struct SettingsConnectionStatus: View {
    var text: String
    var tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(SettingsMonochromeDesign.primary)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            Text(text)
                .font(.caption)
                .foregroundStyle(SettingsMonochromeDesign.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

struct SettingsValueRow: View {
    var title: String
    var value: String
    var subtitle: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .pulsarTextStyle(.bodyEmphasis)
                if let subtitle {
                    Text(subtitle)
                        .pulsarTextStyle(.metadata)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            Text(value)
                .pulsarTextStyle(.bodyEmphasis)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct HelperCard: View {
    var symbol: String
    var title: String
    var message: String
    var tint: Color = SettingsMonochromeDesign.primary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SettingsIcon(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .pulsarTextStyle(.cardTitle)
                Text(message)
                    .pulsarTextStyle(.metadata)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pulsarSettingsCardSurface(cornerRadius: 24)
    }
}

struct HealthStatusBadge: View {
    var text: String
    var tint: Color

    var body: some View {
        Text(text)
            .pulsarTextStyle(.captionEmphasis)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(SettingsMonochromeDesign.subtleFill, in: Capsule())
            .foregroundStyle(SettingsMonochromeDesign.secondary)
            .overlay {
                Capsule()
                    .stroke(SettingsMonochromeDesign.border, lineWidth: 0.7)
            }
    }
}

extension View {
    func pulsarSettingsCardSurface(
        cornerRadius: CGFloat,
        interactive: Bool = false
    ) -> some View {
        self
            .background(
                SettingsMonochromeDesign.surface,
                in: RoundedRectangle(cornerRadius: cornerRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(SettingsMonochromeDesign.border, lineWidth: 0.75)
            }
            .shadow(color: SettingsMonochromeDesign.shadow, radius: 18, y: 8)
    }
}

#Preview("Settings Components") {
    ScrollView {
        VStack(spacing: 18) {
            SettingsSectionCard(title: "Personal") {
                SettingsNavigationRow(title: "Profile", subtitle: "Name and birthday", symbol: "person.crop.circle", tint: .black)
                SettingsDivider()
                SettingsNavigationRow(title: "Measurements", subtitle: "Height, weight, units", symbol: "ruler", tint: .black, badge: "Metric")
            }
            HelperCard(symbol: "heart.text.square", title: "HealthKit", message: "Pulsar uses available Apple Health data to personalize insights.")
        }
        .padding()
    }
    .background(PulsarSettingsBackground())
}
