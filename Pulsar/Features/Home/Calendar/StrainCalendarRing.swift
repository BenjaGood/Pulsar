//
//  StrainCalendarRing.swift
//  Pulsar
//

import SwiftUI

struct StrainCalendarRing: View {
    let score: Int
    let size: CGFloat
    let progressLineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    StrainCalendarDesign.ringTrack,
                    lineWidth: score > 0 ? 1.05 : 0.75
                )

            if score > 0 {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        StrainCalendarDesign.strainOrange,
                        style: StrokeStyle(
                            lineWidth: progressLineWidth,
                            lineCap: .round
                        )
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var progress: Double {
        min(1, max(0, Double(score) / 100))
    }
}
