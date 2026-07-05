//
//  MindfulnessComponents.swift
//  Pulsar
//

import Foundation
import SwiftUI

enum MindfulnessVisualStyle {
    static let calmBlue = Color(red: 0.38, green: 0.72, blue: 1.00)
    static let mint = Color(red: 0.38, green: 0.88, blue: 0.72)
    static let lavender = Color(red: 0.70, green: 0.60, blue: 0.98)
    static let softGold = Color(red: 0.94, green: 0.73, blue: 0.38)
    static let softRose = Color(red: 0.96, green: 0.56, blue: 0.60)
    static let neonViolet = Color(red: 0.78, green: 0.30, blue: 1.00)
    static let neonBlue = Color(red: 0.24, green: 0.48, blue: 1.00)
    static let neonAmber = Color(red: 1.00, green: 0.70, blue: 0.12)
    static let neonCyan = Color(red: 0.10, green: 0.72, blue: 1.00)
    static let neonMint = Color(red: 0.16, green: 1.00, blue: 0.58)
    static let neonFlame = Color(red: 1.00, green: 0.46, blue: 0.08)
    static let secondaryText = Color.white.opacity(0.70)
    static let tertiaryText = Color.white.opacity(0.52)

    static func moodColor(for wellnessAverage: Double?) -> Color {
        guard let wellnessAverage else { return Color.white.opacity(0.22) }
        return switch wellnessAverage {
        case 0.74...: mint
        case 0.58..<0.74: calmBlue
        case 0.42..<0.58: softGold
        default: lavender
        }
    }
}

struct PulsarMindfulnessGlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 28
    var contentPadding: CGFloat = 18
    var tint: Color?
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        cornerRadius: CGFloat = 28,
        contentPadding: CGFloat = 18,
        tint: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.contentPadding = contentPadding
        self.tint = tint
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if tint != nil {
            baseContent
                .background {
                    shape.fill(
                        Color.black
                            .opacity(reduceTransparency ? 0.84 : 0.22)
                    )
                }
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(reduceTransparency ? 0.05 : 0.10),
                                .white.opacity(0.02),
                                Color.black.opacity(reduceTransparency ? 0.06 : 0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .allowsHitTesting(false)
                }
                .overlay {
                    shape.strokeBorder(.white.opacity(reduceTransparency ? 0.26 : 0.18), lineWidth: 0.9)
                }
                .shadow(color: .black.opacity(0.18), radius: 16, y: 9)
                .pulsarLiquidGlass(cornerRadius: cornerRadius, isClear: true)
        } else {
            baseContent
                .background {
                    shape.fill(
                        Color.black
                            .opacity(reduceTransparency ? 0.84 : 0.18)
                    )
                }
                .overlay {
                    shape.strokeBorder(.white.opacity(reduceTransparency ? 0.24 : 0.14), lineWidth: 0.8)
                }
                .pulsarLiquidGlass(cornerRadius: cornerRadius)
        }
    }

    private var baseContent: some View {
        content
            .padding(contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MindfulnessPageTitleHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 14) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.16), lineWidth: 0.8)
                    .padding(5)

                Image(systemName: "camera.macro")
                    .font(.system(size: 30, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.90))
            }
            .frame(width: 58, height: 58)
            .background(.black.opacity(0.14), in: Circle())
            .pulsarLiquidGlass(
                cornerRadius: 29,
                tint: MindfulnessVisualStyle.calmBlue.opacity(0.08),
                isClear: true
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Mindfulness")
                    .font(.system(.largeTitle, design: .default, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .accessibilityAddTraits(.isHeader)

                Text("Understand your mind.\nElevate your day.")
                    .pulsarTextStyle(.screenSubtitle)
                    .foregroundStyle(MindfulnessVisualStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct MindfulnessScenicBackground: View {
    var body: some View {
        Image("MindfulnessBackground")
            .resizable()
            .scaledToFill()
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [.black.opacity(0.48), .black.opacity(0.13), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 280)
            }
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.22), .black.opacity(0.66)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 430)
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

private enum MindfulnessMoodLevel: Int, CaseIterable, Identifiable {
    case veryLow
    case low
    case neutral
    case good
    case great

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .veryLow: "Very Low"
        case .low: "Low"
        case .neutral: "Neutral"
        case .good: "Good"
        case .great: "Great"
        }
    }

    var valence: Double {
        Double(rawValue - 2) / 2
    }

    var tint: Color {
        switch self {
        case .veryLow: MindfulnessVisualStyle.neonViolet
        case .low: MindfulnessVisualStyle.neonBlue
        case .neutral: MindfulnessVisualStyle.neonAmber
        case .good: MindfulnessVisualStyle.neonCyan
        case .great: MindfulnessVisualStyle.neonMint
        }
    }

    var mouthControlY: CGFloat {
        switch self {
        case .veryLow: 0.38
        case .low: 0.46
        case .neutral: 0.60
        case .good: 0.73
        case .great: 0.82
        }
    }

    static func nearest(to valence: Double) -> MindfulnessMoodLevel {
        allCases.min {
            abs($0.valence - valence) < abs($1.valence - valence)
        } ?? .neutral
    }
}

private enum MindfulnessMetricKind: String, CaseIterable, Identifiable {
    case energy
    case stress
    case gratitude
    case anxiety
    case social
    case productivity
    case sleep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .energy: "Energy"
        case .stress: "Stress"
        case .gratitude: "Gratitude"
        case .anxiety: "Anxiety"
        case .social: "Social"
        case .productivity: "Productivity"
        case .sleep: "Sleep"
        }
    }

    var symbolName: String {
        switch self {
        case .energy: "bolt.fill"
        case .stress: "water.waves"
        case .gratitude: "heart.fill"
        case .anxiety: "cloud.fill"
        case .social: "person.2.fill"
        case .productivity: "scope"
        case .sleep: "moon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .energy: MindfulnessVisualStyle.mint
        case .stress: MindfulnessVisualStyle.lavender
        case .gratitude: MindfulnessVisualStyle.softRose
        case .anxiety: MindfulnessVisualStyle.calmBlue
        case .social: MindfulnessVisualStyle.softGold
        case .productivity: Color(red: 0.30, green: 0.82, blue: 0.80)
        case .sleep: MindfulnessVisualStyle.lavender
        }
    }

    var keyPath: WritableKeyPath<PulsarDailyJournalDraft, Double> {
        switch self {
        case .energy: \PulsarDailyJournalDraft.energy
        case .stress: \PulsarDailyJournalDraft.stress
        case .gratitude: \PulsarDailyJournalDraft.gratitude
        case .anxiety: \PulsarDailyJournalDraft.anxiety
        case .social: \PulsarDailyJournalDraft.socialConnection
        case .productivity: \PulsarDailyJournalDraft.productivity
        case .sleep: \PulsarDailyJournalDraft.sleepPerception
        }
    }
}

