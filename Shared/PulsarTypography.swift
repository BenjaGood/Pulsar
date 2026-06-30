//
//  PulsarTypography.swift
//  Pulsar
//

import SwiftUI

enum PulsarTypography {
    enum Role {
        case displayLarge
        case displayMedium
        case title
        case sectionHeader
        case body
        case bodyEmphasis
        case label
        case navigationLabel
        case metadata
        case caption
        case captionEmphasis
        case metricLarge
        case metricMedium
        case emptyStateTitle
        case insightHeadline
        case orionHero

        case appBody
        case appBodyEmphasis
        case screenTitle
        case screenSubtitle
        case sectionTitle
        case cardTitle
        case heroMetric
        case metricValue
        case metricLabel
        case overline
        case buttonTitle
        case workoutHero
        case workoutSubtitle
        case watchTitle
        case watchSubtitle
        case watchHeroValue
        case watchValue
        case watchMetric
        case watchLabel
        case watchButton
    }
}

extension PulsarTypography.Role {
    var font: Font {
        switch self {
        case .displayLarge:
            Self.serif(.largeTitle, weight: .regular)
        case .displayMedium:
            Self.serif(.title, weight: .regular)
        case .title:
            Self.serif(.title2, weight: .regular)
        case .sectionHeader:
            Self.serif(.title3, weight: .medium)
        case .body:
            Self.sans(.body, weight: .regular)
        case .bodyEmphasis:
            Self.sans(.body, weight: .medium)
        case .label:
            Self.sans(.subheadline, weight: .medium)
        case .navigationLabel:
            Self.sans(.subheadline, weight: .medium)
        case .metadata:
            Self.sans(.footnote, weight: .regular)
        case .caption:
            Self.sans(.caption, weight: .regular)
        case .captionEmphasis:
            Self.sans(.caption, weight: .medium)
        case .metricLarge:
            Self.serif(.largeTitle, weight: .regular)
        case .metricMedium:
            Self.serif(.title, weight: .regular)
        case .emptyStateTitle:
            Self.serif(.title2, weight: .regular)
        case .insightHeadline:
            Self.serif(.title3, weight: .medium)
        case .orionHero:
            Self.serif(.largeTitle, weight: .regular)

        case .appBody:
            PulsarTypography.Role.body.font
        case .appBodyEmphasis:
            PulsarTypography.Role.bodyEmphasis.font
        case .screenTitle:
            PulsarTypography.Role.displayLarge.font
        case .screenSubtitle:
            PulsarTypography.Role.label.font
        case .sectionTitle:
            PulsarTypography.Role.sectionHeader.font
        case .cardTitle:
            Self.serif(.headline, weight: .medium)
        case .heroMetric:
            PulsarTypography.Role.metricLarge.font
        case .metricValue:
            PulsarTypography.Role.metricMedium.font
        case .metricLabel:
            PulsarTypography.Role.captionEmphasis.font
        case .overline:
            Self.sans(.caption2, weight: .semibold)
        case .buttonTitle:
            Self.sans(.headline, weight: .semibold)
        case .workoutHero:
            PulsarTypography.Role.metricLarge.font
        case .workoutSubtitle:
            PulsarTypography.Role.sectionHeader.font
        case .watchTitle:
            Self.serif(.headline, weight: .medium)
        case .watchSubtitle:
            Self.sans(.caption2, weight: .regular)
        case .watchHeroValue:
            Self.serif(.title, weight: .regular)
        case .watchValue:
            Self.serif(.title2, weight: .regular)
        case .watchMetric:
            Self.sans(.caption, weight: .medium)
        case .watchLabel:
            .caption2.weight(.medium)
        case .watchButton:
            .caption.weight(.semibold)
        }
    }

    var tracking: CGFloat {
        switch self {
        default:
            0
        }
    }

    var lineSpacing: CGFloat {
        switch self {
        case .displayLarge, .screenTitle, .workoutHero, .orionHero:
            2
        case .displayMedium, .title, .sectionHeader, .metricLarge, .metricMedium:
            1
        case .screenSubtitle, .appBody, .appBodyEmphasis, .body, .bodyEmphasis, .label:
            3
        case .watchTitle, .watchSubtitle:
            1
        default:
            0
        }
    }

    private static func serif(_ textStyle: Font.TextStyle, weight: Font.Weight) -> Font {
        .system(textStyle, design: .serif).weight(weight)
    }

    private static func sans(_ textStyle: Font.TextStyle, weight: Font.Weight) -> Font {
        .system(textStyle, design: .default).weight(weight)
    }
}

extension View {
    func pulsarTextStyle(_ role: PulsarTypography.Role) -> some View {
        self
            .font(role.font)
            .tracking(role.tracking)
            .lineSpacing(role.lineSpacing)
    }

    func pulsarMonospacedMetric(_ role: PulsarTypography.Role = .metricValue) -> some View {
        self
            .pulsarTextStyle(role)
            .monospacedDigit()
    }
}
