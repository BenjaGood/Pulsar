//
//  WorkoutSearchBar.swift
//  Pulsar
//

import SwiftUI

struct WorkoutSearchBar: View {
    @Binding var text: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .pulsarTextStyle(.label)
                .foregroundStyle(.secondary)

            TextField("Search workouts", text: $text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .pulsarTextStyle(.label)
                .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        text = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .pulsarTextStyle(.label)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(searchBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(colorScheme == .dark ? 0.12 : 0.64), lineWidth: 1)
        }
    }

    private var searchBackground: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color.white.opacity(0.08),
                    Color.white.opacity(0.04)
                ]
                : [
                    Color.white.opacity(0.78),
                    Color(red: 0.95, green: 0.97, blue: 1.00).opacity(0.58)
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