struct MindfulnessMoodLoggingCard: View {
    @Binding var draft: PulsarDailyJournalDraft
    var loggedEntry: PulsarDailyJournalEntry?
    var loggedStreakDays: Int = 0
    var isCelebratingStreak = false
    var onLog: () -> Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isEditingLoggedMood = false
    @State private var moodFeedbackSequence = 0

    var body: some View {
        PulsarMindfulnessGlassCard(
            cornerRadius: 30,
            contentPadding: 14,
            tint: MindfulnessVisualStyle.calmBlue.opacity(0.14)
        ) {
            VStack(alignment: .leading, spacing: 8) {
                moodHeader

                PulsarGlassEffectGroup(spacing: 8) {
                    LazyVGrid(columns: moodColumns, spacing: 8) {
                        ForEach(MindfulnessMoodLevel.allCases) { mood in
                            let isLogged = loggedMood == mood
                            MindfulnessMoodButton(
                                mood: mood,
                                isSelected: selectedMood == mood,
                                isLogged: isLogged
                            ) {
                                guard selectedMood != mood else { return }
                                withAnimation(reduceMotion ? nil : .smooth(duration: 0.22)) {
                                    draft.valence = mood.valence
                                }
                                moodFeedbackSequence += 1
                            }
                        }
                    }
                }
                .disabled(!showsSignalEditor)
                .sensoryFeedback(.selection, trigger: moodFeedbackSequence)

                Rectangle()
                    .fill(.white.opacity(0.12))
                    .frame(height: 0.75)

                Group {
                    if showsSignalEditor {
                        LazyVGrid(columns: signalColumns, alignment: .leading, spacing: 4) {
                            ForEach(MindfulnessMetricKind.allCases) { metric in
                                MindfulnessInlineSignalSlider(
                                    metric: metric,
                                    value: $draft[dynamicMember: metric.keyPath]
                                )
                            }
                        }
                        .transition(.opacity)
                    } else {
                        MindfulnessLoggedStreakSummary(
                            dayCount: max(1, loggedStreakDays),
                            isCelebrating: isCelebratingStreak
                        )
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .scale(scale: 0.96).combined(with: .opacity)
                        )
                    }
                }
                .animation(
                    reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.38, dampingFraction: 0.84),
                    value: showsSignalEditor
                )

                Button(action: handlePrimaryAction) {
                    Text(primaryActionTitle)
                        .pulsarTextStyle(.buttonTitle)
                        .frame(maxWidth: .infinity, minHeight: 24)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.roundedRectangle(radius: 16))
                .controlSize(.regular)
                .tint(MindfulnessVisualStyle.calmBlue.opacity(0.48))
                .foregroundStyle(.white)
                .accessibilityHint(primaryActionHint)
            }
        }
        .onChange(of: loggedEntry?.id) { _, newEntryID in
            guard newEntryID == nil else { return }
            isEditingLoggedMood = false
        }
    }

    private var moodColumns: [GridItem] {
        let columnCount = dynamicTypeSize.isAccessibilitySize ? 2 : 5
        return Array(
            repeating: GridItem(.flexible(minimum: 44), spacing: 5, alignment: .top),
            count: columnCount
        )
    }

    private var signalColumns: [GridItem] {
        let columnCount = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(
            repeating: GridItem(.flexible(minimum: 130), spacing: 18, alignment: .top),
            count: columnCount
        )
    }

    private var selectedMood: MindfulnessMoodLevel {
        MindfulnessMoodLevel.nearest(to: draft.valence)
    }

    private var loggedMood: MindfulnessMoodLevel? {
        loggedEntry.map { MindfulnessMoodLevel.nearest(to: $0.valence) }
    }

    private var showsSignalEditor: Bool {
        loggedEntry == nil || isEditingLoggedMood
    }

    private var primaryActionTitle: String {
        if loggedEntry == nil { return "Log Mood" }
        return isEditingLoggedMood ? "Save Update" : "Update Mood"
    }

    private var primaryActionHint: String {
        if loggedEntry == nil {
            return "Saves today's mood and wellness signals"
        }
        if isEditingLoggedMood {
            return "Saves the changes and returns to the streak summary"
        }
        return "Shows the wellness sliders to edit today's mood"
    }

    private func handlePrimaryAction() {
        if loggedEntry != nil, !isEditingLoggedMood {
            withAnimation(editorAnimation) {
                isEditingLoggedMood = true
            }
            return
        }

        let didSave = onLog()
        withAnimation(editorAnimation) {
            isEditingLoggedMood = !didSave
        }
    }

    private var editorAnimation: Animation {
        reduceMotion
            ? .linear(duration: 0.01)
            : .spring(response: 0.38, dampingFraction: 0.84)
    }

    private var moodHeader: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("How are you feeling?")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Select and log your mood")
                    .pulsarTextStyle(.caption)
                    .foregroundStyle(MindfulnessVisualStyle.secondaryText)
            }

            Spacer(minLength: 4)

            if loggedEntry == nil {
                MindfulnessStreakStatusCapsule(dayCount: max(0, loggedStreakDays))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
        }
    }
}

private struct MindfulnessMoodButton: View {
    var mood: MindfulnessMoodLevel
    var isSelected: Bool
    var isLogged: Bool
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                MindfulnessMoodOrb(
                    mood: mood,
                    state: orbState,
                    size: 52,
                    isInteractive: true
                )
                .scaleEffect((isSelected || isLogged) && !reduceMotion ? 1.06 : 1)

                Text(mood.title)
                    .pulsarTextStyle(.caption)
                    .foregroundStyle(isSelected || isLogged ? .white : MindfulnessVisualStyle.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

            }
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mood.title)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var orbState: MindfulnessMoodOrbState {
        if isLogged { return .logged }
        return isSelected ? .selected : .muted
    }

    private var accessibilityValue: String {
        if isLogged {
            return isSelected
                ? "Logged today, selected"
                : "Logged today"
        }
        return isSelected ? "Selected, not logged" : "Not selected"
    }
}

