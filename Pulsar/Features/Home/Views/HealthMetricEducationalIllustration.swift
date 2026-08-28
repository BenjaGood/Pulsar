//
//  HealthMetricEducationalIllustration.swift
//  Pulsar
//

import SwiftUI

struct HealthMetricEducationalIllustration: View {
    var kind: HealthMetricKind
    var accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.035))
                .frame(width: 62, height: 62)

            Image(systemName: kind.systemImageName)
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(accent.opacity(0.12))
                .symbolRenderingMode(.hierarchical)

            HealthMetricSignalShape(kind: kind, phase: phase)
                .stroke(
                    accent.opacity(0.58),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )
                .padding(.horizontal, 4)
        }
        .onAppear(perform: startAnimation)
        .onChange(of: reduceMotion) { _, shouldReduceMotion in
            if shouldReduceMotion {
                phase = 0.5
            }
        }
        .accessibilityHidden(true)
    }

    private func startAnimation() {
        guard !reduceMotion else {
            phase = 0.5
            return
        }
        withAnimation(.easeInOut(duration: 3.8).repeatForever(autoreverses: true)) {
            phase = 1
        }
    }
}
