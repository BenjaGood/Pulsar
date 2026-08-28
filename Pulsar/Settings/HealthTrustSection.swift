//
//  HealthTrustSection.swift
//  Pulsar
//

import SwiftUI

struct HealthTrustSection: View {
    var body: some View {
        VStack(spacing: 0) {
            HealthTrustRow(
                symbol: "lock.fill",
                title: "Secure & Private",
                description: "Your health data stays encrypted and on your device."
            )

            Divider()

            HealthTrustRow(
                symbol: "square.3.layers.3d",
                title: "Limited Access",
                description: "Reads Health data and writes only workouts you record."
            )

            Divider()

            HealthTrustRow(
                symbol: "shield.fill",
                title: "You’re in Control",
                description: "Change Apple Health access at any time."
            )
        }
    }
}