private enum MindfulnessMoodOrbState: Equatable {
    case muted
    case logged
    case selected
}

private struct MindfulnessMoodOrb: View {
    var mood: MindfulnessMoodLevel
    var state: MindfulnessMoodOrbState
    var size: CGFloat
    var isInteractive: Bool = false
    var usesNeutralTint = false

    private var tintColor: Color {
        usesNeutralTint
            ? Color(red: 0.48, green: 0.56, blue: 0.65)
            : mood.tint
    }

    private var colorStrength: Double {
        switch state {
        case .muted: 0.035
        case .logged: 0.14
        case .selected: 0.18
        }
    }

    private var rimStrength: Double {
        switch state {
        case .muted: 0.32
        case .logged: 0.88
        case .selected: 1.0
        }
    }

    private var faceStrength: Double {
        switch state {
        case .muted: 0.66
        case .logged: 0.96
        case .selected: 1.0
        }
    }

    private var glowStrength: Double {
        switch state {
        case .muted: 0.08
        case .logged: 0.58
        case .selected: 0.72
        }
    }

    private var rimWidth: CGFloat {
        switch state {
        case .muted: 0.9
        case .logged: 1.7
        case .selected: 1.9
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(state == .muted ? 0.045 : 0.10),
                            tintColor.opacity(colorStrength),
                            tintColor.opacity(0.015)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.18), .clear],
                        center: UnitPoint(x: 0.30, y: 0.24),
                        startRadius: 0,
                        endRadius: size * 0.58
                    )
                )
                .opacity(state == .muted ? 0.45 : 0.85)

            MindfulnessMoodFace(mood: mood)
                .foregroundStyle(.white.opacity(faceStrength))
                .frame(width: size * 0.58, height: size * 0.58)

            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(state == .muted ? 0.16 : 0.44),
                            tintColor.opacity(rimStrength),
                            tintColor.opacity(state == .muted ? 0.16 : 0.44)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: rimWidth
                )

            Circle()
                .inset(by: 2)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.15), .clear, .black.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.7
                )
        }
        .frame(width: size, height: size)
        .shadow(color: tintColor.opacity(glowStrength), radius: state == .muted ? 4 : 13)
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        .pulsarLiquidGlass(
            cornerRadius: size / 2,
            tint: tintColor.opacity(state == .muted ? 0.035 : 0.16),
            interactive: isInteractive,
            isClear: true
        )
        .accessibilityHidden(true)
    }
}

private struct MindfulnessMoodFace: View {
    var mood: MindfulnessMoodLevel

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let lineWidth = max(1.25, size * 0.06)

            ZStack {
                HStack(spacing: size * 0.20) {
                    Circle()
                        .frame(width: size * 0.08, height: size * 0.08)
                    Circle()
                        .frame(width: size * 0.08, height: size * 0.08)
                }
                .offset(y: -size * 0.12)

                Path { path in
                    path.move(to: CGPoint(x: size * 0.28, y: size * 0.60))
                    path.addQuadCurve(
                        to: CGPoint(x: size * 0.72, y: size * 0.60),
                        control: CGPoint(x: size * 0.50, y: size * mood.mouthControlY)
                    )
                }
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
            .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }
}

private struct MindfulnessInlineSignalSlider: View {
    var metric: MindfulnessMetricKind
    @Binding var value: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isEditing = false
    @State private var lastFeedbackPoint = 0
    @State private var lastFeedbackDate = Date.distantPast
    @State private var feedbackEvent = MindfulnessSliderFeedbackEvent()

    private var displayedPoints: Int {
        min(max(Int((value * 100).rounded()), 0), 100)
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 7) {
                Image(systemName: metric.symbolName)
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(metric.tint)
                    .frame(width: 24, height: 24)
                    .background {
                        Circle()
                            .fill(metric.tint.opacity(0.10))
                            .overlay {
                                Circle()
                                    .fill(
                                        RadialGradient(
                                            colors: [.white.opacity(0.16), .clear],
                                            center: .topLeading,
                                            startRadius: 0,
                                            endRadius: 22
                                        )
                                    )
                            }
                    }
                    .accessibilityHidden(true)

                Text(metric.title)
                    .pulsarTextStyle(.caption)
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 4)

                Text("\(displayedPoints)")
                    .pulsarTextStyle(.caption)
                    .monospacedDigit()
                    .foregroundStyle(MindfulnessVisualStyle.secondaryText)
                    .contentTransition(.numericText(value: Double(displayedPoints)))
                    .animation(
                        reduceMotion ? .linear(duration: 0.01) : .snappy(duration: 0.14),
                        value: displayedPoints
                    )
            }
            .accessibilityHidden(true)

            Slider(
                value: $value,
                in: 0...1,
                step: 0.01,
                label: { Text(metric.title) },
                onEditingChanged: handleEditingChanged
            )
                .tint(metric.tint)
                .controlSize(.mini)
                .frame(height: 22)
                .brightness(isEditing ? 0.035 : 0)
                .accessibilityLabel(metric.title)
                .accessibilityValue("\(displayedPoints) percent")
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .onChange(of: displayedPoints, handlePointChange)
        .sensoryFeedback(trigger: feedbackEvent) { _, newValue in
            newValue.feedback
        }
    }

    private func handleEditingChanged(_ editing: Bool) {
        isEditing = editing
        lastFeedbackPoint = displayedPoints
        lastFeedbackDate = Date()
        emitFeedback(editing ? .start : .release)
    }

    private func handlePointChange(_ oldValue: Int, _ newValue: Int) {
        guard isEditing, oldValue != newValue else { return }

        let now = Date()
        if lastFeedbackPoint / 10 != newValue / 10 {
            lastFeedbackPoint = newValue
            lastFeedbackDate = now
            emitFeedback(.milestone)
            return
        }

        guard abs(newValue - lastFeedbackPoint) >= 3,
              now.timeIntervalSince(lastFeedbackDate) >= 0.075 else {
            return
        }

        lastFeedbackPoint = newValue
        lastFeedbackDate = now
        emitFeedback(.fine)
    }

    private func emitFeedback(_ kind: MindfulnessSliderFeedbackEvent.Kind) {
        feedbackEvent = MindfulnessSliderFeedbackEvent(
            sequence: feedbackEvent.sequence + 1,
            kind: kind
        )
    }
}

