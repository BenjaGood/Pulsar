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
    @Environment(\.scenePhase) private var scenePhase
    @State private var phase: DailyRewindPlaybackPhase = .arrival
    @State private var isShowingSummary = false
    @State private var isJournalPresented = false
    @State private var didStartPlayback = false
    @State private var storyProgress = 0.0
    @State private var isPlaybackPaused = false
    @State private var isInteractionPaused = false
    @State private var isScenePaused = false
    @GestureState private var storyDragTranslation: CGFloat = 0

    private var isPaused: Bool {
        isPlaybackPaused || isInteractionPaused || isScenePaused
    }

    private static let cinematicPhases: [DailyRewindPlaybackPhase] = [
        .arrival,
        .movement,
        .recovery,
        .mindfulness,
        .insight
    ]

    private static let playbackTick: TimeInterval = 1.0 / 30.0

    var body: some View {
        ZStack {
            DailyRewindBackdrop(
                tint: phaseTint,
                phase: phase,
                reduceTransparency: reduceTransparency,
                reduceMotion: reduceMotion,
                isPaused: isPaused,
                colorScheme: colorScheme
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                if phase == .summary || isShowingSummary || reduceMotion {
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
                storyProgress = 1
                isPlaybackPaused = false
                isInteractionPaused = false
                isScenePaused = false
                isShowingSummary = true
            } else {
                await playSequence()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard !isShowingSummary else { return }
            isScenePaused = newPhase != .active
        }
        .onChange(of: reduceMotion) { _, newValue in
            guard newValue else { return }
            storyProgress = 1
            isPlaybackPaused = false
            isInteractionPaused = false
            isScenePaused = false
            phase = .summary
            isShowingSummary = true
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
        VStack(spacing: 10) {
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

                if !reduceMotion && phase != .summary && !isShowingSummary {
                    Button {
                        withAnimation(.smooth(duration: 0.22)) {
                            isPlaybackPaused.toggle()
                        }
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                            .font(.footnote.weight(.bold))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(PulsarMindfulnessIconButtonStyle(tint: phaseTint.color))
                    .accessibilityLabel(isPaused ? "Resume Daily Rewind" : "Pause Daily Rewind")
                }

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(PulsarMindfulnessIconButtonStyle(tint: .secondary))
                .accessibilityLabel("Close Daily Rewind")
            }

            DailyRewindStoryProgressBar(
                phases: Self.cinematicPhases,
                activePhase: phase,
                progress: isShowingSummary ? 1 : storyProgress,
                isPaused: isPaused,
                activeTint: phaseTint
            )
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var cinematicContent: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                storyStage(in: proxy)
            }

            Button {
                showSummary(source: .manual)
            } label: {
                Label("View summary", systemImage: "rectangle.stack.fill")
                    .font(.headline.weight(.bold))
                    .padding(.vertical, 15)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PulsarMindfulnessActionButtonStyle(tint: phaseTint.color))
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
    }

    @ViewBuilder
    private func storyStage(in proxy: GeometryProxy) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 18) {
                storyStageContent(in: proxy)
            }
        } else {
            storyStageContent(in: proxy)
        }
    }

    private func storyStageContent(in proxy: GeometryProxy) -> some View {
        VStack(spacing: 22) {
            Spacer(minLength: 10)

            DailyRewindSignalHalo(
                phase: phase,
                tint: phaseTint,
                reduceMotion: reduceMotion,
                isPaused: isPaused
            )
            .frame(height: min(280, max(218, proxy.size.height * 0.38)))
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

            DailyRewindHighlightPanel(highlight: activeHighlight)
                .padding(.horizontal, 18)

            if !rewind.highlights.isEmpty {
                DailyRewindTimelineStrip(highlights: rewind.highlights, activeID: activeHighlight.id)
                    .padding(.horizontal, 18)
            }

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(x: storyDragTranslation * 0.055)
        .rotation3DEffect(
            .degrees(Double(storyDragTranslation / max(proxy.size.width, 1)) * -3.5),
            axis: (x: 0, y: 1, z: 0)
        )
        .scaleEffect(isPaused ? 0.992 : 1)
        .contentShape(Rectangle())
        .gesture(storyNavigationGesture(width: proxy.size.width))
        .onLongPressGesture(
            minimumDuration: 0.18,
            maximumDistance: 44,
            perform: {},
            onPressingChanged: { pressing in
                withAnimation(.smooth(duration: 0.18)) {
                    isInteractionPaused = pressing
                }
            }
        )
        .animation(reduceMotion ? nil : .smooth(duration: 0.52), value: phase)
        .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: isPaused)
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

    private var activeHighlight: DailyRewindHighlight {
        guard let firstHighlight = rewind.highlights.first else { return insightHighlight }
        switch phase {
        case .arrival:
            return firstHighlight
        case .movement:
            return rewind.highlights.first(where: { $0.id == DailyRewindCardKind.movement.rawValue }) ?? firstHighlight
        case .recovery:
            return rewind.highlights.first(where: { $0.id == DailyRewindCardKind.recovery.rawValue }) ??
                rewind.highlights.first(where: { $0.id == "hrv" }) ??
                firstHighlight
        case .mindfulness:
            return rewind.highlights.first(where: { $0.id == DailyRewindCardKind.mindfulness.rawValue }) ??
                rewind.highlights.first(where: { $0.id == DailyRewindCardKind.reflection.rawValue }) ??
                firstHighlight
        case .insight:
            return rewind.highlights.first(where: { $0.id == DailyRewindCardKind.stress.rawValue }) ??
                rewind.highlights.first(where: { $0.id == DailyRewindCardKind.energy.rawValue }) ??
                firstHighlight
        case .summary:
            return insightHighlight
        }
    }

    private var insightHighlight: DailyRewindHighlight {
        DailyRewindHighlight(
            id: "insight",
            title: "Insight",
            value: rewind.insight.title,
            caption: rewind.insight.body,
            symbolName: rewind.insight.symbolName,
            tint: rewind.insight.tint,
            state: .ready
        )
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
        activeHighlight.tint
    }

    @MainActor
    private func playSequence() async {
        storyProgress = 0

        while !Task.isCancelled && !isShowingSummary {
            let currentPhase = phase
            let duration = currentPhase.duration
            var elapsed = storyProgress * duration

            while elapsed < duration, !Task.isCancelled, phase == currentPhase, !isShowingSummary {
                await sleepForPlaybackTick()

                guard !Task.isCancelled, phase == currentPhase, !isShowingSummary else { break }
                guard !isPaused else { continue }

                elapsed += Self.playbackTick
                withAnimation(.linear(duration: Self.playbackTick)) {
                    storyProgress = min(elapsed / duration, 1)
                }
            }

            guard !Task.isCancelled, phase == currentPhase, !isShowingSummary else { continue }
            advancePhase(source: .automatic)
        }
    }

    private func sleepForPlaybackTick() async {
        try? await Task.sleep(nanoseconds: UInt64(Self.playbackTick * 1_000_000_000))
    }

    private func storyNavigationGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .updating($storyDragTranslation) { value, state, _ in
                state = value.translation.width
            }
            .onChanged { _ in
                if !isInteractionPaused {
                    isInteractionPaused = true
                }
            }
            .onEnded { value in
                isInteractionPaused = false
                handleStoryNavigation(value, width: width)
            }
    }

    private func handleStoryNavigation(_ value: DragGesture.Value, width: CGFloat) {
        let horizontalTravel = value.translation.width
        let predictedTravel = value.predictedEndTranslation.width
        let verticalTravel = abs(value.translation.height)
        let didSwipe = max(abs(horizontalTravel), abs(predictedTravel)) > max(44, width * 0.14) && verticalTravel < 96

        if didSwipe {
            if horizontalTravel < 0 || predictedTravel < 0 {
                advancePhase(source: .manual)
            } else {
                retreatPhase()
            }
            return
        }

        guard abs(horizontalTravel) < 12, verticalTravel < 12 else { return }

        if value.startLocation.x < width * 0.36 {
            retreatPhase()
        } else if value.startLocation.x > width * 0.64 {
            advancePhase(source: .manual)
        }
    }

    private func advancePhase(source: DailyRewindNavigationSource) {
        guard let currentIndex = Self.cinematicPhases.firstIndex(of: phase) else { return }

        if currentIndex == Self.cinematicPhases.index(before: Self.cinematicPhases.endIndex) {
            showSummary(source: source)
            return
        }

        setPhase(Self.cinematicPhases[currentIndex + 1], source: source)
    }

    private func retreatPhase() {
        guard let currentIndex = Self.cinematicPhases.firstIndex(of: phase), currentIndex > 0 else {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) {
                storyProgress = 0
            }
            return
        }

        setPhase(Self.cinematicPhases[currentIndex - 1], source: .manual)
    }

    private func setPhase(_ nextPhase: DailyRewindPlaybackPhase, source: DailyRewindNavigationSource) {
        guard nextPhase != phase else { return }

        withAnimation(reduceMotion ? nil : .smooth(duration: source == .manual ? 0.46 : 0.68)) {
            phase = nextPhase
            storyProgress = 0
        }

        if source == .manual || nextPhase != .arrival {
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private func showSummary(source: DailyRewindNavigationSource) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.62)) {
            phase = .summary
            storyProgress = 1
            isPlaybackPaused = false
            isInteractionPaused = false
            isScenePaused = false
            isShowingSummary = true
        }

        if source == .manual {
            UISelectionFeedbackGenerator().selectionChanged()
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

    var duration: TimeInterval {
        switch self {
        case .arrival:
            return 2.8
        case .movement, .recovery, .mindfulness:
            return 4.2
        case .insight:
            return 4.8
        case .summary:
            return 0
        }
    }
}

