//
//  DailyRewindView.swift
//  Pulsar
//

import SwiftUI
import UIKit

struct DailyRewindView: View {
    let rewind: PulsarDailyRewind
    @ObservedObject var mindfulnessStore: PulsarMindfulnessStore
    var onDismiss: () -> Void
    var onJournalSaved: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @State private var phase: DailyRewindPlaybackPhase = .arrival
    @State private var isJournalPresented = false
    @State private var didStartPlayback = false

    var body: some View {
        ZStack {
            DailyRewindBackdrop(
                tint: phaseTint,
                reduceTransparency: reduceTransparency,
                colorScheme: colorScheme
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                if phase == .summary || reduceMotion {
                    summaryContent
                        .transition(.opacity)
                } else {
                    cinematicContent
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
        }
        .task(id: rewind.id) {
            guard !didStartPlayback else { return }
            didStartPlayback = true
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            if reduceMotion {
                phase = .summary
            } else {
                await playSequence()
            }
        }
        .sheet(isPresented: $isJournalPresented) {
            DailyJournalCheckInSheet(draft: mindfulnessStore.draft(for: rewind.date)) { draft in
                mindfulnessStore.saveCheckIn(draft)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onJournalSaved()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Daily Rewind")
                    .font(.caption.weight(.black))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text(rewind.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.subheadline.weight(.semibold))
            }

            Spacer()

            DailyRewindProgressPill(phase: phase)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(PulsarMindfulnessIconButtonStyle(tint: .secondary))
            .accessibilityLabel("Close Daily Rewind")
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var cinematicContent: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 18)

            DailyRewindSignalHalo(
                phase: phase,
                tint: phaseTint,
                reduceMotion: reduceMotion
            )
            .frame(height: 280)
            .padding(.horizontal, 20)

            VStack(spacing: 10) {
                Text(phaseTitle)
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)

                Text(phaseSubtitle)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 28)

            if let highlight = phaseHighlight {
                DailyRewindHighlightPanel(highlight: highlight)
                    .padding(.horizontal, 18)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            DailyRewindTimelineStrip(highlights: rewind.highlights, activeID: phaseHighlight?.id)
                .padding(.horizontal, 18)

            Spacer(minLength: 20)

            Button {
                withAnimation(.smooth(duration: 0.6)) {
                    phase = .summary
                }
                UISelectionFeedbackGenerator().selectionChanged()
            } label: {
                Label("View summary", systemImage: "rectangle.stack.fill")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
    }

    private var summaryContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(rewind.headline)
                        .font(.largeTitle.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(rewind.subtitle)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 20)

                DailyRewindInsightCard(insight: rewind.insight)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    ForEach(rewind.cards) { card in
                        DailyRewindSummaryCard(card: card)
                    }
                }

                journalPrompt

                Button(action: onDismiss) {
                    Text("Done")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 4)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 34)
        }
        .scrollContentBackground(.hidden)
        .premiumScrollHeaderBlur()
    }

    private var journalPrompt: some View {
        Group {
            if let entry = mindfulnessStore.entry(on: rewind.date) {
                PulsarMindfulnessGlassCard(cornerRadius: 26) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.green)
                            .frame(width: 44, height: 44)
                            .background(.green.opacity(0.13), in: Circle())

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your day is complete.")
                                .font(.title3.weight(.bold))
                            Text("Thanks for taking a moment to reflect.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Today feels \(entry.moodTitle.lowercased()). Pulsar folded this into your mindfulness insights.")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Button("Update check-in") {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                isJournalPresented = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .padding(.top, 4)
                        }

                        Spacer(minLength: 0)
                    }
                }
            } else {
                PulsarMindfulnessGlassCard(cornerRadius: 26) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "heart.text.square.fill")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.purple)
                                .frame(width: 44, height: 44)
                                .background(.purple.opacity(0.13), in: Circle())

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Before the day ends, how did you feel today?")
                                    .font(.title3.weight(.bold))
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("Add mood, energy, stress, gratitude, and optional notes so Rewind can connect your emotional signal over time.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            isJournalPresented = true
                        } label: {
                            Label("Add check-in", systemImage: "square.and.pencil")
                                .font(.headline.weight(.bold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
            }
        }
    }

    private var phaseHighlight: DailyRewindHighlight? {
        guard !rewind.highlights.isEmpty else { return nil }
        switch phase {
        case .arrival:
            return nil
        case .movement:
            return rewind.highlights.first(where: { $0.id == DailyRewindCardKind.movement.rawValue }) ?? rewind.highlights.first
        case .recovery:
            return rewind.highlights.first(where: { $0.id == DailyRewindCardKind.recovery.rawValue }) ??
                rewind.highlights.first(where: { $0.id == "hrv" }) ??
                rewind.highlights.first
        case .mindfulness:
            return rewind.highlights.first(where: { $0.id == DailyRewindCardKind.mindfulness.rawValue }) ??
                rewind.highlights.first(where: { $0.id == DailyRewindCardKind.reflection.rawValue }) ??
                rewind.highlights.first
        case .insight:
            return rewind.highlights.first(where: { $0.id == DailyRewindCardKind.stress.rawValue }) ??
                rewind.highlights.first(where: { $0.id == DailyRewindCardKind.energy.rawValue }) ??
                rewind.highlights.first
        case .summary:
            return nil
        }
    }

    private var phaseTitle: String {
        switch phase {
        case .arrival:
            return rewind.headline
        case .movement:
            return "Movement surfaced first"
        case .recovery:
            return "Recovery came into focus"
        case .mindfulness:
            return "Mindfulness softened the signal"
        case .insight:
            return rewind.insight.title
        case .summary:
            return "Daily summary"
        }
    }

    private var phaseSubtitle: String {
        switch phase {
        case .arrival:
            return rewind.subtitle
        case .movement:
            return "Steps, workouts, and active energy become the first thread of the day."
        case .recovery:
            return "HRV, sleep, and readiness add the body’s quieter context."
        case .mindfulness:
            return "Breathing, meditation, and journaling complete the emotional picture."
        case .insight:
            return rewind.insight.body
        case .summary:
            return rewind.subtitle
        }
    }

    private var phaseTint: DailyRewindTint {
        phaseHighlight?.tint ?? rewind.insight.tint
    }

    private func playSequence() async {
        let phases: [DailyRewindPlaybackPhase] = [.arrival, .movement, .recovery, .mindfulness, .insight, .summary]
        for phase in phases {
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.smooth(duration: 0.82)) {
                    self.phase = phase
                }
                if phase != .arrival && phase != .summary {
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
            let delay: UInt64 = phase == .arrival ? 2_000_000_000 : 3_200_000_000
            try? await Task.sleep(nanoseconds: delay)
        }
    }
}