private struct MindfulnessSliderFeedbackEvent: Equatable {
    enum Kind: Equatable {
        case none
        case start
        case fine
        case milestone
        case release
    }

    var sequence = 0
    var kind: Kind = .none

    var feedback: SensoryFeedback? {
        switch kind {
        case .none: nil
        case .start: .selection
        case .fine: .impact(weight: .light, intensity: 0.18)
        case .milestone: .impact(weight: .medium, intensity: 0.45)
        case .release: .impact(flexibility: .soft, intensity: 0.35)
        }
    }
}

struct MindfulnessWeeklySummaryCard: View {
    var snapshot: PulsarMindfulnessWeekSnapshot
    var onViewMore: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        PulsarMindfulnessGlassCard(
            cornerRadius: 26,
            contentPadding: 12,
            tint: MindfulnessVisualStyle.calmBlue.opacity(0.12)
        ) {
            VStack(alignment: .leading, spacing: 6) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        summaryTitle
                        Spacer(minLength: 8)
                        viewMoreButton
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        summaryTitle
                        viewMoreButton
                    }
                }

                if dynamicTypeSize.isAccessibilitySize {
                    ScrollView(.horizontal) {
                        weekRow(fixedCellWidth: 52)
                    }
                    .contentMargins(.horizontal, 1, for: .scrollContent)
                    .scrollIndicators(.hidden)
                } else {
                    weekRow(fixedCellWidth: nil)
                }
            }
        }
    }

    private var summaryTitle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Mood at a glance")
                .font(.headline)
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)

            Text("This week")
                .pulsarTextStyle(.caption)
                .foregroundStyle(MindfulnessVisualStyle.secondaryText)
        }
    }

    private var viewMoreButton: some View {
        Button(action: onViewMore) {
            Label("View more", systemImage: "calendar")
                .pulsarTextStyle(.captionEmphasis)
                .frame(minHeight: 24)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .tint(MindfulnessVisualStyle.calmBlue.opacity(0.14))
        .foregroundStyle(.white)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityHint("Opens the full monthly mood calendar")
    }

    private func weekRow(fixedCellWidth: CGFloat?) -> some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            MindfulnessVisualStyle.calmBlue.opacity(0.18),
                            .white.opacity(0.18),
                            MindfulnessVisualStyle.mint.opacity(0.18)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1.25)
                .padding(.horizontal, 20)
                .offset(y: 32)

            PulsarGlassEffectGroup(spacing: 4) {
                HStack(spacing: fixedCellWidth == nil ? 0 : 8) {
                    ForEach(snapshot.days) { day in
                        Group {
                            if let fixedCellWidth {
                                MindfulnessWeeklyDayView(day: day)
                                    .frame(width: fixedCellWidth)
                            } else {
                                MindfulnessWeeklyDayView(day: day)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
        }
        .frame(minHeight: 50)
    }
}

private struct MindfulnessWeeklyDayView: View {
    var day: PulsarMindfulnessWeekSnapshot.Day

    @Environment(\.calendar) private var calendar

    private var mood: MindfulnessMoodLevel? {
        day.entry.map { MindfulnessMoodLevel.nearest(to: $0.valence) }
    }

    private var isToday: Bool {
        calendar.isDateInToday(day.date)
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(day.date, format: .dateTime.weekday(.abbreviated))
                .pulsarTextStyle(.overline)
                .foregroundStyle(weekdayColor)

            MindfulnessMoodOrb(
                mood: mood ?? .neutral,
                state: orbState,
                size: 32,
                usesNeutralTint: day.entry == nil
            )
            .scaleEffect(isToday ? 1.06 : 1)
            .shadow(
                color: isToday ? MindfulnessVisualStyle.calmBlue.opacity(0.22) : .clear,
                radius: 7,
                y: isToday ? -1 : 0
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityValue(mood.map(\.title) ?? "No mood logged")
    }

    private var orbState: MindfulnessMoodOrbState {
        guard day.entry != nil else { return .muted }
        return isToday ? .selected : .logged
    }

    private var weekdayColor: Color {
        if let mood {
            return mood.tint.opacity(isToday ? 1 : 0.88)
        }
        return isToday ? MindfulnessVisualStyle.calmBlue.opacity(0.90) : MindfulnessVisualStyle.tertiaryText
    }
}

struct MindfulnessCompactInsightsCard: View {
    var average: Double?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))

        PulsarMindfulnessGlassCard(
            cornerRadius: 24,
            contentPadding: 10,
            tint: MindfulnessVisualStyle.calmBlue.opacity(0.10)
        ) {
            layout {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Insights", systemImage: "sparkles")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader)

                    Text(insightText)
                        .pulsarTextStyle(.caption)
                        .foregroundStyle(MindfulnessVisualStyle.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                MindfulnessWeeklyAverageRing(average: average)
                    .frame(
                        maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil,
                        alignment: .trailing
                    )
            }
        }
    }

    private var insightText: String {
        guard let average else {
            return "Log a few days to reveal your weekly pattern."
        }

        return switch average {
        case 0.72...: "You've been balanced most of this week."
        case 0.56..<0.72: "Your week is holding a steady rhythm."
        case 0.40..<0.56: "Your week has had a mix of lighter and heavier days."
        default: "Your signals suggest making room for gentle recovery."
        }
    }
}

struct MindfulnessGuidedMeditationSection: View {
    var snapshot: PulsarMindfulnessMeditationWeekSnapshot
    var templates: [PulsarMeditationTemplate]
    var onStart: (PulsarMeditationTemplate) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PulsarMindfulnessGlassCard(
                cornerRadius: 24,
                contentPadding: 12,
                tint: MindfulnessVisualStyle.mint.opacity(0.10)
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            sectionTitle
                            Spacer(minLength: 8)
                            weekCount
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            sectionTitle
                            weekCount
                        }
                    }

                    meditationWeekRow
                }
            }

            PulsarGlassEffectGroup(spacing: 12) {
                LazyVGrid(columns: templateColumns, alignment: .leading, spacing: 12) {
                    ForEach(templates) { template in
                        MindfulnessTemplateCard(template: template) {
                            onStart(template)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var templateColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(minimum: 220), spacing: 12, alignment: .top)]
        }
        return [
            GridItem(.flexible(minimum: 140), spacing: 12, alignment: .top),
            GridItem(.flexible(minimum: 140), spacing: 12, alignment: .top)
        ]
    }

    private var sectionTitle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label("Meditation exercises", systemImage: "figure.mind.and.body")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)

            Text("Guided sessions")
                .pulsarTextStyle(.caption)
                .foregroundStyle(MindfulnessVisualStyle.secondaryText)
        }
    }

    private var weekCount: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text("\(snapshot.meditatedDayCount)/7")
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(MindfulnessVisualStyle.mint)
                .contentTransition(.numericText(value: Double(snapshot.meditatedDayCount)))

            Text("days this week")
                .pulsarTextStyle(.overline)
                .foregroundStyle(MindfulnessVisualStyle.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Meditated \(snapshot.meditatedDayCount) out of 7 days this week")
    }

    private var meditationWeekRow: some View {
        HStack(spacing: 6) {
            ForEach(snapshot.days) { day in
                MindfulnessMeditationWeekDayDot(day: day)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct MindfulnessMeditationWeekDayDot: View {
    var day: PulsarMindfulnessMeditationWeekSnapshot.Day

    @Environment(\.calendar) private var calendar

    private var isToday: Bool {
        calendar.isDateInToday(day.date)
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(day.date, format: .dateTime.weekday(.abbreviated))
                .pulsarTextStyle(.overline)
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            ZStack {
                Circle()
                    .fill(dotFill)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(day.hasSession ? 0.28 : 0.10), lineWidth: 0.8)
                    }

                Image(systemName: day.hasSession ? "checkmark" : "minus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(day.hasSession ? .white : MindfulnessVisualStyle.tertiaryText)
            }
            .shadow(color: day.hasSession ? MindfulnessVisualStyle.mint.opacity(0.22) : .clear, radius: 7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityValue(accessibilityValue)
    }

    private var labelColor: Color {
        if day.hasSession { return MindfulnessVisualStyle.mint.opacity(isToday ? 1 : 0.88) }
        return isToday ? .white.opacity(0.82) : MindfulnessVisualStyle.tertiaryText
    }

    private var dotFill: LinearGradient {
        LinearGradient(
            colors: day.hasSession
                ? [MindfulnessVisualStyle.mint.opacity(0.88), MindfulnessVisualStyle.softGold.opacity(0.54)]
                : [.white.opacity(0.09), .black.opacity(0.16)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var accessibilityValue: String {
        guard day.hasSession else { return "No meditation logged" }
        return "\(Int(day.mindfulMinutes.rounded())) mindful minutes"
    }
}

private struct MindfulnessWeeklyAverageRing: View {
    var average: Double?

    @ScaledMetric(relativeTo: .body) private var ringSize: CGFloat = 52

    private var progress: Double {
        min(max(average ?? 0, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            MindfulnessVisualStyle.moodColor(for: average).opacity(0.08),
                            .clear
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 48
                    )
                )

            Circle()
                .stroke(.white.opacity(0.14), lineWidth: 3)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    MindfulnessVisualStyle.moodColor(for: average),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: MindfulnessVisualStyle.moodColor(for: average).opacity(0.40), radius: 4)

            VStack(spacing: 0) {
                Text(scoreText)
                    .font(.headline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(MindfulnessVisualStyle.moodColor(for: average))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                Text("Average")
                    .pulsarTextStyle(.overline)
                    .foregroundStyle(MindfulnessVisualStyle.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .frame(width: min(ringSize, 72), height: min(ringSize, 72))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weekly average")
        .accessibilityValue(average.map { "\(String(format: "%.1f", $0 * 5)) out of 5" } ?? "No data")
    }

    private var scoreText: String {
        average.map { String(format: "%.1f", $0 * 5) } ?? "--"
    }
}

struct MindfulnessHistorySheet: View {
    var entries: [PulsarDailyJournalEntry]
    @Binding var displayedMonth: Date
    @Binding var selectedDate: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { proxy in
            let sideInset: CGFloat = proxy.size.width < 390 ? 16 : 22

            ZStack {
                MindfulnessScenicBackground()
                    .scaleEffect(1.02)

                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(reduceTransparency ? 0 : 0.12)
                    .ignoresSafeArea()

                Color.black
                    .opacity(reduceTransparency ? 0.42 : 0.16)
                    .ignoresSafeArea()

                ScrollView {
                    MindfulnessMoodHistoryCard(
                        entries: entries,
                        displayedMonth: $displayedMonth,
                        selectedDate: $selectedDate
                    )
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, sideInset)
                    .padding(.vertical, 20)
                }
                .scrollContentBackground(.hidden)
                .defaultScrollAnchor(.top)
                .defaultScrollAnchor(.center, for: .alignment)
                .scrollBounceBehavior(.basedOnSize)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Spacer()

                    Button("Close", systemImage: "xmark", action: dismiss.callAsFunction)
                        .labelStyle(.iconOnly)
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .tint(MindfulnessVisualStyle.calmBlue.opacity(0.22))
                        .foregroundStyle(.white)
                        .shadow(color: MindfulnessVisualStyle.calmBlue.opacity(0.28), radius: 9)
                        .accessibilityHint("Closes mood history")
                }
                .padding(.horizontal, sideInset)
                .padding(.vertical, 6)
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct MindfulnessMoodHistoryCard: View {
    var entries: [PulsarDailyJournalEntry]
    @Binding var displayedMonth: Date
    @Binding var selectedDate: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        PulsarMindfulnessGlassCard(
            cornerRadius: 32,
            contentPadding: 16,
            tint: MindfulnessVisualStyle.calmBlue.opacity(0.16)
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        historyTitle
                        Spacer(minLength: 8)
                        historyControls
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        historyTitle
                        historyControls
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }

                calendarGrid

                Rectangle()
                    .fill(.white.opacity(0.12))
                    .frame(height: 0.75)

                monthlyInsight
            }
        }
    }

    private var historyTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Mood History")
                .font(.headline)
                .foregroundStyle(.white)
            Text(monthStart, format: .dateTime.month(.wide).year())
                .pulsarTextStyle(.caption)
                .foregroundStyle(MindfulnessVisualStyle.secondaryText)
        }
    }

    private var historyControls: some View {
        PulsarGlassEffectGroup(spacing: 6) {
            HStack(spacing: 6) {
                Button("Previous month", systemImage: "chevron.left") {
                    moveMonth(by: -1)
                }
                .labelStyle(.iconOnly)
                .frame(width: 30, height: 30)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())

                Button("Next month", systemImage: "chevron.right") {
                    moveMonth(by: 1)
                }
                .labelStyle(.iconOnly)
                .frame(width: 30, height: 30)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())

                Button("Today") {
                    selectToday()
                }
                .pulsarTextStyle(.captionEmphasis)
                .frame(minHeight: 36)
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityHint("Shows the current month and selects today")
            }
            .tint(MindfulnessVisualStyle.calmBlue.opacity(0.12))
            .foregroundStyle(.white)
        }
    }

    private var calendarGrid: some View {
        LazyVGrid(columns: calendarColumns, spacing: 2) {
            ForEach(weekdaySymbols.indices, id: \.self) { index in
                Text(weekdaySymbols[index].short)
                    .pulsarTextStyle(.overline)
                    .foregroundStyle(MindfulnessVisualStyle.tertiaryText)
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .accessibilityLabel(weekdaySymbols[index].full)
            }

            ForEach(calendarDays) { day in
                let entry = entriesByDay[calendar.startOfDay(for: day.date)]
                MindfulnessCalendarDayButton(
                    date: day.date,
                    isInDisplayedMonth: day.isInDisplayedMonth,
                    isSelected: calendar.isDate(day.date, inSameDayAs: selectedDate),
                    entry: entry
                ) {
                    select(day)
                }
            }
        }
    }

    private var monthlyInsight: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 10))

        return layout {
            VStack(alignment: .leading, spacing: 5) {
                Label("Monthly Insight", systemImage: "sparkles")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)

                Text(monthlyInsightText)
                    .pulsarTextStyle(.caption)
                    .foregroundStyle(MindfulnessVisualStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            MindfulnessAverageRing(average: monthlyAverage)
                .frame(
                    maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil,
                    alignment: .trailing
                )
        }
        .padding(.vertical, 2)
    }

    private var calendarColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 36), spacing: 0), count: 7)
    }

    private var weekdaySymbols: [(short: String, full: String)] {
        [
            ("M", "Monday"),
            ("T", "Tuesday"),
            ("W", "Wednesday"),
            ("T", "Thursday"),
            ("F", "Friday"),
            ("S", "Saturday"),
            ("S", "Sunday")
        ]
    }

    private var monthStart: Date {
        calendar.dateInterval(of: .month, for: displayedMonth)?.start ?? displayedMonth
    }

    private var calendarDays: [MindfulnessCalendarDay] {
        let weekday = calendar.component(.weekday, from: monthStart)
        let daysBeforeMonday = (weekday + 5) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -daysBeforeMonday, to: monthStart) else {
            return []
        }

        let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 31
        let requiredCells = daysBeforeMonday + daysInMonth
        let cellCount = requiredCells <= 35 ? 35 : 42

        return (0..<cellCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else { return nil }
            return MindfulnessCalendarDay(
                date: date,
                isInDisplayedMonth: calendar.isDate(date, equalTo: monthStart, toGranularity: .month)
            )
        }
    }

    private var entriesByDay: [Date: PulsarDailyJournalEntry] {
        entries.reduce(into: [:]) { result, entry in
            let day = calendar.startOfDay(for: entry.date)
            if result[day] == nil {
                result[day] = entry
            }
        }
    }

    private var monthlyEntries: [PulsarDailyJournalEntry] {
        entries.filter { calendar.isDate($0.date, equalTo: monthStart, toGranularity: .month) }
    }

    private var monthlyAverage: Double? {
        guard !monthlyEntries.isEmpty else { return nil }
        return monthlyEntries.reduce(0) { $0 + $1.wellnessAverage } / Double(monthlyEntries.count)
    }

    private var monthlyInsightText: String {
        guard let monthlyAverage else {
            return "Log a few days this month to reveal a steadier pattern."
        }

        switch monthlyAverage {
        case 0.72...:
            return "Your days were mostly calm, connected, and balanced this month."
        case 0.56..<0.72:
            return "Your month held a steady balance with a few softer days."
        case 0.40..<0.56:
            return "Your signals were mixed this month. Small resets may help create more ease."
        default:
            return "This month carried more strain. Gentle recovery and connection may help."
        }
    }

    private func moveMonth(by value: Int) {
        guard let nextMonth = calendar.date(byAdding: .month, value: value, to: monthStart) else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.24)) {
            displayedMonth = nextMonth
        }
    }

    private func selectToday() {
        let today = Date()
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.24)) {
            selectedDate = today
            displayedMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today
        }
    }

    private func select(_ day: MindfulnessCalendarDay) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.20)) {
            selectedDate = day.date
            if !day.isInDisplayedMonth {
                displayedMonth = calendar.dateInterval(of: .month, for: day.date)?.start ?? day.date
            }
        }
    }
}

