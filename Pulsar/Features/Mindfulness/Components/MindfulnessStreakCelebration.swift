//
//  MindfulnessStreakCelebration.swift
//  Pulsar
//

import SwiftUI

struct MindfulnessStreakCelebration: Identifiable, Equatable {
    let id: UUID
    let dayCount: Int

    init(id: UUID = UUID(), dayCount: Int) {
        self.id = id
        self.dayCount = max(1, dayCount)
    }

    var title: String {
        dayCount == 1 ? "1 day streak" : "\(dayCount)-day streak"
    }

    var message: String {
        dayCount == 1 ? "A calm start." : "Keep your rhythm."
    }
}

struct MindfulnessStreakStatusCapsule: View {
    var dayCount: Int

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "flame.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Logged")
                    .font(.subheadline)
                    .foregroundStyle(MindfulnessDesign.primaryText)

                Text(dayText)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(MindfulnessDesign.secondaryText)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .fixedSize(horizontal: true, vertical: false)
        .mindfulnessCardSurface(cornerRadius: 26, shadowOpacity: 0.035)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("mindfulness.pendingStreak")
    }

    private var dayText: String {
        let clampedDayCount = max(0, dayCount)
        return clampedDayCount == 1 ? "1 day" : "\(clampedDayCount) days"
    }

    private var accessibilityLabel: String {
        if dayCount <= 0 {
            return "No active streak. Today is not logged yet."
        }
        return "Current streak: \(dayText). Today is not logged yet."
    }
}

struct MindfulnessLoggedStreakSummary: View {
    var dayCount: Int
    var isCelebrating: Bool

    var body: some View {
        VStack(spacing: 7) {
            MindfulnessFlameMark(
                size: 84,
                isActive: true,
                isCelebrating: isCelebrating
            )

            Text(dayText)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.yellow, MindfulnessVisualStyle.neonFlame],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Mood logged today")
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(MindfulnessVisualStyle.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 178)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mood logged today. Current streak: \(dayText).")
        .accessibilityIdentifier("mindfulness.loggedStreak")
    }

    private var dayText: String {
        let clampedDayCount = max(1, dayCount)
        return clampedDayCount == 1 ? "1 day" : "\(clampedDayCount) days"
    }
}

private struct MindfulnessFlameMark: View {
    var size: CGFloat
    var isActive: Bool
    var isCelebrating = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            MindfulnessVisualStyle.neonFlame.opacity(0.24),
                            MindfulnessVisualStyle.neonFlame.opacity(0.08),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.54
                    )
                )
                .scaleEffect(reduceMotion ? 1 : (isAnimating ? 1.10 : 0.92))
                .opacity(reduceMotion ? 0.95 : (isAnimating ? 1 : 0.70))

            Circle()
                .fill(MindfulnessVisualStyle.neonFlame.opacity(isCelebrating ? 0.18 : 0.12))
                .blur(radius: size * 0.11)
                .scaleEffect(reduceMotion ? 1 : (isAnimating ? 0.72 : 0.96))
                .offset(y: size * 0.18)

            Image(systemName: "flame.fill")
                .font(.system(size: size * 0.48, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.yellow, MindfulnessVisualStyle.neonFlame, Color.orange],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .rotationEffect(.degrees(reduceMotion ? 0 : (isAnimating ? rotationAmount : -rotationAmount)))
                .scaleEffect(x: reduceMotion ? 1 : (isAnimating ? 0.92 : 1.04), y: reduceMotion ? 1 : (isAnimating ? 1.08 : 0.96))
                .offset(y: reduceMotion ? 0 : (isAnimating ? -size * 0.015 : size * 0.012))
                .shadow(
                    color: MindfulnessVisualStyle.neonFlame.opacity(0.90),
                    radius: size * (isCelebrating ? 0.16 : 0.12)
                )

            Image(systemName: "flame.fill")
                .font(.system(size: size * 0.25, weight: .heavy))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.white.opacity(0.92), Color.yellow.opacity(0.88), MindfulnessVisualStyle.neonFlame.opacity(0.40)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .scaleEffect(reduceMotion ? 1 : (isAnimating ? 1.10 : 0.78))
                .rotationEffect(.degrees(reduceMotion ? 0 : (isAnimating ? -4 : 5)))
                .offset(x: reduceMotion ? 0 : (isAnimating ? -size * 0.015 : size * 0.018), y: reduceMotion ? size * 0.055 : (isAnimating ? size * 0.02 : size * 0.075))
                .opacity(isActive ? (reduceMotion ? 0.82 : (isAnimating ? 0.92 : 0.62)) : 0.58)

            if isActive {
                Circle()
                    .fill(Color.yellow.opacity(reduceMotion ? 0.68 : (isAnimating ? 0.75 : 0.22)))
                    .frame(width: size * 0.055, height: size * 0.055)
                    .blur(radius: size * 0.01)
                    .offset(x: size * 0.22, y: reduceMotion ? -size * 0.15 : (isAnimating ? -size * 0.29 : -size * 0.08))
                    .scaleEffect(reduceMotion ? 1 : (isAnimating ? 0.62 : 1.18))
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(reduceMotion ? 1 : (isAnimating ? expandedScale : contractedScale))
        .accessibilityHidden(true)
        .onAppear {
            updateAnimation(isActive: isActive)
        }
        .onChange(of: isActive) { _, newValue in
            updateAnimation(isActive: newValue)
        }
        .onChange(of: reduceMotion) { _, _ in
            updateAnimation(isActive: isActive)
        }
    }

    private var rotationAmount: Double {
        isCelebrating ? 3.2 : 2
    }

    private var expandedScale: CGFloat {
        isCelebrating ? 1.10 : 1.06
    }

    private var contractedScale: CGFloat {
        isCelebrating ? 0.93 : 0.96
    }

    private func updateAnimation(isActive: Bool) {
        guard !reduceMotion, isActive else {
            withAnimation(.easeOut(duration: 0.16)) {
                isAnimating = false
            }
            return
        }

        isAnimating = false
        withAnimation(.easeInOut(duration: 0.66).repeatForever(autoreverses: true)) {
            isAnimating = true
        }
    }
}

#Preview("Mindfulness Streak States") {
    ZStack {
        MindfulnessScenicBackground()

        VStack(spacing: 30) {
            MindfulnessStreakStatusCapsule(dayCount: 3)
            MindfulnessLoggedStreakSummary(dayCount: 4, isCelebrating: true)
        }
        .padding(22)
    }
    .preferredColorScheme(.dark)
}
