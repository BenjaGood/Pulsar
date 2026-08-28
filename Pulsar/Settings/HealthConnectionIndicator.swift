//
//  HealthConnectionIndicator.swift
//  Pulsar
//

import SwiftUI

struct HealthConnectionIndicator: View {
    let permissionState: HealthPermissionState

    @ScaledMetric(relativeTo: .title3)
    private var indicatorSize = HealthSettingsDesign.statusIndicatorSize
    @ScaledMetric(relativeTo: .subheadline) private var badgeSize: CGFloat = 34

    var body: some View {
        ZStack {
            Circle()
                .fill(indicatorTint.opacity(0.08))

            Circle()
                .stroke(indicatorTint.opacity(0.16), lineWidth: 1)

            Image(systemName: symbol)
                .font(.subheadline)
                .bold()
                .foregroundStyle(permissionState.isConnected ? Color.white : indicatorTint)
                .frame(width: badgeSize, height: badgeSize)
                .background(
                    permissionState.isConnected
                        ? SettingsMonochromeDesign.primary
                        : Color.clear,
                    in: Circle()
                )
        }
        .frame(width: indicatorSize, height: indicatorSize)
        .accessibilityHidden(true)
    }

    private var symbol: String {
        switch permissionState {
        case .connected:
            "checkmark"
        case .notAvailable:
            "xmark"
        case .notIntroduced, .needsPermission:
            "heart.fill"
        }
    }

    private var indicatorTint: Color {
        permissionState.isConnected
            ? SettingsMonochromeDesign.primary
            : SettingsMonochromeDesign.secondary
    }
}