private struct MindfulnessCalendarDay: Identifiable {
    var date: Date
    var isInDisplayedMonth: Bool

    var id: Date { date }
}

private struct MindfulnessCalendarDayButton: View {
    var date: Date
    var isInDisplayedMonth: Bool
    var isSelected: Bool
    var entry: PulsarDailyJournalEntry?
    var action: () -> Void

    @ScaledMetric(relativeTo: .callout) private var dayCircleSize: CGFloat = 30

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(
                            isSelected
                                ? RadialGradient(
                                    colors: [selectionTint.opacity(0.32), selectionTint.opacity(0.12)],
                                    center: .topLeading,
                                    startRadius: 0,
                                    endRadius: 34
                                )
                                : RadialGradient(
                                    colors: [.clear, .clear],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 1
                                )
                        )

                    if isSelected {
                        Circle()
                            .strokeBorder(selectionTint.opacity(0.78), lineWidth: 1.2)
                            .shadow(color: selectionTint.opacity(0.52), radius: 7)
                    }

                    Text(date, format: .dateTime.day())
                        .font(.callout.weight(isSelected ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(dayTextColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.66)
                }
                .frame(width: min(dayCircleSize, 42), height: min(dayCircleSize, 42))

                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: dotColor.opacity(entry == nil ? 0 : 0.58), radius: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var dayTextColor: Color {
        guard isInDisplayedMonth else { return .white.opacity(0.30) }
        return isSelected ? .white : .white.opacity(0.84)
    }

    private var dotColor: Color {
        guard isInDisplayedMonth else { return .clear }
        guard let entry else { return .white.opacity(0.22) }
        return MindfulnessMoodLevel.nearest(to: entry.valence).tint
    }

    private var selectionTint: Color {
        guard let entry else { return MindfulnessVisualStyle.calmBlue }
        return MindfulnessMoodLevel.nearest(to: entry.valence).tint
    }

    private var accessibilityValue: String {
        guard let entry else { return "No mood logged" }
        return "Wellness average \(String(format: "%.1f", entry.wellnessAverage * 5)) out of 5"
    }
}

private struct MindfulnessAverageRing: View {
    var average: Double?

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            MindfulnessVisualStyle.moodColor(for: average).opacity(0.09),
                            .clear
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 64
                    )
                )

            Circle()
                .stroke(.white.opacity(0.14), lineWidth: 3)

            Circle()
                .trim(from: 0, to: average ?? 0)
                .stroke(
                    MindfulnessVisualStyle.moodColor(for: average),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: MindfulnessVisualStyle.moodColor(for: average).opacity(0.38), radius: 4)

            VStack(spacing: 0) {
                Text(scoreText)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(MindfulnessVisualStyle.moodColor(for: average))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                Text("Average")
                    .pulsarTextStyle(.overline)
                    .foregroundStyle(MindfulnessVisualStyle.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .frame(width: 72, height: 72)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Monthly average")
        .accessibilityValue(average.map { "\(String(format: "%.1f", $0 * 5)) out of 5" } ?? "No data")
    }

    private var scoreText: String {
        average.map { String(format: "%.1f", $0 * 5) } ?? "--"
    }
}