private enum DailyRewindPlaybackPhase: Int, CaseIterable {
    case arrival
    case movement
    case recovery
    case mindfulness
    case insight
    case summary
}

private struct DailyRewindBackdrop: View {
    var tint: DailyRewindTint
    var reduceTransparency: Bool
    var colorScheme: ColorScheme

    var body: some View {
        ZStack {
            base

            if !reduceTransparency {
                RadialGradient(
                    colors: [
                        tint.color.opacity(colorScheme == .dark ? 0.34 : 0.22),
                        tint.color.opacity(0.03),
                        .clear
                    ],
                    center: .topTrailing,
                    startRadius: 24,
                    endRadius: 520
                )

                LinearGradient(
                    colors: [
                        Color.black.opacity(colorScheme == .dark ? 0.22 : 0.02),
                        tint.color.opacity(colorScheme == .dark ? 0.12 : 0.07),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    private var base: some View {
        colorScheme == .dark
            ? LinearGradient(
                colors: [
                    Color(red: 0.025, green: 0.030, blue: 0.045),
                    Color(red: 0.055, green: 0.070, blue: 0.105),
                    Color(red: 0.015, green: 0.017, blue: 0.024)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            : LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.985, blue: 1.00),
                    Color(red: 0.91, green: 0.94, blue: 0.98),
                    Color(red: 0.98, green: 0.98, blue: 0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
    }
}

private struct DailyRewindSignalHalo: View {
    var phase: DailyRewindPlaybackPhase
    var tint: DailyRewindTint
    var reduceMotion: Bool

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            colors: [
                                tint.color.opacity(0.0),
                                tint.color.opacity(0.45 - Double(index) * 0.07),
                                .white.opacity(0.18),
                                tint.color.opacity(0.0)
                            ],
                            center: .center
                        ),
                        lineWidth: 1.1
                    )
                    .scaleEffect(scale(for: index))
                    .opacity(opacity(for: index))
                    .blur(radius: CGFloat(index) * 0.4)
            }

            Circle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.22), lineWidth: 0.8)
                }
                .frame(width: 128, height: 128)
                .shadow(color: tint.color.opacity(0.28), radius: 38, y: 18)

            Image(systemName: symbolName)
                .font(.system(size: 42, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint.color)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .smooth(duration: 1.1), value: phase)
    }

