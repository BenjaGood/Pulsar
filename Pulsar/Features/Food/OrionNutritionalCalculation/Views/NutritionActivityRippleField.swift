//
//  NutritionActivityRippleField.swift
//  Pulsar
//

import SwiftUI

struct NutritionActivityRippleField: View {
    private let waveCount = 6
    private let cycleDuration = 3.6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if reduceMotion {
                staticRings
            } else {
                TimelineView(
                    .animation(
                        minimumInterval: 1.0 / 30.0,
                        paused: scenePhase != .active
                    )
                ) { context in
                    ZStack {
                        ForEach(0..<waveCount, id: \.self) { index in
                            animatedRing(index: index, date: context.date)
                        }
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var staticRings: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .stroke(.black.opacity(0.045), lineWidth: 0.7)
                    .scaleEffect(0.54 + (CGFloat(index) * 0.13))
            }
        }
    }

    private func animatedRing(index: Int, date: Date) -> some View {
        let elapsed = date.timeIntervalSinceReferenceDate / cycleDuration
        let stagger = Double(index) / Double(waveCount)
        let phase = (elapsed + stagger).truncatingRemainder(dividingBy: 1)
        let scale = 0.45 + (phase * 0.55)
        let opacity = 0.13 * pow(1 - phase, 1.35)

        return Circle()
            .stroke(.black.opacity(0.9), lineWidth: 0.72)
            .scaleEffect(CGFloat(scale))
            .opacity(opacity)
    }
}
