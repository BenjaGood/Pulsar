//
//  HealthConnectionCard.swift
//  Pulsar
//

import SwiftUI

struct HealthConnectionCard: View {
    let permissionState: HealthPermissionState
    let isRequestingAuthorization: Bool
    let errorMessage: String?
    let connect: () -> Void
    let manage: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: HealthSettingsDesign.cardSpacing) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        HealthConnectionIcon()
                        Spacer(minLength: 12)
                        HealthConnectionIndicator(permissionState: permissionState)
                    }

                    HealthConnectionStatus(permissionState: permissionState)
                }
            } else {
                HStack(spacing: 18) {
                    HealthConnectionIcon()
                    HealthConnectionStatus(permissionState: permissionState)
                        .layoutPriority(1)
                    Spacer(minLength: 8)
                    HealthConnectionIndicator(permissionState: permissionState)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Pulsar reads compatible HealthKit data to estimate Sleep, Recovery, and Strain. You stay in control of what Apple Health shares.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)

                if let inlineMessage {
                    Label(inlineMessage, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(SettingsMonochromeDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HealthConnectionActionButton(
                isConnected: permissionState.isConnected,
                isRequestingAuthorization: isRequestingAuthorization,
                canRequestAuthorization: permissionState.canRequestAuthorization,
                connect: connect,
                manage: manage
            )
            .frame(maxWidth: HealthSettingsDesign.maximumButtonWidth)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, HealthSettingsDesign.cardHorizontalPadding)
        .padding(.vertical, HealthSettingsDesign.cardVerticalPadding)
        .background(
            SettingsMonochromeDesign.surface,
            in: .rect(cornerRadius: HealthSettingsDesign.cardCornerRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: HealthSettingsDesign.cardCornerRadius)
                .stroke(SettingsMonochromeDesign.border, lineWidth: 0.75)
        }
        .shadow(color: SettingsMonochromeDesign.shadow, radius: 16, y: 8)
        .accessibilityElement(children: .contain)
    }

    private var inlineMessage: String? {
        if permissionState == .notAvailable {
            "Apple Health is not available on this device."
        } else {
            errorMessage
        }
    }
}

#Preview("Health Connection States") {
    ScrollView {
        VStack(spacing: 24) {
            HealthConnectionCard(
                permissionState: .connected,
                isRequestingAuthorization: false,
                errorMessage: nil,
                connect: { },
                manage: { }
            )

            HealthConnectionCard(
                permissionState: .notIntroduced,
                isRequestingAuthorization: false,
                errorMessage: nil,
                connect: { },
                manage: { }
            )
        }
        .padding(24)
    }
    .background(HealthSettingsDesign.background)
}