private enum DailyRewindNavigationSource {
    case automatic
    case manual
}

private struct DailyRewindBackdrop: View {
    var tint: DailyRewindTint
    var phase: DailyRewindPlaybackPhase
    var reduceTransparency: Bool
    var reduceMotion: Bool
    var isPaused: Bool
    var colorScheme: ColorScheme
    @State private var isBreathing = false

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
                    center: glowCenter,
                    startRadius: 24,
                    endRadius: 520
                )
                .scaleEffect(ambientScale)
                .offset(x: ambientOffset.width, y: ambientOffset.height)

                LinearGradient(
                    colors: [
                        Color.black.opacity(colorScheme == .dark ? 0.22 : 0.02),
                        tint.color.opacity(colorScheme == .dark ? 0.12 : 0.07),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .opacity(isPaused ? 0.72 : 1)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 4.8).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 1.0), value: phase)
        .animation(reduceMotion ? nil : .smooth(duration: 0.26), value: isPaused)
    }

    private var glowCenter: UnitPoint {
        guard !reduceMotion else { return .topTrailing }
        if isPaused { return .top }

        switch phase {
        case .arrival, .movement:
            return .topTrailing
        case .recovery:
            return .topLeading
        case .mindfulness:
            return .bottomTrailing
        case .insight, .summary:
            return .center
        }
    }

    private var ambientScale: CGFloat {
        guard !reduceMotion, !isPaused else { return 1 }
        return isBreathing ? 1.08 : 0.96
    }

    private var ambientOffset: CGSize {
        guard !reduceMotion, !isPaused else { return .zero }
        let direction = phase.rawValue.isMultiple(of: 2) ? 1.0 : -1.0
        return CGSize(
            width: (isBreathing ? -18 : 12) * direction,
            height: isBreathing ? 14 : -10
        )
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
    var isPaused: Bool
    @State private var isBreathing = false

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
                    .opacity(opacity(for: index) * (isPaused ? 0.72 : 1))
                    .blur(radius: CGFloat(index) * 0.4)
            }

            coreSurface
                .scaleEffect(coreScale)
                .shadow(color: tint.color.opacity(0.28), radius: 38, y: 18)

            Image(systemName: symbolName)
                .font(.system(size: 42, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary.opacity(0.76))
                .shadow(color: tint.color.opacity(0.20), radius: 10, y: 4)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 1.1), value: phase)
        .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: isPaused)
    }

    @ViewBuilder
    private var coreSurface: some View {
        if #available(iOS 26.0, *) {
            Circle()
                .fill(tint.color.opacity(0.06))
                .frame(width: 128, height: 128)
                .glassEffect(.regular, in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.24), lineWidth: 0.8)
                }
        } else {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.22), lineWidth: 0.8)
                }
                .frame(width: 128, height: 128)
        }
    }

    private var symbolName: String {
        switch phase {
        case .arrival: "arrow.counterclockwise"
        case .movement: "figure.walk"
        case .recovery: "heart.text.square.fill"
        case .mindfulness: "figure.mind.and.body"
        case .insight: "sparkles"
        case .summary: "rectangle.stack.fill"
        }
    }

    private func scale(for index: Int) -> CGFloat {
        let phaseOffset = CGFloat(phase.rawValue) * 0.045
        let breathOffset: CGFloat = isBreathing && !reduceMotion && !isPaused ? 0.025 : 0
        return 0.58 + CGFloat(index) * 0.20 + phaseOffset + breathOffset
    }

    private func opacity(for index: Int) -> Double {
        max(0.14, 0.58 - Double(index) * 0.10)
    }

    private var coreScale: CGFloat {
        guard !reduceMotion, !isPaused else { return 1 }
        return isBreathing ? 1.035 : 0.985
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
                    .contentTransition(.opacity)

                VStack(alignment: .leading, spacing: 5) {
                    Text(highlight.title)
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                    Text(highlight.value)
                        .font(.title2.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                        .contentTransition(.opacity)
                    Text(highlight.caption)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .contentTransition(.opacity)
                }

                Spacer(minLength: 0)
            }
            .frame(minHeight: 86, alignment: .center)
        }
        .frame(minHeight: 122)
        .animation(.smooth(duration: 0.48), value: highlight.id)
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

