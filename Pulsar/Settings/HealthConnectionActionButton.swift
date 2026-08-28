//
//  HealthConnectionActionButton.swift
//  Pulsar
//

import SwiftUI

struct HealthConnectionActionButton: View {
    let isConnected: Bool
    let isRequestingAuthorization: Bool
    let canRequestAuthorization: Bool
    let connect: () -> Void
    let manage: () -> Void

    var body: some View {
        Button(action: performAction) {
            HStack(spacing: 12) {
                ZStack {
                    Image(systemName: "heart")
                        .opacity(isRequestingAuthorization ? 0 : 1)

                    ProgressView()
                        .tint(.white)
                        .opacity(isRequestingAuthorization ? 1 : 0)
                }
                .frame(width: 22, height: 22)

                Text(buttonTitle)
                    .contentTransition(.opacity)
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: HealthSettingsDesign.actionButtonMinimumHeight)
            .contentShape(.rect(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .background(
            SettingsMonochromeDesign.selectedFill,
            in: .rect(cornerRadius: 24)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(SettingsMonochromeDesign.border, lineWidth: 0.75)
        }
        .shadow(color: SettingsMonochromeDesign.shadow, radius: 14, y: 7)
        .disabled(isRequestingAuthorization || (!isConnected && !canRequestAuthorization))
        .opacity(!isConnected && !canRequestAuthorization ? 0.55 : 1)
        .accessibilityLabel(accessibilityTitle)
    }

    private var buttonTitle: String {
        if isRequestingAuthorization {
            "Connecting…"
        } else if isConnected {
            "Manage Connection"
        } else {
            "Connect Apple Health"
        }
    }

    private var accessibilityTitle: String {
        isRequestingAuthorization ? "Connecting to Apple Health" : buttonTitle
    }

    private func performAction() {
        if isConnected {
            manage()
        } else {
            connect()
        }
    }
}
