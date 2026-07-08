//
//  WorkoutSearchBar.swift
//  Pulsar
//

import SwiftUI

struct WorkoutSearchBar: View {
    @Binding var text: String

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .pulsarTextStyle(.label)
                .foregroundStyle(PulsarTheme.fitnessSecondaryText(for: colorScheme))

            TextField("Search workouts", text: $text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .pulsarTextStyle(.label)
                .foregroundStyle(PulsarTheme.fitnessPrimaryText(for: colorScheme))
                .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        text = ""
                    }
                } label: {
                    Label("Clear search", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .pulsarTextStyle(.label)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(PulsarTheme.fitnessSecondaryText(for: colorScheme))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(searchBackground, in: shape)
        .pulsarLiquidGlass(cornerRadius: 20, tint: glassTint, interactive: true, isClear: !reduceTransparency)
        .overlay {
            shape
                .stroke(searchBorder, lineWidth: reduceTransparency ? 0.9 : 0.65)
                .blendMode(.plusLighter)
        }
        .contentShape(shape)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
    }

    private var searchBackground: Color {
        if reduceTransparency {
            return colorScheme == .dark
                ? Color(red: 0.04, green: 0.055, blue: 0.09).opacity(0.84)
                : Color.white.opacity(0.86)
        }

        return colorScheme == .dark
            ? Color.black.opacity(0.08)
            : Color.white.opacity(0.18)
    }

    private var glassTint: Color {
        Color(red: 0.68, green: 0.80, blue: 0.92).opacity(0.06)
    }

    private var searchBorder: LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(colorScheme == .dark ? 0.20 : 0.70),
                .white.opacity(colorScheme == .dark ? 0.08 : 0.24),
                .clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

#Preview {
    WorkoutSearchBar(text: .constant(""))
        .padding()
        .background(PulsarSectionBackground())
}
