import SwiftUI

enum SleepStageVisualStyle {
    static func color(for stage: SleepStage) -> Color {
        switch stage {
        case .awake:
            SleepDetailsDesign.awake
        case .rem:
            SleepDetailsDesign.rem
        case .core, .asleepUnspecified:
            SleepDetailsDesign.core
        case .deep:
            SleepDetailsDesign.deep
        case .inBed:
            .secondary.opacity(0.08)
        }
    }

    static func displayName(for stage: SleepStage) -> String {
        switch stage {
        case .asleepUnspecified:
            "Core"
        case .inBed:
            "In Bed"
        default:
            stage.rawValue
        }
    }
}