    private var symbolName: String {
        switch phase {
        case .arrival: "arrow.counterclockwise.circle.fill"
        case .movement: "figure.walk"
        case .recovery: "heart.text.square.fill"
        case .mindfulness: "figure.mind.and.body"
        case .insight: "sparkles"
        case .summary: "rectangle.stack.fill"
        }
    }

    private func scale(for index: Int) -> CGFloat {
        let phaseOffset = CGFloat(phase.rawValue) * 0.045
        return 0.58 + CGFloat(index) * 0.20 + phaseOffset
    }

    private func opacity(for index: Int) -> Double {
        max(0.14, 0.58 - Double(index) * 0.10)
    }
}

private struct DailyRewindHighlightPanel: View {
    var highlight: DailyRewindHighlight

    var body: some View {
        PulsarMindfulnessGlassCard(cornerRadius: 28) {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: highlight.symbolName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(highlight.tint.color)
                    .frame(width: 48, height: 48)
                    .background(highlight.tint.color.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(highlight.title)
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                    Text(highlight.value)
                        .font(.title2.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                    Text(highlight.caption)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
        }
    }
}

private struct DailyRewindTimelineStrip: View {
    var highlights: [DailyRewindHighlight]
    var activeID: String?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(highlights) { highlight in
                Capsule(style: .continuous)
                    .fill(highlight.id == activeID ? highlight.tint.color.opacity(0.84) : Color.white.opacity(0.18))
                    .frame(height: 5)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(.white.opacity(highlight.id == activeID ? 0.28 : 0.10), lineWidth: 0.7)
                    }
            }
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}

private struct DailyRewindProgressPill: View {
    var phase: DailyRewindPlaybackPhase

    var body: some View {
        HStack(spacing: 5) {
            ForEach(DailyRewindPlaybackPhase.allCases, id: \.rawValue) { item in
                Circle()
                    .fill(item.rawValue <= phase.rawValue ? Color.primary.opacity(0.72) : Color.secondary.opacity(0.24))
                    .frame(width: 5, height: 5)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .pulsarLiquidGlass(cornerRadius: 18)
        .accessibilityLabel("Daily Rewind progress")
    }
}

private struct DailyRewindInsightCard: View {
    var insight: DailyRewindInsight

    var body: some View {
        PulsarMindfulnessGlassCard(cornerRadius: 28) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: insight.symbolName)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(insight.tint.color)
                        .frame(width: 40, height: 40)
                        .background(insight.tint.color.opacity(0.13), in: Circle())

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Insight")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.secondary)
                        Text(insight.title)
                            .font(.title3.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Text(insight.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(insight.evidence)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(insight.tint.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(insight.tint.color.opacity(0.12), in: Capsule(style: .continuous))
            }
        }
    }
}

private struct DailyRewindSummaryCard: View {
    var card: DailyRewindCard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: card.symbolName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(card.tint.color)
                    .frame(width: 34, height: 34)
                    .background(card.tint.color.opacity(0.13), in: Circle())
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                Text(card.value)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                Text(card.subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .pulsarLiquidGlass(cornerRadius: 22)
        .opacity(card.state == .placeholder ? 0.74 : 1)
    }
}

#if DEBUG
#Preview("Daily Rewind") {
    let store = PulsarMindfulnessStore()
    let rewind = DailyRewindBuilder().build(
        dashboard: .sample,
        mindfulness: store.state
    )
    DailyRewindView(rewind: rewind, mindfulnessStore: store, onDismiss: {}, onJournalSaved: {})
}
#endif