struct MindfulnessTodayCard: View {
    var dashboard: PulsarMindfulnessDashboard
    var onCheckIn: () -> Void
    var onStartBreathing: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        PulsarMindfulnessGlassCard(cornerRadius: 30) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    MindfulnessBalanceHalo(entry: dashboard.todayEntry)
                        .frame(width: 78, height: 78)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Emotional Balance")
                            .pulsarTextStyle(.sectionTitle)
                        Text(balanceCopy)
                            .pulsarTextStyle(.screenSubtitle)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 4)
                }

                HStack(spacing: 10) {
                    Button(action: onCheckIn) {
                        Label(dashboard.todayEntry == nil ? "Check in" : "Update", systemImage: "slider.horizontal.3")
                            .pulsarTextStyle(.buttonTitle)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(PulsarMindfulnessActionButtonStyle(tint: balanceTint))

                    Button(action: onStartBreathing) {
                        Image(systemName: "lungs.fill")
                            .pulsarTextStyle(.cardTitle)
                            .frame(width: 52, height: 52)
                    }
                    .buttonStyle(PulsarMindfulnessIconButtonStyle(tint: .blue))
                    .accessibilityLabel("Start breathing")
                }

                HStack(spacing: 10) {
                    MindfulnessMetricPill(
                        title: "Streak",
                        value: dashboard.streak.currentStreak == 1 ? "1 day" : "\(dashboard.streak.currentStreak) days",
                        symbolName: "flame.fill",
                        tint: .orange
                    )
                    MindfulnessMetricPill(
                        title: "This week",
                        value: "\(Int(dashboard.weeklyMindfulMinutes.rounded())) min",
                        symbolName: "timer",
                        tint: .teal
                    )
                }
            }
        }
    }

    private var balanceCopy: String {
        guard let entry = dashboard.todayEntry else {
            return "A low-friction reflection is ready when your day has enough shape."
        }

        let mood = entry.moodTitle.lowercased()
        if entry.stress > 0.62 {
            return "Today feels \(mood), with stress asking for a little extra space."
        }
        if entry.gratitude > 0.68 {
            return "Today feels \(mood), with gratitude clearly present."
        }
        return "Today feels \(mood). Pulsar will keep the signal simple until patterns emerge."
    }

    private var balanceTint: Color {
        guard let entry = dashboard.todayEntry else { return .blue }
        if entry.valence >= 0.25 { return .green }
        if entry.stress > 0.62 { return .orange }
        return .blue
    }
}

