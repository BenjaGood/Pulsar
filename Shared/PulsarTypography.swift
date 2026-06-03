//
//  PulsarTypography.swift
//  Pulsar
//

import SwiftUI

enum PulsarTypography {
    enum Role {
        case appBody
        case appBodyEmphasis
        case screenTitle
        case screenSubtitle
        case sectionTitle
        case cardTitle
        case heroMetric
        case metricValue
        case metricLabel
        case caption
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
        case .appBody:
            .body.weight(.regular)
        case .appBodyEmphasis:
            .body.weight(.medium)
        case .screenTitle:
            .system(.largeTitle, design: .default).weight(.semibold)
        case .screenSubtitle:
            .subheadline.weight(.regular)
        case .sectionTitle:
            .title3.weight(.semibold)
        case .cardTitle:
            .headline.weight(.semibold)
        case .heroMetric:
            .system(.largeTitle, design: .default).weight(.semibold)
        case .metricValue:
            .system(.title, design: .default).weight(.semibold)
        case .metricLabel:
            .caption.weight(.medium)
        case .caption:
            .caption.weight(.regular)
        case .overline:
            .caption2.weight(.semibold)
        case .buttonTitle:
            .headline.weight(.semibold)
        case .workoutHero:
            .system(.largeTitle, design: .default).weight(.semibold)
        case .workoutSubtitle:
            .title3.weight(.regular)
        case .watchTitle:
            .headline.weight(.semibold)
        case .watchSubtitle:
            .caption2.weight(.regular)
        case .watchHeroValue:
            .system(.title, design: .default).weight(.semibold)
        case .watchValue:
            .system(.title2, design: .default).weight(.semibold)
        case .watchMetric:
            .caption.weight(.semibold)
        case .watchLabel:
            .caption2.weight(.medium)
        case .watchButton:
            .caption.weight(.semibold)
        }
    }

    var tracking: CGFloat {
        switch self {
        case .overline:
            0.7
        case .metricLabel, .watchLabel:
            0.3
        case .buttonTitle, .watchButton:
            0.15
        default:
            0
        }
    }

    var lineSpacing: CGFloat {
        switch self {
        case .screenTitle, .workoutHero:
            2
        case .screenSubtitle, .appBody, .appBodyEmphasis:
            3
        case .watchTitle, .watchSubtitle:
            1
        default:
            0
        }
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
