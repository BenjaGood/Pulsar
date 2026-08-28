//
//  MindfulnessSegmentedProgress.swift
//  Pulsar
//

import SwiftUI

struct MindfulnessSegmentedProgress: View {
    var currentStep: Int
    var totalSteps: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { step in
                Capsule()
                    .fill(step <= currentStep ? MindfulnessDesign.active : MindfulnessDesign.track)
                    .frame(height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Question \(currentStep + 1) of \(totalSteps)")
    }
}