private struct DailyRewindStoryProgressBar: View {
    var phases: [DailyRewindPlaybackPhase]
    var activePhase: DailyRewindPlaybackPhase
    var progress: Double
    var isPaused: Bool
    var activeTint: DailyRewindTint

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(phases.enumerated()), id: \.offset) { index, phase in
                GeometryReader { proxy in
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.12))
                        .overlay(alignment: .leading) {
                            Capsule(style: .continuous)
                                .fill(fillColor(for: phase, index: index))
                                .frame(width: proxy.size.width * fillAmount(for: phase, index: index))
                        }
                }
                .frame(height: 4)
            }
        }
        .frame(height: 4)
        .accessibilityLabel("Daily Rewind progress")
        .accessibilityValue(accessibilityValue)
        .animation(.linear(duration: 0.12), value: progress)
        .animation(.smooth(duration: 0.24), value: activePhase)
    }

    private func fillAmount(for phase: DailyRewindPlaybackPhase, index: Int) -> CGFloat {
        guard let activeIndex = phases.firstIndex(of: activePhase) else {
            return activePhase == .summary ? 1 : 0
        }
        if index < activeIndex { return 1 }
        if phase == activePhase { return CGFloat(min(max(progress, 0), 1)) }
        return 0
    }

    private func fillColor(for phase: DailyRewindPlaybackPhase, index: Int) -> Color {
        guard let activeIndex = phases.firstIndex(of: activePhase) else {
            return activeTint.color.opacity(0.82)
        }
        if phase == activePhase {
            return activeTint.color.opacity(isPaused ? 0.52 : 0.88)
        }
        if index < activeIndex {
            return Color.primary.opacity(0.64)
        }
        return Color.primary.opacity(0.52)
    }

    private var accessibilityValue: String {
        guard let activeIndex = phases.firstIndex(of: activePhase) else {
            return activePhase == .summary ? "Complete" : ""
        }
        return "Section \(activeIndex + 1) of \(phases.count)"
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
