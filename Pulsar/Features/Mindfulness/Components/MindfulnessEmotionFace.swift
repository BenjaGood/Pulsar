//
//  MindfulnessEmotionFace.swift
//  Pulsar
//

import SwiftUI

struct MindfulnessEmotionFace: View {
    var emotion: MindfulnessEmotion

    var body: some View {
        Canvas { context, size in
            let lineWidth = max(1.3, min(size.width, size.height) * 0.055)
            let stroke = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            let width = size.width
            let height = size.height

            var leftEye = Path()
            leftEye.addEllipse(in: CGRect(x: width * 0.29, y: height * 0.30, width: lineWidth * 1.35, height: lineWidth * 1.35))
            context.fill(leftEye, with: .color(MindfulnessDesign.primaryText))

            var rightEye = Path()
            rightEye.addEllipse(in: CGRect(x: width * 0.64, y: height * 0.30, width: lineWidth * 1.35, height: lineWidth * 1.35))
            context.fill(rightEye, with: .color(MindfulnessDesign.primaryText))

            var mouth = Path()
            mouth.move(to: CGPoint(x: width * 0.28, y: height * 0.63))
            mouth.addQuadCurve(
                to: CGPoint(x: width * 0.72, y: height * 0.63),
                control: CGPoint(x: width * 0.50, y: height * mouthControlY)
            )
            context.stroke(mouth, with: .color(MindfulnessDesign.primaryText), style: stroke)

            if emotion == .anxious || emotion == .stressed {
                var brows = Path()
                brows.move(to: CGPoint(x: width * 0.24, y: height * 0.23))
                brows.addLine(to: CGPoint(x: width * 0.37, y: height * 0.18))
                brows.move(to: CGPoint(x: width * 0.63, y: height * 0.18))
                brows.addLine(to: CGPoint(x: width * 0.76, y: height * 0.23))
                context.stroke(brows, with: .color(MindfulnessDesign.primaryText), style: stroke)
            }
        }
        .accessibilityHidden(true)
    }

    private var mouthControlY: CGFloat {
        switch emotion {
        case .calm: 0.78
        case .happy: 0.86
        case .neutral: 0.63
        case .anxious: 0.49
        case .stressed: 0.43
        case .sad: 0.39
        }
    }
}
