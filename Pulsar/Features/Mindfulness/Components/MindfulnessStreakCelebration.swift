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
        "\(dayCount) day streak"
    }

    var message: String {
        dayCount == 1 ? "A calm start." : "Keep your rhythm."
    }
}

struct MindfulnessStreakToast: View {
    var celebration: MindfulnessStreakCelebration

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 12) {
            flame

            VStack(alignment: .leading, spacing: 3) {
                Text(celebration.title)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(celebration.message)
                    .pulsarTextStyle(.caption)
                    .foregroundStyle(MindfulnessVisualStyle.secondaryText)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 360)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            MindfulnessVisualStyle.softGold.opacity(0.14),
                            MindfulnessVisualStyle.calmBlue.opacity(0.09),
                            Color(red: 0.03, green: 0.08, blue: 0.14).opacity(0.40)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.34),
                            MindfulnessVisualStyle.softGold.opacity(0.30),
                            MindfulnessVisualStyle.calmBlue.opacity(0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )
        }
        .shadow(color: .black.opacity(0.28), radius: 16, y: 9)
        .shadow(color: MindfulnessVisualStyle.softGold.opacity(0.18), radius: 12)
        .pulsarLiquidGlass(
            cornerRadius: 22,
            tint: MindfulnessVisualStyle.softGold.opacity(0.14),
            isClear: false
        )
        .onAppear(perform: startAnimation)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(celebration.title). \(celebration.message)")
        .accessibilityIdentifier("mindfulness.streakCelebration")
    }

    private var flame: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(MindfulnessVisualStyle.softGold.opacity(0.82))
                    .frame(width: 3, height: 3)
                    .offset(
                        x: CGFloat(index - 1) * 8 + (isAnimating ? CGFloat(index - 1) * 2 : 0),
                        y: isAnimating ? -24 - CGFloat(index * 3) : -10
                    )
                    .opacity(reduceMotion ? 0 : (isAnimating ? 0.05 : 0.72))
            }

            Circle()
                .fill(MindfulnessVisualStyle.softGold.opacity(0.13))
                .frame(width: 44, height: 44)

            Image(systemName: "flame.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.yellow, MindfulnessVisualStyle.softGold, Color.orange],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .scaleEffect(reduceMotion ? 1 : (isAnimating ? 1.08 : 0.94))
                .rotationEffect(.degrees(reduceMotion ? 0 : (isAnimating ? 2 : -2)))
                .shadow(color: Color.orange.opacity(0.62), radius: 8)
        }
        .frame(width: 48, height: 48)
        .accessibilityHidden(true)
    }

    private func startAnimation() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true)) {
            isAnimating = true
        }
    }
}

#Preview("Mindfulness Streak") {
    ZStack {
        MindfulnessScenicBackground()

        MindfulnessStreakToast(
            celebration: MindfulnessStreakCelebration(dayCount: 3)
        )
        .padding(22)
    }
    .preferredColorScheme(.dark)
}
