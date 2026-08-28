//
//  HealthConnectionStatus.swift
//  Pulsar
//

import SwiftUI

struct HealthConnectionStatus: View {
    let permissionState: HealthPermissionState

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Apple Health")
                .font(.title2)
                .bold()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            HStack(spacing: 8) {
                Image(systemName: statusSymbol)
                    .font(statusSymbolFont)
                    .frame(width: 10)
                    .accessibilityHidden(true)

                Text(statusTitle)
            }
            .font(.body)
            .foregroundStyle(statusTint)
            .contentTransition(.opacity)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusSymbol: String {
        "circle.fill"
    }

    private var statusTitle: String {
        switch permissionState {
        case .connected:
            "Connected"
        case .notAvailable:
            "Not Available"
        case .notIntroduced, .needsPermission:
            "Not Connected"
        }
    }

    private var statusTint: Color {
        permissionState.isConnected
            ? SettingsMonochromeDesign.primary
            : SettingsMonochromeDesign.secondary
    }

    private var statusSymbolFont: Font {
        .system(size: 8)
    }
}