struct MindfulnessBalanceHalo: View {
    var entry: PulsarDailyJournalEntry?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    var body: some View {
        ZStack {
            Circle()
                .fill(haloFill)
                .blur(radius: 8)
                .scaleEffect(phase && !reduceMotion ? 1.08 : 0.96)

            Circle()
                .stroke(haloStroke, lineWidth: 1.4)
                .padding(5)

            Image(systemName: entry == nil ? "sparkles" : "heart.text.square.fill")
                .font(.system(size: 24, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconTint)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                phase = true
            }
        }
    }

    private var iconTint: Color {
        guard let entry else { return .blue }
        return entry.valence >= 0 ? .green : .orange
    }

    private var haloFill: RadialGradient {
        RadialGradient(
            colors: [
                iconTint.opacity(0.34),
                iconTint.opacity(0.14),
                Color.white.opacity(0.03)
            ],
            center: .center,
            startRadius: 5,
            endRadius: 42
        )
    }

    private var haloStroke: LinearGradient {
        LinearGradient(
            colors: [.white.opacity(0.66), iconTint.opacity(0.42), .white.opacity(0.08)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct MindfulnessMetricPill: View {
    var title: String
    var value: String
    var symbolName: String
    var tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbolName)
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.13), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .pulsarTextStyle(.appBodyEmphasis)
                Text(title)
                    .pulsarTextStyle(.metricLabel)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }
}

struct MindfulnessTrendCard: View {
    var points: [PulsarMindfulnessTrendPoint]

    var body: some View {
        PulsarMindfulnessGlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mood constellation")
                            .pulsarTextStyle(.cardTitle)
                        Text("Seven-day signal")
                            .pulsarTextStyle(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chart.xyaxis.line")
                        .pulsarTextStyle(.cardTitle)
                        .foregroundStyle(.blue)
                }

                MoodConstellationChart(points: points)
                    .frame(height: 120)

                ConsistencyStrip(points: points)
            }
        }
    }
}

