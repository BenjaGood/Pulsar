//
//  FitnessFloatingAddButton.swift
//  Pulsar
//

import SwiftUI
import UIKit

struct FitnessFloatingAddButton: View {
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            action()
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)

                Circle()
                    .fill(liquidTint)
                    .padding(1)

                Image(systemName: "plus")
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                    .foregroundStyle(iconGradient)
                    .shadow(color: .white.opacity(colorScheme == .dark ? 0.10 : 0.42), radius: 5, y: -1)
            }
            .frame(width: 64, height: 64)
            .overlay {
                Circle()
                    .stroke(borderGradient, lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(.white.opacity(colorScheme == .dark ? 0.18 : 0.50))
                    .frame(width: 17, height: 17)
                    .blur(radius: 6)
                    .offset(x: 12, y: 10)
            }
            .shadow(color: .accentColor.opacity(colorScheme == .dark ? 0.36 : 0.24), radius: 22, y: 10)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.38 : 0.16), radius: 18, y: 10)
            .contentShape(Circle())
        }
        .buttonStyle(FitnessFloatingAddButtonStyle())
        .accessibilityLabel("Add workout")
        .accessibilityHint("Opens workout options")
    }

    private var liquidTint: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color.white.opacity(0.18),
                    Color.accentColor.opacity(0.22),
                    Color(red: 0.10, green: 0.12, blue: 0.20).opacity(0.58)
                ]
                : [
                    Color.white.opacity(0.78),
                    Color.accentColor.opacity(0.16),
                    Color(red: 0.90, green: 0.95, blue: 1.00).opacity(0.58)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var iconGradient: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [.white.opacity(0.98), Color.accentColor.opacity(0.92)]
                : [Color(red: 0.08, green: 0.10, blue: 0.15), Color.accentColor.opacity(0.92)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(colorScheme == .dark ? 0.36 : 0.90),
                .white.opacity(colorScheme == .dark ? 0.10 : 0.28),
                .black.opacity(colorScheme == .dark ? 0.20 : 0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct FitnessFloatingAddButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1)
            .rotationEffect(.degrees(configuration.isPressed ? 45 : 0))
            .brightness(configuration.isPressed ? 0.06 : 0)
            .animation(.spring(response: 0.30, dampingFraction: 0.62), value: configuration.isPressed)
    }
}

#Preview {
    FitnessFloatingAddButton { }
        .padding(40)
        .background(PulsarSectionBackground())
}
