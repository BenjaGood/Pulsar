//
//  WorkoutOptionCard.swift
//  Pulsar
//

import SwiftUI

struct WorkoutOptionCard: View {
    var workout: WorkoutOption
    var usesPickerGlass = false
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            PulsarGlassCard(
                cornerRadius: 26,
                contentPadding: 14,
                tint: Color.black.opacity(usesPickerGlass ? 0.025 : 0.04),
                fillOpacity: usesPickerGlass ? 0.10 : nil,
                suppressShadow: usesPickerGlass,
                isInteractive: true
            ) {
                VStack(alignment: .leading, spacing: 13) {
                    HStack(alignment: .top, spacing: 10) {
                        WorkoutGlyphView(workout: workout)
                            .frame(width: 44, height: 44)

                        Spacer(minLength: 0)

                        Image(systemName: workout.isPersonalized ? "sparkles" : "plus")
                            .pulsarTextStyle(.captionEmphasis)
                            .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                            .frame(width: 26, height: 26)
                            .background(PulsarCircularGlassSurface(cornerRadius: 13, tint: .black, opacity: 0.86))
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(workout.name)
                            .pulsarTextStyle(.cardTitle)
                            .foregroundStyle(primaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)

                        Text(workout.category)
                            .pulsarTextStyle(.overline)
                            .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(categoryBackground, in: Capsule())
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(accentRim)
            .modifier(WorkoutOptionCardShadowModifier(
                workout: workout,
                usesPickerGlass: usesPickerGlass,
                colorScheme: colorScheme
            ))
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(WorkoutOptionCardButtonStyle(glowColor: workout.accent.color, reduceMotion: reduceMotion))
        .accessibilityLabel(workout.isPersonalized ? "\(workout.name), personalized training" : "\(workout.name), \(workout.category)")
        .accessibilityHint(workout.isPersonalized ? "Starts personalized training" : "Explores workout type")
    }

    private var primaryText: Color {
        PulsarTheme.fitnessPrimaryText(for: colorScheme)
    }

    private var accentRim: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        .white.opacity(colorScheme == .dark ? 0.12 : 0.54),
                        Color.black.opacity(0.06),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.75
            )
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }

    private var categoryBackground: Color {
        Color.black.opacity(0.045)
    }
}

private struct WorkoutGlyphView: View {
    var workout: WorkoutOption

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            PulsarCircularGlassSurface(cornerRadius: 22, tint: .black, opacity: 0.96)

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
                PulsarFitnessMonochromeDesign.secondaryText
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

private struct WorkoutOptionCardShadowModifier: ViewModifier {
    var workout: WorkoutOption
    var usesPickerGlass: Bool
    var colorScheme: ColorScheme

    func body(content: Content) -> some View {
        if usesPickerGlass {
            content
        } else {
            content
                .shadow(
                    color: workout.accent.color.opacity(colorScheme == .dark ? 0.10 : 0.08),
                    radius: 12,
                    y: 7
                )
        }
    }
}

private struct WorkoutOptionCardButtonStyle: ButtonStyle {
    var glowColor: Color
    var reduceMotion = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.965 : 1)
            .brightness(configuration.isPressed ? 0.045 : 0)
            .shadow(color: glowColor.opacity(configuration.isPressed ? 0.26 : 0), radius: 18, y: 8)
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.26, dampingFraction: 0.74), value: configuration.isPressed)
    }
}

#Preview {
    WorkoutOptionCard(workout: WorkoutOption.personalized[0]) { }
        .padding()
        .background(PulsarSectionBackground())
}