struct MoodConstellationChart: View {
    var points: [PulsarMindfulnessTrendPoint]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.07))

                Path { path in
                    let midY = proxy.size.height / 2
                    path.move(to: CGPoint(x: 12, y: midY))
                    path.addLine(to: CGPoint(x: max(12, proxy.size.width - 12), y: midY))
                }
                .stroke(.secondary.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))

                ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                    let position = position(for: point, index: index, size: proxy.size)
                    Circle()
                        .fill(color(for: point))
                        .frame(width: point.hasCheckIn ? 12 : 7, height: point.hasCheckIn ? 12 : 7)
                        .shadow(color: color(for: point).opacity(0.32), radius: 8)
                        .position(position)
                }
            }
        }
        .accessibilityLabel("Seven day mood constellation")
    }

    private func position(for point: PulsarMindfulnessTrendPoint, index: Int, size: CGSize) -> CGPoint {
        let count = max(points.count - 1, 1)
        let x = 18 + (size.width - 36) * CGFloat(index) / CGFloat(count)
        let normalized = CGFloat((point.valence ?? 0) + 1) / 2
        let y = 18 + (size.height - 36) * (1 - normalized)
        return CGPoint(x: x, y: y)
    }

    private func color(for point: PulsarMindfulnessTrendPoint) -> Color {
        guard let valence = point.valence else {
            return .secondary.opacity(0.36)
        }
        if valence > 0.22 { return .green }
        if valence < -0.22 { return .orange }
        return .blue
    }
}

struct ConsistencyStrip: View {
    var points: [PulsarMindfulnessTrendPoint]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(points) { point in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fill(for: point))
                    .frame(height: 8)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(.white.opacity(point.hasCheckIn ? 0.14 : 0.06), lineWidth: 1)
                    }
                    .accessibilityLabel(point.hasCheckIn ? "Check-in logged" : "No check-in")
            }
        }
    }

    private func fill(for point: PulsarMindfulnessTrendPoint) -> Color {
        if point.hasCheckIn && point.mindfulMinutes > 0 { return .green.opacity(0.72) }
        if point.hasCheckIn { return .blue.opacity(0.62) }
        if point.mindfulMinutes > 0 { return .teal.opacity(0.52) }
        return .secondary.opacity(0.18)
    }
}

struct MindfulnessTemplateCard: View {
    var template: PulsarMeditationTemplate
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Image(systemName: template.category.symbolName)
                        .font(.system(size: 18, weight: .bold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(template.category.accent)
                        .frame(width: 40, height: 40)
                        .background {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            template.category.accent.opacity(0.22),
                                            Color.black.opacity(0.18)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(.white.opacity(0.12), lineWidth: 0.8)
                        }
                    Spacer(minLength: 0)
                    Text(template.durationText)
                        .pulsarTextStyle(.metricLabel)
                        .foregroundStyle(template.category.accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background {
                            Capsule()
                                .fill(template.category.accent.opacity(0.13))
                                .overlay {
                                    Capsule()
                                        .strokeBorder(.white.opacity(0.10), lineWidth: 0.7)
                                }
                        }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(template.title)
                        .pulsarTextStyle(.appBodyEmphasis)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                    Text(template.category.title)
                        .pulsarTextStyle(.metricLabel)
                        .foregroundStyle(MindfulnessVisualStyle.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(template.subtitle)
                        .pulsarTextStyle(.caption)
                        .foregroundStyle(MindfulnessVisualStyle.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 152, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.20),
                                Color(red: 0.04, green: 0.12, blue: 0.20).opacity(0.30)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.10),
                                        .clear,
                                        template.category.accent.opacity(0.045)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 0.85)
            }
            .shadow(color: .black.opacity(0.16), radius: 12, y: 6)
            .pulsarLiquidGlass(
                cornerRadius: 24,
                tint: MindfulnessVisualStyle.calmBlue.opacity(0.06),
                interactive: true,
                isClear: true
            )
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PulsarMindfulnessPressStyle(glowColor: template.category.accent))
        .accessibilityLabel("\(template.title), \(template.durationText)")
    }
}

struct PulsarMindfulnessInsightCard: View {
    var insight: PulsarEmotionalInsight

    var body: some View {
        PulsarMindfulnessGlassCard(cornerRadius: 24) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: insight.symbolName)
                    .pulsarTextStyle(.cardTitle)
                    .foregroundStyle(insight.tint.color)
                    .frame(width: 38, height: 38)
                    .background(insight.tint.color.opacity(0.13), in: Circle())

                VStack(alignment: .leading, spacing: 7) {
                    Text(insight.title)
                        .pulsarTextStyle(.cardTitle)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(insight.body)
                        .pulsarTextStyle(.screenSubtitle)
                        .foregroundStyle(MindfulnessVisualStyle.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(insight.evidence)
                        .pulsarTextStyle(.metricLabel)
                        .foregroundStyle(MindfulnessVisualStyle.tertiaryText)
                        .padding(.top, 2)
                }
            }
        }
    }
}

struct PulsarMindfulnessActionButtonStyle: ButtonStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [tint.opacity(0.95), tint.opacity(0.72)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule(style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .shadow(color: tint.opacity(configuration.isPressed ? 0.28 : 0.16), radius: 18, y: 8)
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

struct PulsarMindfulnessIconButtonStyle: ButtonStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tint)
            .background(tint.opacity(0.13), in: Circle())
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.76), value: configuration.isPressed)
    }
}

struct PulsarMindfulnessPressStyle: ButtonStyle {
    var glowColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? 0.035 : 0)
            .shadow(color: glowColor.opacity(configuration.isPressed ? 0.22 : 0), radius: 18, y: 8)
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

#Preview("Mood Logging Before") {
    @Previewable @State var draft = PulsarDailyJournalDraft()

    ZStack {
        MindfulnessScenicBackground()

        MindfulnessMoodLoggingCard(
            draft: $draft,
            loggedEntry: nil,
            loggedStreakDays: 2,
            onLog: { true }
        )
        .padding(22)
    }
    .frame(width: 393, height: 700)
    .preferredColorScheme(.dark)
}

#Preview("Mood Logging Logged") {
    @Previewable @State var entry = PulsarDailyJournalDraft().entry()
    @Previewable @State var draft = PulsarDailyJournalDraft()

    ZStack {
        MindfulnessScenicBackground()

        MindfulnessMoodLoggingCard(
            draft: $draft,
            loggedEntry: entry,
            loggedStreakDays: 2,
            isCelebratingStreak: true,
            onLog: { true }
        )
        .padding(22)
    }
    .frame(width: 393, height: 700)
    .preferredColorScheme(.dark)
}

#Preview("Mood History Sheet") {
    @Previewable @State var displayedMonth = Date()
    @Previewable @State var selectedDate = Date()

    MindfulnessHistorySheet(
        entries: [],
        displayedMonth: $displayedMonth,
        selectedDate: $selectedDate
    )
}
