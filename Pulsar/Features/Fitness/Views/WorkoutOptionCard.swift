//
//  WorkoutOptionCard.swift
//  Pulsar
//

import SwiftUI

struct WorkoutOptionCard: View {
    var workout: WorkoutOption
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top, spacing: 10) {
                    WorkoutGlyphView(workout: workout)
                        .frame(width: 44, height: 44)

                    Spacer(minLength: 0)

                    Image(systemName: workout.isPersonalized ? "sparkles" : "plus")
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(workout.accent.color.opacity(0.95))
                        .frame(width: 26, height: 26)
                        .background(workout.accent.color.opacity(colorScheme == .dark ? 0.16 : 0.11), in: Circle())
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(workout.name)
                        .pulsarTextStyle(.cardTitle)
                        .foregroundStyle(primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(workout.category)
                        .pulsarTextStyle(.overline)
                        .foregroundStyle(workout.accent.color)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(workout.accent.color.opacity(colorScheme == .dark ? 0.14 : 0.10), in: Capsule())
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(cardBorder)
            .shadow(color: shadowColor, radius: colorScheme == .dark ? 14 : 10, y: 7)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(WorkoutOptionCardButtonStyle(glowColor: workout.accent.color))
        .accessibilityLabel(workout.isPersonalized ? "\(workout.name), personalized training" : "\(workout.name), \(workout.category)")
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.96) : Color(red: 0.08, green: 0.10, blue: 0.15)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [
                            Color.white.opacity(0.095),
                            Color.white.opacity(0.045),
                            workout.accent.color.opacity(0.10)
                        ]
                        : [
                            Color.white.opacity(0.88),
                            Color(red: 0.95, green: 0.97, blue: 1.00).opacity(0.82),
                            workout.accent.color.opacity(0.08)
                        ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        .white.opacity(colorScheme == .dark ? 0.18 : 0.84),
                        workout.accent.color.opacity(colorScheme == .dark ? 0.16 : 0.22),
                        .black.opacity(colorScheme == .dark ? 0.16 : 0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    private var shadowColor: Color {
        colorScheme == .dark ? .black.opacity(0.20) : workout.accent.color.opacity(0.10)
    }
}

private struct WorkoutGlyphView: View {
    var workout: WorkoutOption

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Circle()
                .fill(iconBackground)

            Circle()
                .stroke(.white.opacity(colorScheme == .dark ? 0.14 : 0.58), lineWidth: 1)

            if let personalizedKind = workout.personalizedKind {
                personalizedGlyph(for: personalizedKind)
            } else {
                Image(systemName: workout.symbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(iconGradient)
            }
        }
    }

    @ViewBuilder
    private func personalizedGlyph(for kind: PersonalizedWorkoutKind) -> some View {
        switch kind {
        case .hiking:
            ZStack {
                MountainGlyphShape()
                    .fill(iconGradient)
                    .frame(width: 27, height: 19)
                    .offset(y: 2)

                Path { path in
                    path.move(to: CGPoint(x: 4, y: 24))
                    path.addCurve(to: CGPoint(x: 21, y: 20), control1: CGPoint(x: 9, y: 17), control2: CGPoint(x: 15, y: 26))
                    path.addCurve(to: CGPoint(x: 29, y: 12), control1: CGPoint(x: 25, y: 16), control2: CGPoint(x: 25, y: 13))
                }
                .trim(from: 0.05, to: 0.95)
                .stroke(.white.opacity(colorScheme == .dark ? 0.72 : 0.86), style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                .frame(width: 32, height: 28)
            }
        case .running:
            ZStack {
                Image(systemName: "figure.run")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(iconGradient)

                HStack(spacing: 3) {
                    Circle().fill(workout.accent.color.opacity(0.85)).frame(width: 3, height: 3)
                    Circle().fill(workout.accent.color.opacity(0.58)).frame(width: 3, height: 3)
                }
                .offset(x: -13, y: 10)
            }
        case .indoorRunning:
            ZStack {
                Image(systemName: "figure.run")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(iconGradient)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(workout.accent.color.opacity(0.70))
                    .frame(width: 25, height: 4)
                    .offset(y: 15)

                Capsule(style: .continuous)
                    .fill(.white.opacity(colorScheme == .dark ? 0.76 : 0.88))
                    .frame(width: 9, height: 2)
                    .offset(x: 8, y: 13)
            }
        case .walking:
            ZStack {
                Image(systemName: "figure.walk")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(iconGradient)

                HStack(spacing: 5) {
                    Capsule().fill(workout.accent.color.opacity(0.72)).frame(width: 7, height: 3)
                    Capsule().fill(workout.accent.color.opacity(0.48)).frame(width: 7, height: 3)
                }
                .rotationEffect(.degrees(-10))
                .offset(y: 14)
            }
        case .gym:
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(iconGradient)
        }
    }

    private var iconGradient: LinearGradient {
        LinearGradient(
            colors: [
                colorScheme == .dark ? .white.opacity(0.94) : Color(red: 0.10, green: 0.12, blue: 0.18),
                workout.accent.color
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var iconBackground: LinearGradient {
        LinearGradient(
            colors: [
                workout.accent.color.opacity(colorScheme == .dark ? 0.24 : 0.14),
                Color.white.opacity(colorScheme == .dark ? 0.07 : 0.76)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct MountainGlyphShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.32, y: rect.minY + rect.height * 0.30))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.47, y: rect.minY + rect.height * 0.54))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.66, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct WorkoutOptionCardButtonStyle: ButtonStyle {
    var glowColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .brightness(configuration.isPressed ? 0.045 : 0)
            .shadow(color: glowColor.opacity(configuration.isPressed ? 0.26 : 0), radius: 18, y: 8)
            .animation(.spring(response: 0.26, dampingFraction: 0.74), value: configuration.isPressed)
    }
}

#Preview {
    WorkoutOptionCard(workout: WorkoutOption.personalized[0]) { }
        .padding()
        .background(PulsarSectionBackground())
}
