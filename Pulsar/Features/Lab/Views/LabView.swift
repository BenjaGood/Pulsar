//
//  LabView.swift
//  Pulsar
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct LabView: View {
    @ObservedObject var profileStore: ProfileStore
    @StateObject private var store = LabModuleStore()
    @State private var isVisible = false
    @State private var isShowingImport = false
    @State private var isShowingManualEntry = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(profileStore: ProfileStore, startsVisible: Bool = false) {
        self.profileStore = profileStore
        _isVisible = State(initialValue: startsVisible)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LabHeaderView(result: store.state.latestBiologicalAgeResult)
                        .labStaggered(isVisible: isVisible, index: 0)

                    if let result = store.state.latestBiologicalAgeResult {
                        LabBiologicalAgeHeroView(result: result)
                            .labStaggered(isVisible: isVisible, index: 1)

                        LabHealthTrajectoryCard(result: result, trendResults: store.biologicalAgeTrendResults)
                            .labStaggered(isVisible: isVisible, index: 2)

                        LabSectionTitle(title: "Pillar Signals", subtitle: "A conservative estimate weighted by fitness, lifestyle, and recent blood markers.")
                            .labStaggered(isVisible: isVisible, index: 3)

                        VStack(spacing: 12) {
                            ForEach(result.pillarResults) { pillar in
                                LabPillarCard(pillar: pillar)
                            }
                        }
                        .labStaggered(isVisible: isVisible, index: 4)

                        DataConfidenceCard(result: result)
                            .labStaggered(isVisible: isVisible, index: 5)
                    } else {
                        LabEmptyStateCard(
                            hasBiomarkers: !store.state.biomarkers.isEmpty,
                            onConnectData: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                store.refresh(profile: profileStore.profile)
                            },
                            onImport: { isShowingImport = true },
                            onManualEntry: { isShowingManualEntry = true }
                        )
                        .labStaggered(isVisible: isVisible, index: 1)
                    }

                    BiomarkersSection(
                        biomarkers: store.displayedBiomarkers,
                        onImport: { isShowingImport = true },
                        onManualEntry: { isShowingManualEntry = true },
                        onDelete: { biomarker in
                            store.deleteBiomarker(biomarker, profile: profileStore.profile)
                        }
                    )
                    .labStaggered(isVisible: isVisible, index: 6)

                    LabDisclaimerCard()
                        .labStaggered(isVisible: isVisible, index: 7)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 36)
            }
            .pulsarBottomChromeScrollTracking()
            .background(LabModuleBackground())
            .premiumScrollHeaderBlur(height: 56)
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            store.refresh(profile: profileStore.profile)
            await MainActor.run {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                if reduceMotion {
                    isVisible = true
                } else {
                    withAnimation(.spring(response: 0.54, dampingFraction: 0.86)) {
                        isVisible = true
                    }
                }
            }
        }
        .onChange(of: profileStore.profile) { _, newProfile in
            store.refresh(profile: newProfile)
        }
        .sheet(isPresented: $isShowingImport) {
            ImportLabResultsView(
                store: store,
                profile: profileStore.profile,
                onEnterManually: {
                    isShowingImport = false
                    isShowingManualEntry = true
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingManualEntry) {
            ManualBiomarkerEntryView(store: store, profile: profileStore.profile)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct LabHeaderView: View {
    let result: BiologicalAgeResult?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            LabGenomeIconView(size: 54)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 9) {
                    Text("Lab")
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(LabPalette.primaryText(for: colorScheme))
                        .lineLimit(1)

                    if let result {
                        LabStatusPill(text: "Updated \(result.updatedAt.formatted(.dateTime.weekday(.wide)))", symbol: "clock")
                    } else {
                        LabStatusPill(text: "Latest available data")
                    }
                }

                Text("Biological age & biomarker insights")
                    .font(.subheadline)
                    .foregroundStyle(LabPalette.secondaryText(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct LabStatusPill: View {
    let text: String
    var symbol: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(LabPalette.accent(for: colorScheme))
            }

            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(LabPalette.secondaryText(for: colorScheme))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(LabPalette.controlBackground(for: colorScheme), in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(LabPalette.controlBorder(for: colorScheme), lineWidth: 1)
        }
    }
}

private struct LabBiologicalAgeHeroView: View {
    let result: BiologicalAgeResult
    var startsSettled = false
    @State private var animatedAge = 0.0
    @State private var cardVisible = false
    @State private var heroVisible = false
    @State private var readoutDetailsVisible = false
    @State private var scaleProgress = 0.0
    @State private var deltaBadgeVisible = false
    @State private var statChipsVisible = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            heroCopy

            AgeDifferenceScaleView(
                biologicalAge: result.biologicalAge,
                chronologicalAge: result.chronologicalAge,
                delta: result.ageDelta,
                confidence: result.confidence,
                tint: tint,
                animationProgress: scaleProgress,
                badgeVisible: deltaBadgeVisible
            )
            .frame(maxWidth: .infinity)
            .frame(height: 158)
            .opacity(heroVisible ? 1 : 0)
            .offset(y: heroVisible ? 0 : 8)
            .scaleEffect(heroVisible ? 1 : 0.985)
            .animation(reduceMotion ? nil : .spring(response: 0.62, dampingFraction: 0.86), value: heroVisible)

            HStack(spacing: 10) {
                statChips
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .labGlassCard(cornerRadius: 32, glow: tint.opacity(colorScheme == .dark ? 0.16 : 0.09))
        .opacity(cardVisible ? 1 : 0)
        .offset(y: cardVisible ? 0 : 10)
        .onAppear {
            runEntrySequence()
        }
        .onChange(of: result.biologicalAge) { _, newValue in
            if reduceMotion {
                animatedAge = newValue
                scaleProgress = 1
                deltaBadgeVisible = true
            } else {
                withAnimation(.easeInOut(duration: 0.86)) {
                    animatedAge = newValue
                }
                scaleProgress = 0
                deltaBadgeVisible = false
                withAnimation(.easeInOut(duration: 0.82).delay(0.14)) {
                    scaleProgress = 1
                }
                withAnimation(.spring(response: 0.40, dampingFraction: 0.88).delay(0.74)) {
                    deltaBadgeVisible = true
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var heroCopy: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 10) {
                Text("Preliminary Biological Age")
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption2.weight(.bold))
                    Text("Age estimate")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(tint)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(tint.opacity(colorScheme == .dark ? 0.09 : 0.07), in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(tint.opacity(colorScheme == .dark ? 0.18 : 0.14), lineWidth: 1)
                }
                .accessibilityHidden(true)
            }

            AnimatedBiologicalAgeReadoutView(
                displayedAge: animatedAge,
                chronologicalAge: result.chronologicalAge,
                delta: result.ageDelta,
                deltaText: deltaText,
                sourceCopy: sourceCopy,
                tint: tint,
                detailsVisible: readoutDetailsVisible
            )
        }
        .layoutPriority(1)
    }

    @ViewBuilder
    private var statChips: some View {
        animatedStatChip(index: 0, title: "Chronological", value: String(format: "%.0f", result.chronologicalAge), symbol: "calendar")
        animatedStatChip(index: 1, title: "Delta", value: signedYears(result.ageDelta), symbol: result.ageDelta <= 0 ? "arrow.down.right" : "arrow.up.right", tint: tint)
        animatedStatChip(index: 2, title: "Confidence", value: result.confidence.rawValue, symbol: "shield.lefthalf.filled")
    }

    private func animatedStatChip(index: Int, title: String, value: String, symbol: String, tint: Color? = nil) -> some View {
        AgeStatChipView(title: title, value: value, symbol: symbol, tint: tint)
            .opacity(statChipsVisible ? 1 : 0)
            .offset(y: statChipsVisible ? 0 : 8)
            .animation(
                reduceMotion ? nil : .spring(response: 0.46, dampingFraction: 0.88).delay(0.05 * Double(index)),
                value: statChipsVisible
            )
    }

    private var tint: Color {
        switch result.ageDelta {
        case ..<(-0.2): return LabPalette.positive(for: colorScheme)
        case (-0.2)...0.2: return LabPalette.accent(for: colorScheme)
        default: return LabPalette.warning(for: colorScheme)
        }
    }

    private var sourceCopy: String {
        switch result.confidence {
        case .low:
            return "Estimated from available data. Add blood biomarkers to improve accuracy."
        case .medium:
            return "Estimated from recent wearable, lifestyle, and available lab signals."
        case .high:
            return "Built from recent wearable data, lifestyle inputs, and complete blood markers."
        }
    }

    private var deltaText: String {
        if result.ageDelta < -0.05 {
            return deltaPhrase(value: abs(result.ageDelta), direction: "younger")
        }
        if result.ageDelta > 0.05 {
            return deltaPhrase(value: result.ageDelta, direction: "older")
        }
        return "Aligned with your chronological age"
    }

    private func deltaPhrase(value: Double, direction: String) -> String {
        let years = "\(value.formattedOneDecimal) years \(direction)"
        return "Preliminary estimate: \(years)"
    }

    private func signedYears(_ value: Double) -> String {
        String(format: "%+.1f yr", value)
    }

    private func runEntrySequence() {
        if startsSettled || reduceMotion {
            animatedAge = result.biologicalAge
            cardVisible = true
            readoutDetailsVisible = true
            heroVisible = true
            scaleProgress = 1
            deltaBadgeVisible = true
            statChipsVisible = true
            return
        }

        animatedAge = result.chronologicalAge
        cardVisible = false
        readoutDetailsVisible = false
        heroVisible = false
        scaleProgress = 0
        deltaBadgeVisible = false
        statChipsVisible = false

        withAnimation(.easeOut(duration: 0.30)) {
            cardVisible = true
        }
        withAnimation(.easeInOut(duration: 1.08).delay(0.14)) {
            animatedAge = result.biologicalAge
        }
        withAnimation(.easeOut(duration: 0.42).delay(0.32)) {
            readoutDetailsVisible = true
        }
        withAnimation(.spring(response: 0.56, dampingFraction: 0.90).delay(0.54)) {
            heroVisible = true
        }
        withAnimation(.easeInOut(duration: 0.86).delay(0.66)) {
            scaleProgress = 1
        }
        withAnimation(.spring(response: 0.40, dampingFraction: 0.88).delay(1.12)) {
            deltaBadgeVisible = true
        }
        withAnimation(.spring(response: 0.46, dampingFraction: 0.90).delay(1.24)) {
            statChipsVisible = true
        }
    }
}

private struct AnimatedBiologicalAgeReadoutView: View {
    let displayedAge: Double
    let chronologicalAge: Double
    let delta: Double
    let deltaText: String
    let sourceCopy: String
    let tint: Color
    let detailsVisible: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                readout(phase: 0)
            } else {
                TimelineView(.animation) { timeline in
                    readout(phase: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Biological Age \(displayedAge.formattedOneDecimal). \(deltaText). \(sourceCopy)")
    }

    private func readout(phase: TimeInterval) -> some View {
        let progress = movementProgress
        let breath = reduceMotion ? 1.0 : 0.96 + 0.04 * sin(phase * 0.95)
        let arrivalGlow = 0.70 + 0.30 * progress
        let scanPulse = reduceMotion ? 0.0 : sin(progress * .pi)
        let ageLift: CGFloat = reduceMotion ? 0 : CGFloat((1 - progress) * (delta < -0.05 ? -3 : delta > 0.05 ? 3 : -1))

        return VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let scanX = min(max(width * (0.18 + 0.52 * progress), 78), width - 36)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    tint.opacity(colorScheme == .dark ? 0.095 : 0.045),
                                    LabPalette.controlBackground(for: colorScheme),
                                    Color.white.opacity(colorScheme == .dark ? 0.025 : 0.52)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(colorScheme == .dark ? 0.16 : 0.84),
                                            tint.opacity(colorScheme == .dark ? 0.19 : 0.18),
                                            .black.opacity(colorScheme == .dark ? 0.10 : 0.04)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                        .shadow(color: tint.opacity((colorScheme == .dark ? 0.12 : 0.055) * breath * arrivalGlow), radius: colorScheme == .dark ? 14 : 8, x: 0, y: 5)

                    RadialGradient(
                        colors: [
                            tint.opacity((colorScheme == .dark ? 0.17 : 0.10) * breath * arrivalGlow),
                            tint.opacity(colorScheme == .dark ? 0.045 : 0.032),
                            .clear
                        ],
                        center: .leading,
                        startRadius: 4,
                        endRadius: width * 0.54
                    )
                    .blur(radius: 6)
                    .allowsHitTesting(false)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                ZStack(alignment: .leading) {
                                    BiologicalAgeValueText(value: displayedAge)
                                        .foregroundColor(LabPalette.primaryText(for: colorScheme))
                                }
                                .offset(y: ageLift)

                                Text("yrs")
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                    .foregroundStyle(LabPalette.tertiaryText(for: colorScheme))
                                    .baselineOffset(6)
                            }

                            Spacer(minLength: 6)

                            HStack(spacing: 5) {
                                Capsule(style: .continuous)
                                    .fill(tint)
                                    .frame(width: 10, height: 3)
                                    .shadow(color: tint.opacity(colorScheme == .dark ? 0.30 : 0.14), radius: 4)
                                Text("Preliminary")
                                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                    .textCase(.uppercase)
                                    .lineLimit(1)
                            }
                            .foregroundStyle(LabPalette.secondaryText(for: colorScheme))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(LabPalette.controlBackground(for: colorScheme).opacity(colorScheme == .dark ? 0.72 : 0.92), in: Capsule(style: .continuous))
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(tint.opacity(colorScheme == .dark ? 0.16 : 0.13), lineWidth: 1)
                            }
                            .opacity(detailsVisible ? 1 : 0)
                            .offset(y: detailsVisible ? 0 : 5)
                        }

                        BiologicalAgeSignalLineView(tint: tint, progress: progress, reduceMotion: reduceMotion)
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)

                    if scanPulse > 0 {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .clear,
                                        tint.opacity(colorScheme == .dark ? 0.58 : 0.38),
                                        .white.opacity(colorScheme == .dark ? 0.42 : 0.60),
                                        .clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 1, height: 34)
                            .blur(radius: 0.15)
                            .opacity(scanPulse * 0.50 * arrivalGlow)
                            .position(x: scanX, y: 35)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(height: 82)

            VStack(alignment: .leading, spacing: 6) {
                Text("Biological Age")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(LabPalette.primaryText(for: colorScheme))

                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: deltaSymbol)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                    Text(deltaText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(sourceCopy)
                    .font(.footnote)
                    .foregroundStyle(LabPalette.secondaryText(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(detailsVisible ? 1 : 0)
            .offset(y: detailsVisible ? 0 : 8)
            .animation(reduceMotion ? nil : .spring(response: 0.50, dampingFraction: 0.88), value: detailsVisible)
        }
    }

    private var deltaSymbol: String {
        if delta < -0.05 { return "arrow.down.right" }
        if delta > 0.05 { return "arrow.up.right" }
        return "equal"
    }

    private var movementProgress: Double {
        guard abs(delta) > 0.001 else { return 1 }
        let progress = abs((displayedAge - chronologicalAge) / delta)
        return min(max(progress, 0), 1)
    }
}

private struct BiologicalAgeValueText: View {
    var value: Double

    var body: some View {
        AnimatedDecimalText(value: value)
            .font(.system(size: 60, weight: .semibold, design: .rounded).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.55)
    }
}

private struct BiologicalAgeSignalLineView: View {
    let tint: Color
    let progress: Double
    let reduceMotion: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let sweepProgress = reduceMotion ? 1 : progress
            let activeWidth = width * CGFloat(0.34 + 0.20 * progress)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(LabPalette.secondaryText(for: colorScheme).opacity(colorScheme == .dark ? 0.075 : 0.065))

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(colorScheme == .dark ? 0.10 : 0.07),
                                tint.opacity(colorScheme == .dark ? 0.42 : 0.30),
                                tint.opacity(colorScheme == .dark ? 0.09 : 0.06)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: activeWidth)

                if !reduceMotion {
                    Capsule(style: .continuous)
                        .fill(.white.opacity(colorScheme == .dark ? 0.52 : 0.70))
                        .frame(width: 10)
                        .blur(radius: 1.8)
                        .opacity(sin(progress * .pi))
                        .offset(x: -16 + (width + 24) * sweepProgress)
                }

                Circle()
                    .fill(tint)
                    .frame(width: 4, height: 4)
                    .shadow(color: tint.opacity(colorScheme == .dark ? 0.26 : 0.13), radius: 3)
                    .offset(x: max(activeWidth - 2, 0))
            }
        }
        .frame(height: 2.5)
        .frame(maxWidth: 172)
        .accessibilityHidden(true)
    }
}

private struct AgeDifferenceScaleView: View {
    let biologicalAge: Double
    let chronologicalAge: Double
    let delta: Double
    let confidence: LabConfidenceLevel
    let tint: Color
    let animationProgress: Double
    let badgeVisible: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                scale(phase: 0)
            } else {
                TimelineView(.animation) { timeline in
                    scale(phase: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Age difference scale. Biological age \(biologicalAge.formattedOneDecimal). Chronological age \(String(format: "%.0f", chronologicalAge)). \(deltaAccessibilityText). Confidence \(confidence.rawValue).")
    }

    private func scale(phase: TimeInterval) -> some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let height = max(proxy.size.height, 1)
            let horizontalInset: CGFloat = 24
            let railY = height * 0.39
            let railWidth = max(width - horizontalInset * 2, 1)
            let centerX = width / 2
            let progress = max(0.0, min(1.0, animationProgress))
            let displayedDelta = delta * progress
            let rawOffset = CGFloat(max(-5.0, min(5.0, displayedDelta)) / 5.0) * (railWidth / 2)
            let bioX = min(max(centerX + rawOffset, horizontalInset), width - horizontalInset)
            let connectorX = min(centerX, bioX)
            let connectorWidth = max(abs(bioX - centerX), 1.5)
            let pulseProgress = reduceMotion ? 0.50 : progress
            let bioPulse = reduceMotion ? 1.0 : 1.0 + 0.025 * sin(phase * 1.8)
            let badgeX = min(max(bioX, horizontalInset + 62), width - horizontalInset - 62)

            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(colorScheme == .dark ? 0.10 : 0.055),
                                Color(red: 0.90, green: 0.97, blue: 1.00).opacity(colorScheme == .dark ? 0.045 : 0.58),
                                Color.white.opacity(colorScheme == .dark ? 0.035 : 0.82)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(colorScheme == .dark ? 0.18 : 0.86),
                                        tint.opacity(colorScheme == .dark ? 0.18 : 0.22),
                                        .black.opacity(colorScheme == .dark ? 0.08 : 0.045)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: tint.opacity(colorScheme == .dark ? 0.09 : 0.045), radius: 10, x: 0, y: 6)

                if !reduceMotion {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    .white.opacity(colorScheme == .dark ? 0.055 : 0.24),
                                    tint.opacity(colorScheme == .dark ? 0.10 : 0.12),
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: width * 0.24)
                        .blur(radius: 8)
                        .opacity(sin(progress * .pi))
                        .offset(x: -width * 0.58 + width * 1.16 * pulseProgress)
                        .allowsHitTesting(false)
                }

                scaleLabels
                    .frame(width: max(width - 20, 1))
                    .position(x: width / 2, y: 23)

                ageRail(railWidth: railWidth)
                    .position(x: centerX, y: railY)

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(colorScheme == .dark ? 0.14 : 0.10),
                                tint.opacity(colorScheme == .dark ? 0.42 : 0.34)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: connectorWidth, height: 2.5)
                    .opacity(abs(displayedDelta) < 0.02 ? 0 : 1)
                    .position(x: connectorX + connectorWidth / 2, y: railY)
                    .shadow(color: tint.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 4)

                scaleMarker(tint: LabPalette.secondaryText(for: colorScheme), size: 10, isPrimary: false)
                    .position(x: centerX, y: railY)

                scaleMarker(tint: tint, size: 14, isPrimary: true)
                    .scaleEffect(bioPulse)
                    .position(x: bioX, y: railY)

                Text(deltaBadgeText)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(LabPalette.controlBackground(for: colorScheme), in: Capsule(style: .continuous))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(tint.opacity(colorScheme == .dark ? 0.20 : 0.15), lineWidth: 1)
                    }
                    .opacity(badgeVisible ? 1 : 0)
                    .offset(y: badgeVisible ? 0 : 5)
                    .position(x: badgeX, y: railY + 28)
                    .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86), value: badgeVisible)

                HStack(spacing: 7) {
                    ScaleLegendChip(title: "Bio", value: biologicalAge.formattedOneDecimal, tint: tint, isPrimary: true)
                    ScaleLegendChip(title: "Age", value: String(format: "%.0f", chronologicalAge), tint: LabPalette.secondaryText(for: colorScheme), isPrimary: false)
                    ScaleLegendChip(title: "Confidence", value: confidence.rawValue, tint: LabPalette.accent(for: colorScheme), isPrimary: false)
                }
                .padding(.horizontal, 10)
                .frame(width: max(width - 18, 1))
                .position(x: centerX, y: height - 24)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }

    private var deltaBadgeText: String {
        if roundedDeltaMagnitude < 0.1 { return "Aligned" }
        if delta < 0 { return "\(roundedDeltaMagnitude.formattedOneDecimal) yr younger" }
        if delta > 0 { return "\(roundedDeltaMagnitude.formattedOneDecimal) yr older" }
        return "Aligned"
    }

    private var deltaAccessibilityText: String {
        if roundedDeltaMagnitude < 0.1 { return "Aligned with your chronological age." }
        if delta < 0 { return "\(roundedDeltaMagnitude.formattedOneDecimal) years younger." }
        if delta > 0 { return "\(roundedDeltaMagnitude.formattedOneDecimal) years older." }
        return "Aligned with your chronological age."
    }

    private var roundedDeltaMagnitude: Double {
        (abs(delta) * 10).rounded() / 10
    }

    private var scaleLabels: some View {
        HStack {
            Text("Younger")
            Spacer()
            Text("Aligned")
            Spacer()
            Text("Older")
        }
        .font(.caption2.weight(.semibold))
        .textCase(.uppercase)
        .foregroundStyle(LabPalette.secondaryText(for: colorScheme))
        .padding(.horizontal, 20)
    }

    private func ageRail(railWidth: CGFloat) -> some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            LabPalette.positive(for: colorScheme).opacity(colorScheme == .dark ? 0.14 : 0.12),
                            LabPalette.accent(for: colorScheme).opacity(colorScheme == .dark ? 0.17 : 0.13),
                            LabPalette.warning(for: colorScheme).opacity(colorScheme == .dark ? 0.13 : 0.10)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Capsule(style: .continuous)
                .stroke(.white.opacity(colorScheme == .dark ? 0.12 : 0.58), lineWidth: 1)

            Rectangle()
                .fill(LabPalette.secondaryText(for: colorScheme).opacity(colorScheme == .dark ? 0.18 : 0.14))
                .frame(width: 1, height: 24)
                .offset(y: -1)
        }
        .frame(width: railWidth, height: 8)
        .shadow(color: LabPalette.accent(for: colorScheme).opacity(colorScheme == .dark ? 0.08 : 0.045), radius: 7, x: 0, y: 4)
    }

    private func scaleMarker(tint: Color, size: CGFloat, isPrimary: Bool) -> some View {
        VStack(spacing: 2) {
            Capsule(style: .continuous)
                .fill(tint.opacity(isPrimary ? 0.40 : 0.18))
                .frame(width: isPrimary ? 1.5 : 1, height: isPrimary ? 22 : 16)
            ZStack {
                Circle()
                    .fill(tint.opacity(isPrimary ? (colorScheme == .dark ? 0.14 : 0.085) : 0.055))
                    .frame(width: size + 13, height: size + 13)
                    .blur(radius: isPrimary ? 1.0 : 0.3)
                Circle()
                    .fill(LabPalette.controlBackground(for: colorScheme))
                    .frame(width: size + 6, height: size + 6)
                    .overlay {
                        Circle()
                            .stroke(tint.opacity(isPrimary ? 0.54 : 0.28), lineWidth: isPrimary ? 1.3 : 1)
                    }
                Circle()
                    .fill(tint)
                    .frame(width: size, height: size)
                    .shadow(color: tint.opacity(isPrimary ? 0.26 : 0.10), radius: isPrimary ? 5 : 2)
            }
        }
        .offset(y: -9)
    }
}

private struct ScaleLegendChip: View {
    let title: String
    let value: String
    let tint: Color
    let isPrimary: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: isPrimary ? 7 : 5, height: isPrimary ? 7 : 5)
                .shadow(color: tint.opacity(isPrimary ? (colorScheme == .dark ? 0.24 : 0.10) : 0), radius: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LabPalette.secondaryText(for: colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.66)
                Text(value)
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(isPrimary ? LabPalette.primaryText(for: colorScheme) : LabPalette.secondaryText(for: colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .background(LabPalette.controlBackground(for: colorScheme).opacity(colorScheme == .dark ? 0.78 : 0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(colorScheme == .dark ? 0.14 : 0.11), lineWidth: 1)
        }
    }
}

private struct AgeStatChipView: View {
    let title: String
    let value: String
    var symbol: String
    var tint: Color? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let resolvedTint = tint ?? LabPalette.accent(for: colorScheme)

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(resolvedTint)
                    .frame(width: 21, height: 21)
                    .background(resolvedTint.opacity(colorScheme == .dark ? 0.10 : 0.08), in: Circle())
                Spacer(minLength: 0)
            }

            Text(title)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(LabPalette.secondaryText(for: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.56)

            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(LabPalette.primaryText(for: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.70)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 78, idealHeight: 80, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    LabPalette.controlBackground(for: colorScheme).opacity(colorScheme == .dark ? 0.78 : 0.95),
                    resolvedTint.opacity(colorScheme == .dark ? 0.035 : 0.030)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(colorScheme == .dark ? 0.08 : 0.68),
                            resolvedTint.opacity(colorScheme == .dark ? 0.16 : 0.13),
                            LabPalette.controlBorder(for: colorScheme)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: resolvedTint.opacity(colorScheme == .dark ? 0.07 : 0.035), radius: 8, x: 0, y: 4)
    }
}

struct LabGenomeIconView: View {
    let size: CGFloat
    var animated = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            LabPalette.accent(for: colorScheme).opacity(colorScheme == .dark ? 0.20 : 0.11),
                            LabPalette.positive(for: colorScheme).opacity(colorScheme == .dark ? 0.12 : 0.07),
                            LabPalette.controlBackground(for: colorScheme)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            LabPalette.accent(for: colorScheme).opacity(colorScheme == .dark ? 0.18 : 0.08),
                            .clear
                        ],
                        center: .center,
                        startRadius: 1,
                        endRadius: size * 0.54
                    )
                )
                .blur(radius: size * 0.035)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(colorScheme == .dark ? 0.26 : 0.92),
                            LabPalette.accent(for: colorScheme).opacity(colorScheme == .dark ? 0.26 : 0.28),
                            .black.opacity(colorScheme == .dark ? 0.14 : 0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )

            LabGenomeIconGlyphView(tint: LabPalette.accent(for: colorScheme))
                .frame(width: size * 0.66, height: size * 0.72)

            Circle()
                .stroke(.white.opacity(colorScheme == .dark ? 0.07 : 0.30), lineWidth: 0.7)
                .padding(size * 0.17)
        }
        .frame(width: size, height: size)
        .shadow(color: LabPalette.accent(for: colorScheme).opacity(colorScheme == .dark ? 0.13 : 0.06), radius: size * 0.16, x: 0, y: size * 0.07)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lab")
        .accessibilityHint("Biological age and biomarkers")
    }
}

private struct LabGenomeIconGlyphView: View {
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let strandA = verticalStrandPath(size: size, phaseOffset: 0)
            let strandB = verticalStrandPath(size: size, phaseOffset: .pi)
            let secondary = secondaryColor
            let glowWidth = max(size.width * 0.16, 4.8)
            let strandWidth = max(size.width * 0.058, 1.75)
            let rungWidth = max(size.width * 0.035, 1.0)

            drawRungs(context: &context, size: size, lineWidth: rungWidth)

            context.stroke(
                strandA,
                with: .color(tint.opacity(colorScheme == .dark ? 0.18 : 0.10)),
                style: StrokeStyle(lineWidth: glowWidth, lineCap: .round, lineJoin: .round)
            )
            context.stroke(
                strandB,
                with: .color(secondary.opacity(colorScheme == .dark ? 0.15 : 0.09)),
                style: StrokeStyle(lineWidth: glowWidth * 0.90, lineCap: .round, lineJoin: .round)
            )

            context.stroke(
                strandA,
                with: .linearGradient(
                    Gradient(colors: [
                        tint.opacity(colorScheme == .dark ? 0.86 : 0.78),
                        tint.opacity(colorScheme == .dark ? 0.98 : 0.88),
                        secondary.opacity(colorScheme == .dark ? 0.76 : 0.68)
                    ]),
                    startPoint: CGPoint(x: size.width * 0.15, y: 0),
                    endPoint: CGPoint(x: size.width * 0.85, y: size.height)
                ),
                style: StrokeStyle(lineWidth: strandWidth, lineCap: .round, lineJoin: .round)
            )
            context.stroke(
                strandB,
                with: .linearGradient(
                    Gradient(colors: [
                        secondary.opacity(colorScheme == .dark ? 0.76 : 0.68),
                        tint.opacity(colorScheme == .dark ? 0.86 : 0.76),
                        secondary.opacity(colorScheme == .dark ? 0.88 : 0.78)
                    ]),
                    startPoint: CGPoint(x: size.width * 0.85, y: 0),
                    endPoint: CGPoint(x: size.width * 0.15, y: size.height)
                ),
                style: StrokeStyle(lineWidth: strandWidth * 0.92, lineCap: .round, lineJoin: .round)
            )

            context.stroke(
                strandA,
                with: .color(.white.opacity(colorScheme == .dark ? 0.15 : 0.34)),
                style: StrokeStyle(lineWidth: max(strandWidth * 0.28, 0.55), lineCap: .round, lineJoin: .round)
            )

            drawNodes(context: &context, size: size)
        }
        .compositingGroup()
    }

    private var secondaryColor: Color {
        colorScheme == .dark
            ? Color(red: 0.28, green: 0.72, blue: 1.00)
            : Color(red: 0.00, green: 0.35, blue: 0.61)
    }

    private var rungProgresses: [CGFloat] {
        [0.08, 0.24, 0.40, 0.56, 0.72, 0.88]
    }

    private func verticalPoint(size: CGSize, progress: CGFloat, phaseOffset: Double) -> CGPoint {
        let centerX = size.width * 0.50
        let amplitude = size.width * 0.24
        let top = size.height * 0.08
        let usableHeight = size.height * 0.84
        let theta = Double(progress) * .pi * 2 * 1.28 - .pi / 2 + phaseOffset

        return CGPoint(
            x: centerX + amplitude * CGFloat(sin(theta)),
            y: top + usableHeight * progress
        )
    }

    private func verticalStrandPath(size: CGSize, phaseOffset: Double) -> Path {
        var path = Path()
        let samples = 64
        let points = (0...samples).map { index in
            verticalPoint(size: size, progress: CGFloat(index) / CGFloat(samples), phaseOffset: phaseOffset)
        }

        guard let first = points.first else { return path }
        path.move(to: first)

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let mid = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
            path.addQuadCurve(to: mid, control: previous)
            if index == points.count - 1 {
                path.addQuadCurve(to: current, control: mid)
            }
        }

        return path
    }

    private func drawRungs(context: inout GraphicsContext, size: CGSize, lineWidth: CGFloat) {
        for progress in rungProgresses {
            let pointA = verticalPoint(size: size, progress: progress, phaseOffset: 0)
            let pointB = verticalPoint(size: size, progress: progress, phaseOffset: .pi)
            var rung = Path()
            rung.move(to: pointA)
            rung.addLine(to: pointB)

            context.stroke(
                rung,
                with: .linearGradient(
                    Gradient(colors: [
                        tint.opacity(colorScheme == .dark ? 0.34 : 0.26),
                        .white.opacity(colorScheme == .dark ? 0.16 : 0.36),
                        secondaryColor.opacity(colorScheme == .dark ? 0.30 : 0.24)
                    ]),
                    startPoint: pointA,
                    endPoint: pointB
                ),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
        }
    }

    private func drawNodes(context: inout GraphicsContext, size: CGSize) {
        let radius = max(size.width * 0.055, 1.7)
        for progress in rungProgresses {
            let pointA = verticalPoint(size: size, progress: progress, phaseOffset: 0)
            let pointB = verticalPoint(size: size, progress: progress, phaseOffset: .pi)
            drawNode(context: &context, point: pointA, radius: radius, color: tint, opacity: colorScheme == .dark ? 0.94 : 0.86)
            drawNode(context: &context, point: pointB, radius: radius * 0.94, color: secondaryColor, opacity: colorScheme == .dark ? 0.86 : 0.78)
        }
    }

    private func drawNode(context: inout GraphicsContext, point: CGPoint, radius: CGFloat, color: Color, opacity: Double) {
        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: rect.insetBy(dx: -radius * 0.85, dy: -radius * 0.85)), with: .color(color.opacity(colorScheme == .dark ? 0.16 : 0.08)))
        context.fill(Path(ellipseIn: rect), with: .color(color.opacity(opacity)))
        context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(colorScheme == .dark ? 0.28 : 0.58)), lineWidth: max(radius * 0.22, 0.55))
    }
}

private struct LabDNADoubleHelixView: View {
    let tint: Color
    var isCompact = false
    var animated = false
    var intensity = 1.0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if shouldAnimate {
                TimelineView(.animation) { timeline in
                    helixCanvas(phase: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                helixCanvas(phase: 0)
            }
        }
        .compositingGroup()
    }

    private var shouldAnimate: Bool {
        animated && !reduceMotion
    }

    private func helixCanvas(phase: TimeInterval) -> some View {
        let breath = shouldAnimate ? 0.92 + 0.08 * sin(phase * 1.10) : 1.0
        let shimmer = shouldAnimate ? (phase / 6.2).truncatingRemainder(dividingBy: 1) : -1

        return Canvas { context, size in
            let strandA = strandPath(size: size, phaseOffset: 0)
            let strandB = strandPath(size: size, phaseOffset: .pi)
            let primary = tint
            let secondary = helixSecondaryColor
            let glowOpacity = (colorScheme == .dark ? 0.22 : 0.11) * breath * intensity
            let strandOpacity = (colorScheme == .dark ? 0.72 : 0.62) * breath * intensity
            let secondaryOpacity = (colorScheme == .dark ? 0.54 : 0.46) * breath * intensity

            if !isCompact {
                context.fill(
                    Path(roundedRect: CGRect(x: size.width * 0.06, y: size.height * 0.12, width: size.width * 0.88, height: size.height * 0.76), cornerRadius: size.height * 0.38),
                    with: .radialGradient(
                        Gradient(colors: [
                            primary.opacity((colorScheme == .dark ? 0.13 : 0.075) * breath * intensity),
                            secondary.opacity((colorScheme == .dark ? 0.07 : 0.045) * breath * intensity),
                            .clear
                        ]),
                        center: CGPoint(x: size.width * 0.54, y: size.height * 0.52),
                        startRadius: 8,
                        endRadius: size.width * 0.54
                    )
                )
            }

            drawRungs(context: &context, size: size, breath: breath, phase: phase)

            context.stroke(
                strandA,
                with: .color(primary.opacity(glowOpacity)),
                style: StrokeStyle(lineWidth: isCompact ? 7.0 : 18.0, lineCap: .round, lineJoin: .round)
            )
            context.stroke(
                strandB,
                with: .color(secondary.opacity(glowOpacity * 0.86)),
                style: StrokeStyle(lineWidth: isCompact ? 6.2 : 16.0, lineCap: .round, lineJoin: .round)
            )

            context.stroke(
                strandA,
                with: .linearGradient(
                    Gradient(colors: [
                        primary.opacity(strandOpacity * 0.76),
                        primary.opacity(strandOpacity),
                        secondary.opacity(strandOpacity * 0.72)
                    ]),
                    startPoint: CGPoint(x: 0, y: size.height * 0.18),
                    endPoint: CGPoint(x: size.width, y: size.height * 0.82)
                ),
                style: StrokeStyle(lineWidth: isCompact ? 2.2 : 4.4, lineCap: .round, lineJoin: .round)
            )
            context.stroke(
                strandB,
                with: .linearGradient(
                    Gradient(colors: [
                        secondary.opacity(secondaryOpacity * 0.78),
                        primary.opacity(secondaryOpacity * 0.72),
                        secondary.opacity(secondaryOpacity)
                    ]),
                    startPoint: CGPoint(x: 0, y: size.height * 0.82),
                    endPoint: CGPoint(x: size.width, y: size.height * 0.18)
                ),
                style: StrokeStyle(lineWidth: isCompact ? 2.0 : 3.8, lineCap: .round, lineJoin: .round)
            )

            context.stroke(
                strandA,
                with: .color(.white.opacity(colorScheme == .dark ? 0.11 : 0.22)),
                style: StrokeStyle(lineWidth: isCompact ? 0.7 : 1.15, lineCap: .round, lineJoin: .round)
            )

            if shouldAnimate {
                drawShimmer(context: &context, size: size, center: shimmer, phaseOffset: 0, color: .white)
                drawShimmer(context: &context, size: size, center: (shimmer + 0.18).truncatingRemainder(dividingBy: 1), phaseOffset: .pi, color: primary)
            }

            drawNodes(context: &context, size: size, breath: breath, phase: phase)
        }
    }

    private var helixSecondaryColor: Color {
        colorScheme == .dark
            ? Color(red: 0.32, green: 0.68, blue: 1.00)
            : Color(red: 0.00, green: 0.34, blue: 0.62)
    }

    private var sampleCount: Int {
        isCompact ? 54 : 108
    }

    private var rungCount: Int {
        isCompact ? 5 : 11
    }

    private var cycles: Double {
        isCompact ? 1.15 : 1.85
    }

    private func strandPath(size: CGSize, phaseOffset: Double) -> Path {
        var path = Path()
        let points = (0...sampleCount).map { index in
            helixPoint(size: size, progress: CGFloat(index) / CGFloat(sampleCount), phaseOffset: phaseOffset)
        }

        guard let first = points.first else { return path }
        path.move(to: first)

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let mid = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
            path.addQuadCurve(to: mid, control: previous)
            if index == points.count - 1 {
                path.addQuadCurve(to: current, control: mid)
            }
        }

        return path
    }

    private func helixPoint(size: CGSize, progress: CGFloat, phaseOffset: Double) -> CGPoint {
        let insetX = size.width * (isCompact ? 0.18 : 0.035)
        let usableWidth = max(size.width - insetX * 2, 1)
        let amplitude = size.height * (isCompact ? 0.245 : 0.275)
        let centerY = size.height * 0.50
        let theta = Double(progress) * .pi * 2 * cycles - .pi / 2 + phaseOffset

        return CGPoint(
            x: insetX + usableWidth * progress,
            y: centerY + amplitude * CGFloat(sin(theta))
        )
    }

    private func drawRungs(context: inout GraphicsContext, size: CGSize, breath: Double, phase: TimeInterval) {
        for index in 0..<rungCount {
            let progress = CGFloat(index) / CGFloat(max(rungCount - 1, 1))
            let pointA = helixPoint(size: size, progress: progress, phaseOffset: 0)
            let pointB = helixPoint(size: size, progress: progress, phaseOffset: .pi)
            let theta = Double(progress) * .pi * 2 * cycles - .pi / 2
            let depth = 0.58 + 0.42 * abs(cos(theta))
            let pulse = shouldAnimate ? 0.92 + 0.08 * sin(phase * 0.82 + Double(index) * 0.48) : 1
            let opacity = (colorScheme == .dark ? 0.24 : 0.18) * depth * breath * pulse * intensity

            var rung = Path()
            rung.move(to: pointA)
            rung.addLine(to: pointB)
            context.stroke(
                rung,
                with: .color(tint.opacity(opacity)),
                style: StrokeStyle(lineWidth: isCompact ? 1.0 : 1.45, lineCap: .round)
            )
        }
    }

    private func drawShimmer(context: inout GraphicsContext, size: CGSize, center: Double, phaseOffset: Double, color: Color) {
        let span = isCompact ? 0.26 : 0.18
        let start = max(center - span / 2, 0)
        let end = min(center + span / 2, 1)
        guard end > start else { return }

        var path = Path()
        let sampleTotal = 20
        for sample in 0...sampleTotal {
            let progress = start + (end - start) * Double(sample) / Double(sampleTotal)
            let point = helixPoint(size: size, progress: CGFloat(progress), phaseOffset: phaseOffset)
            if sample == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        let opacity = (colorScheme == .dark ? 0.32 : 0.20) * intensity
        context.stroke(
            path,
            with: .linearGradient(
                Gradient(colors: [
                    color.opacity(0),
                    color.opacity(opacity),
                    tint.opacity(opacity * 0.72),
                    color.opacity(0)
                ]),
                startPoint: CGPoint(x: size.width * CGFloat(start), y: 0),
                endPoint: CGPoint(x: size.width * CGFloat(end), y: size.height)
            ),
            style: StrokeStyle(lineWidth: isCompact ? 1.0 : 2.0, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawNodes(context: inout GraphicsContext, size: CGSize, breath: Double, phase: TimeInterval) {
        for index in 0..<rungCount {
            let progress = CGFloat(index) / CGFloat(max(rungCount - 1, 1))
            let pointA = helixPoint(size: size, progress: progress, phaseOffset: 0)
            let pointB = helixPoint(size: size, progress: progress, phaseOffset: .pi)
            let isMajor = index == rungCount / 2 || index == 1 || index == rungCount - 2
            let pulse = shouldAnimate ? 0.90 + 0.10 * sin(phase * 1.34 + Double(index) * 0.72) : 1
            let nodeScale = shouldAnimate ? 0.97 + 0.03 * sin(phase * 1.34 + Double(index) * 0.72) : 1
            let nodeSize = (isCompact ? (isMajor ? 4.8 : 3.8) : (isMajor ? 6.4 : 5.0)) * nodeScale
            let opacity = (isMajor ? 0.72 : 0.52) * breath * pulse * intensity

            drawNode(context: &context, point: pointA, size: nodeSize, opacity: opacity, color: tint)
            drawNode(context: &context, point: pointB, size: nodeSize * 0.92, opacity: opacity * 0.84, color: helixSecondaryColor)
        }
    }

    private func drawNode(context: inout GraphicsContext, point: CGPoint, size: CGFloat, opacity: Double, color: Color) {
        let rect = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
        let glowInset = isCompact ? CGFloat(-2.8) : CGFloat(-5.5)
        let glassInset = isCompact ? CGFloat(-1.1) : CGFloat(-1.9)

        context.fill(Path(ellipseIn: rect.insetBy(dx: glowInset, dy: glowInset)), with: .color(color.opacity(opacity * (colorScheme == .dark ? 0.18 : 0.09))))
        context.fill(Path(ellipseIn: rect.insetBy(dx: glassInset, dy: glassInset)), with: .color(color.opacity(opacity * 0.25)))
        context.fill(Path(ellipseIn: rect), with: .color(color.opacity(opacity)))
        context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(colorScheme == .dark ? 0.20 : 0.42)), lineWidth: isCompact ? 0.55 : 0.75)
    }
}

private struct LabCapsuleParticles: View {
    let tint: Color
    let phase: TimeInterval

    var body: some View {
        Canvas { context, size in
            for index in 0..<22 {
                let seed = Double(index)
                let x = size.width * CGFloat((seed * 0.137).truncatingRemainder(dividingBy: 1))
                let yBase = size.height * CGFloat((seed * 0.217).truncatingRemainder(dividingBy: 1))
                let y = yBase + CGFloat(sin(phase * 0.7 + seed) * 5)
                let dotSize = CGFloat(1.4 + seed.truncatingRemainder(dividingBy: 3))
                let rect = CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize)
                context.fill(Path(ellipseIn: rect), with: .color(tint.opacity(0.20 + 0.08 * sin(phase + seed))))
            }
        }
    }
}

private enum LabTrajectoryStatus: String, CaseIterable {
    case waiting
    case improving
    case stable
    case accelerating

    var title: String {
        switch self {
        case .waiting:
            return "Waiting for history"
        case .improving:
            return "Improving"
        case .stable:
            return "Stable"
        case .accelerating:
            return "Accelerating"
        }
    }

    var explanation: String {
        switch self {
        case .waiting:
            return "Complete at least 3 weekly biological age calculations to unlock trajectory."
        case .improving:
            return "Your biological age is trending slower than your chronological age."
        case .stable:
            return "Your biological age is moving in line with your chronological age."
        case .accelerating:
            return "Your biological age is trending faster than expected."
        }
    }

    var markerProgress: CGFloat {
        switch self {
        case .waiting:
            return 0.50
        case .improving:
            return 0.16
        case .stable:
            return 0.50
        case .accelerating:
            return 0.84
        }
    }

    func tint(for colorScheme: ColorScheme) -> Color {
        switch self {
        case .waiting:
            return LabPalette.accent(for: colorScheme)
        case .improving:
            return LabPalette.positive(for: colorScheme)
        case .stable:
            return LabPalette.accent(for: colorScheme)
        case .accelerating:
            return LabPalette.warning(for: colorScheme)
        }
    }
}

private struct LabHealthTrajectoryCard: View {
    let result: BiologicalAgeResult
    let trendResults: [BiologicalAgeResult]
    @State private var markerProgress: CGFloat = 0.5
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let status = trajectoryStatus
        let tint = status.tint(for: colorScheme)

        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Health Trajectory")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(LabPalette.primaryText(for: colorScheme))
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(LabPalette.secondaryText(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)

                Spacer(minLength: 8)

                LabTrajectoryStatusPill(text: status.title, tint: tint)
            }

            LabTrajectoryZoneRail(
                status: status,
                markerProgress: markerProgress,
                hasTrajectory: hasTrajectory,
                tint: tint
            )
            .frame(height: 148)

            if hasTrajectory {
                HStack(spacing: 10) {
                    LabTrajectoryMetricTile(title: "Weekly change", value: weeklyChangeText, tint: tint)
                    LabTrajectoryMetricTile(title: "4-week pace", value: paceText, tint: LabPalette.accent(for: colorScheme))
                }

                Text(status.explanation)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(LabPalette.secondaryText(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    Text(status.explanation)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LabPalette.primaryText(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Pulsar recalculates every Monday.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(LabPalette.secondaryText(for: colorScheme))
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LabPalette.controlBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(LabPalette.controlBorder(for: colorScheme), lineWidth: 1)
                }
            }
        }
        .padding(20)
        .labGlassCard(cornerRadius: 30, glow: tint.opacity(colorScheme == .dark ? 0.14 : 0.07))
        .onAppear {
            if reduceMotion {
                markerProgress = status.markerProgress
            } else {
                withAnimation(.spring(response: 0.72, dampingFraction: 0.86).delay(0.12)) {
                    markerProgress = status.markerProgress
                }
            }
        }
        .onChange(of: status.markerProgress) { _, newValue in
            if reduceMotion {
                markerProgress = newValue
            } else {
                withAnimation(.spring(response: 0.72, dampingFraction: 0.86)) {
                    markerProgress = newValue
                }
            }
        }
    }

    private var trajectoryResults: [BiologicalAgeResult] {
        var results = trendResults

        if !results.contains(where: { Calendar.current.isDate($0.updatedAt, inSameDayAs: result.updatedAt) }) {
            results.append(result)
        }

        return Array(results.sorted { $0.updatedAt < $1.updatedAt }.suffix(4))
    }

    private var hasTrajectory: Bool {
        trajectoryResults.count >= 3
    }

    private var subtitle: String {
        hasTrajectory
            ? "Your biological age direction over time"
            : "Trajectory unlocks after multiple weekly calculations"
    }

    private var periodChange: Double {
        guard hasTrajectory,
              let oldest = trajectoryResults.first,
              let newest = trajectoryResults.last else { return 0 }
        return newest.biologicalAge - oldest.biologicalAge
    }

    private var latestWeeklyChange: Double {
        guard hasTrajectory,
              trajectoryResults.count >= 2,
              let newest = trajectoryResults.last,
              let previous = trajectoryResults.dropLast().last else { return 0 }
        return newest.biologicalAge - previous.biologicalAge
    }

    private var trajectoryStatus: LabTrajectoryStatus {
        guard hasTrajectory else { return .waiting }

        if periodChange <= -0.2 || pace < 0.98 {
            return .improving
        }

        if periodChange >= 0.2 || pace > 1.02 {
            return .accelerating
        }

        return .stable
    }

    private var pace: Double {
        if let paceOfAging = result.paceOfAging {
            return min(max(paceOfAging, 0.90), 1.10)
        }

        guard hasTrajectory else { return 1.0 }
        return min(max(1 + latestWeeklyChange * 0.10, 0.90), 1.10)
    }

    private var weeklyChangeText: String {
        guard abs(latestWeeklyChange) >= 0.05 else { return "No meaningful change" }
        return String(format: "%+.1f yr this week", latestWeeklyChange)
    }

    private var paceText: String {
        String(format: "%.2fx pace", pace)
    }
}

private struct LabTrajectoryStatusPill: View {
    let text: String
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.70)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(colorScheme == .dark ? 0.13 : 0.09), in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(tint.opacity(colorScheme == .dark ? 0.32 : 0.22), lineWidth: 1)
            }
    }
}

private struct LabTrajectoryZoneRail: View {
    let status: LabTrajectoryStatus
    let markerProgress: CGFloat
    let hasTrajectory: Bool
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let railWidth = max(width - 34, 1)
            let railY: CGFloat = 68
            let markerX = 17 + railWidth * min(max(markerProgress, 0), 1)
            let zoneColors = [
                LabPalette.positive(for: colorScheme),
                LabPalette.accent(for: colorScheme),
                LabPalette.warning(for: colorScheme)
            ]
            let zoneLabels = ["Improving", "Stable", "Accelerating"]

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                LabPalette.controlBackground(for: colorScheme),
                                tint.opacity(colorScheme == .dark ? 0.08 : 0.045)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { index in
                        zoneColors[index]
                            .opacity(hasTrajectory ? (colorScheme == .dark ? 0.22 : 0.16) : (colorScheme == .dark ? 0.10 : 0.075))
                            .frame(maxWidth: .infinity)
                            .overlay(alignment: .top) {
                                LinearGradient(
                                    colors: [
                                        .white.opacity(colorScheme == .dark ? 0.10 : 0.28),
                                        .clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            }
                    }
                }
                .frame(width: railWidth, height: 18)
                .clipShape(Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(colorScheme == .dark ? 0.14 : 0.48), lineWidth: 1)
                }
                .position(x: width / 2, y: railY)

                Capsule(style: .continuous)
                    .fill(tint.opacity(hasTrajectory ? (colorScheme == .dark ? 0.36 : 0.28) : 0.16))
                    .frame(width: max(railWidth * 0.21, 54), height: 5)
                    .blur(radius: 7)
                    .position(x: markerX, y: railY)

                ForEach(0..<3, id: \.self) { index in
                    let zoneX = 17 + railWidth * (CGFloat(index) + 0.5) / 3
                    VStack(spacing: 8) {
                        Text(zoneLabels[index])
                            .font(.caption2.weight(statusIndex == index ? .bold : .semibold))
                            .foregroundStyle(labelColor(index: index))
                            .lineLimit(1)
                            .minimumScaleFactor(0.74)

                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(zoneColors[index].opacity(statusIndex == index && hasTrajectory ? 0.72 : 0.24))
                            .frame(width: 2, height: 18)
                    }
                    .frame(width: railWidth / 3)
                    .position(x: zoneX, y: 34)
                }

                trajectoryMarker
                    .position(x: markerX, y: railY)

                HStack(spacing: 8) {
                    Image(systemName: hasTrajectory ? "waveform.path.ecg" : "lock.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                        .frame(width: 22, height: 22)
                        .background(tint.opacity(colorScheme == .dark ? 0.13 : 0.09), in: Circle())

                    Text(hasTrajectory ? "Based on repeated Monday calculations." : "Locked until 3 weekly results are available.")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(LabPalette.secondaryText(for: colorScheme))
                        .lineLimit(2)
                        .minimumScaleFactor(0.86)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .background(LabPalette.cardBackground(for: colorScheme), in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(LabPalette.controlBorder(for: colorScheme), lineWidth: 1)
                }
                .position(x: width / 2, y: 122)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(LabPalette.controlBorder(for: colorScheme), lineWidth: 1)
            }
        }
    }

    private var statusIndex: Int {
        switch status {
        case .improving:
            return 0
        case .waiting, .stable:
            return 1
        case .accelerating:
            return 2
        }
    }

    private var trajectoryMarker: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(colorScheme == .dark ? 0.18 : 0.12))
                .frame(width: 54, height: 54)
                .blur(radius: 5)

            Circle()
                .fill(LabPalette.cardBackground(for: colorScheme))
                .frame(width: 42, height: 42)
                .overlay {
                    Circle()
                        .stroke(tint.opacity(colorScheme == .dark ? 0.60 : 0.44), lineWidth: 1.2)
                }

            Circle()
                .fill(tint)
                .frame(width: hasTrajectory ? 13 : 9, height: hasTrajectory ? 13 : 9)
                .shadow(color: tint.opacity(colorScheme == .dark ? 0.42 : 0.20), radius: 10)

            if !hasTrajectory {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(tint)
                    .offset(y: 15)
            }
        }
    }

    private func labelColor(index: Int) -> Color {
        if hasTrajectory, statusIndex == index {
            return LabPalette.primaryText(for: colorScheme)
        }

        return LabPalette.secondaryText(for: colorScheme)
    }
}

private struct LabTrajectoryMetricTile: View {
    let title: String
    let value: String
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(LabPalette.secondaryText(for: colorScheme))
                .lineLimit(1)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(LabPalette.primaryText(for: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(colorScheme == .dark ? 0.10 : 0.065), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(colorScheme == .dark ? 0.18 : 0.13), lineWidth: 1)
        }
    }
}

private struct AnimatedDecimalText: View, Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(String(format: "%.1f", value))
    }
}

private struct LabHeroMetric: View {
    let title: String
    let value: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(LabPalette.secondaryText(for: colorScheme))
                .lineLimit(1)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(LabPalette.primaryText(for: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LabPalette.controlBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(LabPalette.controlBorder(for: colorScheme), lineWidth: 1)
        }
    }
}

private struct LabSectionTitle: View {
    let title: String
    var subtitle: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(LabPalette.primaryText(for: colorScheme))
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(LabPalette.secondaryText(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 2)
    }
}

private struct LabPillarCard: View {
    let pillar: LabPillarResult
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: pillar.kind.labSymbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(colorScheme == .dark ? 0.13 : 0.10), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(pillar.kind.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(LabPalette.primaryText(for: colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                    Text(pillar.statusLabel)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                }

                Spacer()

                Text(scoreText)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(LabPalette.primaryText(for: colorScheme))
                    .minimumScaleFactor(0.7)
            }

            LabPillarProgressBar(score: pillar.score, tint: tint)
                .frame(height: 8)

            Text(pillar.explanation)
                .font(.caption)
                .foregroundStyle(LabPalette.secondaryText(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                LabMiniPill(text: contributionText, tint: pillar.contributionYears <= 0 ? LabPalette.positive(for: colorScheme) : LabPalette.warning(for: colorScheme))
                if pillar.score == nil {
                    LabMiniPill(text: "Missing data", tint: LabPalette.tertiaryText(for: colorScheme))
                } else {
                    LabMiniPill(text: "Signal active", tint: LabPalette.accent(for: colorScheme))
                }
            }
        }
        .padding(16)
        .labGlassCard(cornerRadius: 26, glow: tint.opacity(colorScheme == .dark ? 0.10 : 0.05))
    }

    private var scoreText: String {
        guard let score = pillar.score else { return "--" }
        return "\(Int(score.rounded()))"
    }

    private var contributionText: String {
        String(format: "%+.1f yr", pillar.contributionYears)
    }

    private var tint: Color {
        guard let score = pillar.score else { return LabPalette.tertiaryText(for: colorScheme) }
        switch score {
        case 86...100: return LabPalette.positive(for: colorScheme)
        case 72..<86: return LabPalette.accent(for: colorScheme)
        default: return LabPalette.warning(for: colorScheme)
        }
    }
}

private struct LabPillarProgressBar: View {
    let score: Double?
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * CGFloat(min(max((score ?? 0) / 100, 0), 1))
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(LabPalette.tertiaryText(for: colorScheme).opacity(colorScheme == .dark ? 0.18 : 0.14))
                Capsule(style: .continuous)
                    .fill(tint)
                    .frame(width: max(score == nil ? 0 : width, 0))
                    .shadow(color: tint.opacity(colorScheme == .dark ? 0.34 : 0.14), radius: 7)
            }
        }
    }
}

private struct LabMiniPill: View {
    let text: String
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(colorScheme == .dark ? 0.11 : 0.08), in: Capsule(style: .continuous))
    }
}

private struct DataConfidenceCard: View {
    let result: BiologicalAgeResult
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Data confidence")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(LabPalette.primaryText(for: colorScheme))
                    Text("\(confidencePercent)%")
                        .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(LabPalette.primaryText(for: colorScheme))
                }

                Spacer()

                LabStatusPill(text: result.confidence.rawValue)
            }

            Text("Confidence improves with 20+ days of data and recent lab results. Blood markers should be less than 6 months old.")
                .font(.subheadline)
                .foregroundStyle(LabPalette.secondaryText(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            if !result.missingDataMessages.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(result.missingDataMessages.prefix(3).enumerated()), id: \.offset) { _, message in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.caption)
                                .foregroundStyle(LabPalette.accent(for: colorScheme))
                                .padding(.top, 2)
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(LabPalette.secondaryText(for: colorScheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(18)
        .labGlassCard(cornerRadius: 30, glow: LabPalette.accent(for: colorScheme).opacity(colorScheme == .dark ? 0.12 : 0.06))
    }

    private var confidencePercent: Int {
        switch result.confidence {
        case .high: return 92
        case .medium: return 68
        case .low: return 38
        }
    }
}

private struct LabEmptyStateCard: View {
    let hasBiomarkers: Bool
    let onConnectData: () -> Void
    let onImport: () -> Void
    let onManualEntry: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ZStack {
                Circle()
                    .fill(LabPalette.accent(for: colorScheme).opacity(colorScheme == .dark ? 0.16 : 0.10))
                    .frame(width: 74, height: 74)
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(LabPalette.accent(for: colorScheme))
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Build your biological age profile")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(LabPalette.primaryText(for: colorScheme))
                Text(emptyCopy)
                    .font(.subheadline)
                    .foregroundStyle(LabPalette.secondaryText(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                LabCommandButton(title: "Connect data", symbol: "heart.text.square.fill", action: onConnectData)
                LabCommandButton(title: "Import labs", symbol: "doc.badge.plus", action: onImport)
            }

            Button(action: onManualEntry) {
                Label("Enter manually", systemImage: "square.and.pencil")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            .foregroundStyle(LabPalette.primaryText(for: colorScheme))
            .background(LabPalette.controlBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(LabPalette.controlBorder(for: colorScheme), lineWidth: 1)
            }
        }
        .padding(20)
        .labGlassCard(cornerRadius: 32, glow: LabPalette.accent(for: colorScheme).opacity(colorScheme == .dark ? 0.18 : 0.08))
    }

    private var emptyCopy: String {
        hasBiomarkers
            ? "Add birthday and wearable history to calculate your estimate from the biomarkers already saved."
            : "Connect wearable history, import lab results, or manually enter biomarkers to start the estimate."
    }
}

private struct LabActionStrip: View {
    let onImport: () -> Void
    let onManualEntry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            LabCommandButton(title: "Import Lab Results", symbol: "doc.badge.plus", action: onImport)
            LabCommandButton(title: "Enter manually", symbol: "square.and.pencil", action: onManualEntry)
        }
    }
}

private struct LabCommandButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .padding(.horizontal, 10)
        }
        .buttonStyle(.plain)
        .foregroundStyle(LabPalette.primaryText(for: colorScheme))
        .background(
            LinearGradient(
                colors: [
                    LabPalette.accent(for: colorScheme).opacity(colorScheme == .dark ? 0.18 : 0.10),
                    LabPalette.positive(for: colorScheme).opacity(colorScheme == .dark ? 0.10 : 0.07),
                    LabPalette.controlBackground(for: colorScheme)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(LabPalette.controlBorder(for: colorScheme), lineWidth: 1)
        }
    }
}

private struct BiomarkersSection: View {
    let biomarkers: [LabBiomarker]
    let onImport: () -> Void
    let onManualEntry: () -> Void
    let onDelete: (LabBiomarker) -> Void
    @State private var selectedBiomarker: LabBiomarker?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabSectionTitle(title: "Biomarkers", subtitle: "Professional lab records used by the biological age engine.")

            HStack(spacing: 10) {
                LabCommandButton(title: "Import PDF", symbol: "doc.badge.plus", action: onImport)
                LabCommandButton(title: "Enter manually", symbol: "square.and.pencil", action: onManualEntry)
            }

            VStack(spacing: 10) {
                ForEach(biomarkers) { biomarker in
                    Button {
                        selectedBiomarker = biomarker
                    } label: {
                        BiomarkerRow(biomarker: biomarker)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(item: $selectedBiomarker) { biomarker in
            BiomarkerDetailView(biomarker: biomarker, onDelete: {
                selectedBiomarker = nil
                onDelete(biomarker)
            })
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

private struct BiomarkerRow: View {
    let biomarker: LabBiomarker
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            Circle()
                .fill(statusTint)
                .frame(width: 10, height: 10)
                .shadow(color: statusTint.opacity(0.5), radius: 5)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(biomarker.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(LabPalette.primaryText(for: colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                    Text(biomarker.status.rawValue)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(statusTint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(statusTint.opacity(0.12), in: Capsule(style: .continuous))
                }

                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(LabPalette.secondaryText(for: colorScheme))
                    .lineLimit(2)
            }
            .layoutPriority(1)

            VStack(alignment: .trailing, spacing: 3) {
                Text(valueText)
                    .font(.headline.weight(.bold).monospacedDigit())
                    .foregroundStyle(LabPalette.primaryText(for: colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                Text(biomarker.unit.isEmpty ? " " : biomarker.unit)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LabPalette.tertiaryText(for: colorScheme))
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(LabPalette.tertiaryText(for: colorScheme))
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .labGlassCard(cornerRadius: 24, glow: statusTint.opacity(0.08))
    }

    private var valueText: String {
        biomarker.value == nil ? "--" : biomarker.displayValue
    }

    private var detailText: String {
        let dateText = biomarker.collectedAt?.formatted(.dateTime.month(.abbreviated).day().year()) ?? "No collection date"
        return "\(biomarker.displayReferenceRange) | \(dateText)"
    }

    private var statusTint: Color {
        biomarker.status.labTint(for: colorScheme)
    }
}

private struct BiomarkerDetailView: View {
    let biomarker: LabBiomarker
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(biomarker.name)
                                    .font(.largeTitle.weight(.semibold))
                                    .foregroundStyle(LabPalette.primaryText(for: colorScheme))
                                Text(biomarker.status.rawValue)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(statusTint)
                            }
                            Spacer()
                            Text(biomarker.displayValue)
                                .font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(LabPalette.primaryText(for: colorScheme))
                                .lineLimit(1)
                                .minimumScaleFactor(0.66)
                        }

                        Text(biomarker.unit)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(LabPalette.secondaryText(for: colorScheme))
                    }
                    .padding(18)
                    .labGlassCard(cornerRadius: 30, glow: statusTint.opacity(0.16))

                    LabDetailRow(title: "Reference range", value: biomarker.displayReferenceRange)
                    LabDetailRow(title: "Collected", value: biomarker.collectedAt?.formatted(.dateTime.month(.wide).day().year()) ?? "Missing")
                    LabDetailRow(title: "Source", value: biomarker.source.label)

                    if let definition = LabBiomarkerDefinition.definition(for: biomarker.name) {
                        Text(definition.explanation)
                            .font(.subheadline)
                            .foregroundStyle(LabPalette.secondaryText(for: colorScheme))
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .labGlassCard(cornerRadius: 24, glow: LabPalette.accent(for: colorScheme).opacity(0.08))
                    }

                    if let notes = biomarker.notes {
                        LabDetailRow(title: "Notes", value: notes)
                    }

                    if biomarker.value != nil {
                        Button(role: .destructive, action: onDelete) {
                            Label("Delete biomarker", systemImage: "trash")
                                .font(.headline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                        .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }
                .padding(18)
            }
            .background(LabModuleBackground())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var statusTint: Color {
        biomarker.status.labTint(for: colorScheme)
    }
}

private struct LabDetailRow: View {
    let title: String
    let value: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(LabPalette.secondaryText(for: colorScheme))
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(LabPalette.primaryText(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .labGlassCard(cornerRadius: 22, glow: Color.white.opacity(0.04))
    }
}

private struct ImportLabResultsView: View {
    @ObservedObject var store: LabModuleStore
    let profile: UserProfile
    let onEnterManually: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var isShowingPicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                switch store.state.importStatus {
                case .idle:
                    importIntro
                case .importing(let progress):
                    importingView(progress: progress)
                case .review(let extracted):
                    reviewView(extracted: extracted)
                case .comingSoon(let message):
                    importMessageView(
                        symbol: "sparkles",
                        title: "PDF import is coming soon",
                        message: message,
                        showsRetry: true
                    )
                case .failed(let message):
                    importMessageView(
                        symbol: "exclamationmark.triangle.fill",
                        title: "Import failed",
                        message: message,
                        showsRetry: true
                    )
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(LabModuleBackground())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        store.resetImportStatus()
                        dismiss()
                    }
                }
            }
            .fileImporter(isPresented: $isShowingPicker, allowedContentTypes: [.pdf]) { result in
                guard let url = try? result.get() else {
                    store.resetImportStatus()
                    return
                }
                Task {
                    await store.importPDF(from: url, profile: profile)
                }
            }
        }
    }

    private var importIntro: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(LabPalette.accent(for: colorScheme))
                .frame(width: 76, height: 76)
                .background(LabPalette.accent(for: colorScheme).opacity(colorScheme == .dark ? 0.12 : 0.08), in: Circle())

            VStack(alignment: .leading, spacing: 8) {
                Text("Import Lab Results")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(LabPalette.primaryText(for: colorScheme))
                Text("Select a PDF lab report. Extraction architecture is in place; parser connection will arrive in a later step.")
                    .font(.subheadline)
                    .foregroundStyle(LabPalette.secondaryText(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            LabCommandButton(title: "Select PDF", symbol: "doc.badge.plus") {
                isShowingPicker = true
            }

            Button(action: onEnterManually) {
                Label("Enter manually", systemImage: "square.and.pencil")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .foregroundStyle(LabPalette.primaryText(for: colorScheme))
            .background(LabPalette.controlBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .padding(20)
        .labGlassCard(cornerRadius: 32, glow: LabPalette.accent(for: colorScheme).opacity(colorScheme == .dark ? 0.16 : 0.08))
    }

    private func importingView(progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Reading PDF")
                .font(.title2.weight(.semibold))
                .foregroundStyle(LabPalette.primaryText(for: colorScheme))
            ProgressView(value: progress)
                .tint(LabPalette.accent(for: colorScheme))
            Text("\(Int((progress * 100).rounded()))%")
                .font(.headline.weight(.bold).monospacedDigit())
                .foregroundStyle(LabPalette.secondaryText(for: colorScheme))
        }
        .padding(20)
        .labGlassCard(cornerRadius: 32, glow: LabPalette.accent(for: colorScheme).opacity(colorScheme == .dark ? 0.16 : 0.08))
    }

    private func reviewView(extracted: [LabBiomarker]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Review extracted biomarkers")
                .font(.title2.weight(.semibold))
                .foregroundStyle(LabPalette.primaryText(for: colorScheme))

            ForEach(extracted) { biomarker in
                BiomarkerRow(biomarker: biomarker)
            }

            LabCommandButton(title: "Confirm and Save", symbol: "checkmark.circle.fill") {
                store.confirmImportedBiomarkers(extracted, profile: profile)
                dismiss()
            }
        }
    }

    private func importMessageView(symbol: String, title: String, message: String, showsRetry: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(LabPalette.accent(for: colorScheme))
                .frame(width: 76, height: 76)
                .background(LabPalette.accent(for: colorScheme).opacity(colorScheme == .dark ? 0.12 : 0.08), in: Circle())

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(LabPalette.primaryText(for: colorScheme))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(LabPalette.secondaryText(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onEnterManually) {
                Label("Enter manually", systemImage: "square.and.pencil")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .foregroundStyle(LabPalette.primaryText(for: colorScheme))
            .background(LabPalette.accent(for: colorScheme).opacity(colorScheme == .dark ? 0.13 : 0.09), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            if showsRetry {
                Button("Choose another PDF") {
                    store.resetImportStatus()
                    isShowingPicker = true
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .padding(20)
        .labGlassCard(cornerRadius: 32, glow: LabPalette.accent(for: colorScheme).opacity(colorScheme == .dark ? 0.16 : 0.08))
    }
}

private struct ManualBiomarkerEntryView: View {
    @ObservedObject var store: LabModuleStore
    let profile: UserProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var name = ""
    @State private var value = ""
    @State private var unit = ""
    @State private var collectedAt = Date()
    @State private var referenceLow = ""
    @State private var referenceHigh = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    LabSectionTitle(title: "Enter Biomarker", subtitle: "Values are saved locally and used by the Lab calculator.")

                    Menu {
                        ForEach(LabBiomarkerDefinition.required) { definition in
                            Button(definition.name) {
                                name = definition.name
                                unit = definition.unit
                                referenceLow = definition.referenceLow?.formattedLabValue ?? ""
                                referenceHigh = definition.referenceHigh?.formattedLabValue ?? ""
                            }
                        }
                    } label: {
                        Label(name.isEmpty ? "Choose common biomarker" : name, systemImage: "list.bullet")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(LabPalette.primaryText(for: colorScheme))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(LabPalette.controlBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    LabTextField(title: "Biomarker name", text: $name, keyboardType: .default)
                    LabTextField(title: "Value", text: $value, keyboardType: .decimalPad)
                    LabTextField(title: "Unit", text: $unit, keyboardType: .default)

                    DatePicker("Date collected", selection: $collectedAt, displayedComponents: .date)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(LabPalette.primaryText(for: colorScheme))
                        .padding(16)
                        .background(LabPalette.controlBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                    HStack(spacing: 10) {
                        LabTextField(title: "Reference low", text: $referenceLow, keyboardType: .decimalPad)
                        LabTextField(title: "Reference high", text: $referenceHigh, keyboardType: .decimalPad)
                    }

                    LabTextField(title: "Notes", text: $notes, keyboardType: .default)

                    Button(action: save) {
                        Label("Save biomarker", systemImage: "checkmark.circle.fill")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(LabPalette.primaryText(for: colorScheme))
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.45)
                    .background(LabPalette.accent(for: colorScheme).opacity(colorScheme == .dark ? 0.16 : 0.10), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .padding(18)
            }
            .background(LabModuleBackground())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var canSave: Bool {
        name.nilIfBlank != nil && Double(value) != nil
    }

    private func save() {
        guard let parsedValue = Double(value) else { return }
        _ = store.addManualBiomarker(
            name: name,
            value: parsedValue,
            unit: unit,
            collectedAt: collectedAt,
            referenceLow: Double(referenceLow),
            referenceHigh: Double(referenceHigh),
            notes: notes,
            profile: profile
        )
        dismiss()
    }
}

private struct LabTextField: View {
    let title: String
    @Binding var text: String
    let keyboardType: UIKeyboardType
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(LabPalette.secondaryText(for: colorScheme))
            TextField(title, text: $text)
                .font(.headline.weight(.semibold))
                .foregroundStyle(LabPalette.primaryText(for: colorScheme))
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.words)
        }
        .padding(16)
        .background(LabPalette.controlBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(LabPalette.controlBorder(for: colorScheme), lineWidth: 1)
        }
    }
}

private struct LabDisclaimerCard: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text("Biological Age is an estimate based on available health, lifestyle, and biomarker data. It is not a diagnosis or a substitute for medical advice.")
            .font(.caption)
            .foregroundStyle(LabPalette.secondaryText(for: colorScheme))
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .labGlassCard(cornerRadius: 24, glow: Color.white.opacity(0.04))
    }
}

private enum LabPalette {
    static func primaryText(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? .white.opacity(0.96)
            : Color(red: 0.04, green: 0.08, blue: 0.12)
    }

    static func secondaryText(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? .white.opacity(0.68)
            : Color(red: 0.25, green: 0.33, blue: 0.40)
    }

    static func tertiaryText(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? .white.opacity(0.44)
            : Color(red: 0.45, green: 0.52, blue: 0.60)
    }

    static func cardBackground(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color.white.opacity(0.095),
                    Color(red: 0.018, green: 0.045, blue: 0.065).opacity(0.94),
                    Color(red: 0.035, green: 0.14, blue: 0.13).opacity(0.24)
                ]
                : [
                    Color.white.opacity(0.98),
                    Color(red: 0.93, green: 0.98, blue: 1.00).opacity(0.95),
                    Color(red: 0.74, green: 0.92, blue: 0.96).opacity(0.30)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func cardBorder(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    .white.opacity(0.22),
                    accent(for: colorScheme).opacity(0.24),
                    .black.opacity(0.20)
                ]
                : [
                    .white.opacity(0.96),
                    Color(red: 0.42, green: 0.70, blue: 0.78).opacity(0.30),
                    Color(red: 0.05, green: 0.17, blue: 0.22).opacity(0.08)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func controlBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? .white.opacity(0.065)
            : Color(red: 0.97, green: 0.995, blue: 1.00).opacity(0.90)
    }

    static func controlBorder(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? .white.opacity(0.10)
            : Color(red: 0.25, green: 0.50, blue: 0.58).opacity(0.18)
    }

    static func accent(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.42, green: 0.84, blue: 1.00)
            : Color(red: 0.00, green: 0.42, blue: 0.52)
    }

    static func accentSoft(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.20, green: 0.88, blue: 0.80).opacity(0.12)
            : Color(red: 0.72, green: 0.93, blue: 0.96).opacity(0.32)
    }

    static func positive(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.28, green: 0.92, blue: 0.66)
            : Color(red: 0.00, green: 0.48, blue: 0.34)
    }

    static func warning(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 1.00, green: 0.60, blue: 0.32)
            : Color(red: 0.78, green: 0.31, blue: 0.08)
    }

    static func negative(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 1.00, green: 0.39, blue: 0.42)
            : Color(red: 0.78, green: 0.09, blue: 0.18)
    }
}

private struct LabModuleBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            PulsarSectionBackground()

            LinearGradient(
                colors: backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }

    private var backgroundColors: [Color] {
        if colorScheme == .dark {
            [
                Color(red: 0.015, green: 0.060, blue: 0.075).opacity(0.96),
                Color.black.opacity(0.88),
                Color(red: 0.055, green: 0.115, blue: 0.165).opacity(0.92),
                Color(red: 0.035, green: 0.13, blue: 0.11).opacity(0.48)
            ]
        } else {
            [
                Color(red: 0.93, green: 0.985, blue: 1.00).opacity(0.98),
                Color.white.opacity(0.98),
                Color(red: 0.88, green: 0.965, blue: 1.00).opacity(0.86),
                Color(red: 0.80, green: 0.94, blue: 0.91).opacity(0.46)
            ]
        }
    }
}

private struct LabGlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let glow: Color
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LabPalette.cardBackground(for: colorScheme))
            }
            .pulsarLiquidGlass(cornerRadius: cornerRadius)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(LabPalette.cardBorder(for: colorScheme), lineWidth: 1)
            }
            .shadow(color: glow, radius: colorScheme == .dark ? 20 : 12, x: 0, y: colorScheme == .dark ? 12 : 7)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.06), radius: colorScheme == .dark ? 16 : 12, x: 0, y: colorScheme == .dark ? 10 : 7)
    }
}

private struct LabStaggeredAppearanceModifier: ViewModifier {
    let isVisible: Bool
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : 16)
            .animation(
                reduceMotion ? nil : .spring(response: 0.54, dampingFraction: 0.88).delay(Double(index) * 0.042),
                value: isVisible
            )
    }
}

private extension View {
    func labGlassCard(cornerRadius: CGFloat, glow: Color) -> some View {
        modifier(LabGlassCardModifier(cornerRadius: cornerRadius, glow: glow))
    }

    func labStaggered(isVisible: Bool, index: Int) -> some View {
        modifier(LabStaggeredAppearanceModifier(isVisible: isVisible, index: index))
    }
}

private extension LabPillarKind {
    var labSymbol: String {
        switch self {
        case .physiological:
            return "figure.run.circle"
        case .lifestyle:
            return "leaf.circle"
        case .biomarkers:
            return "testtube.2"
        }
    }
}

private extension LabBiomarkerStatus {
    var labTint: Color {
        labTint(for: .dark)
    }

    func labTint(for colorScheme: ColorScheme) -> Color {
        switch self {
        case .optimal:
            return LabPalette.positive(for: colorScheme)
        case .normal:
            return LabPalette.accent(for: colorScheme)
        case .high:
            return LabPalette.warning(for: colorScheme)
        case .low:
            return colorScheme == .dark
                ? Color(red: 0.72, green: 0.62, blue: 1.0)
                : Color(red: 0.35, green: 0.28, blue: 0.72)
        case .missing:
            return LabPalette.tertiaryText(for: colorScheme)
        }
    }
}

private extension Double {
    var formattedOneDecimal: String {
        String(format: "%.1f", self)
    }
}

private var labPreviewBiologicalAgeResult: BiologicalAgeResult {
    let now = Date()
    return BiologicalAgeResult(
        biologicalAge: 22.9,
        chronologicalAge: 23.0,
        ageDelta: -0.1,
        paceOfAging: 0.99,
        confidence: .medium,
        updatedAt: now,
        nextUpdateAt: Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now,
        physiologicalScore: 88,
        lifestyleScore: nil,
        biomarkerScore: 82,
        physiologicalContributionYears: -0.2,
        lifestyleContributionYears: 0,
        biomarkerContributionYears: 0.1,
        missingDataMessages: ["Complete lifestyle check-ins to improve the estimate."],
        wearableDataDays: 24,
        recentBiomarkerCount: 6,
        lifestyleSurveyCompleted: false
    )
}

#Preview("Lab - Light") {
    LabView(profileStore: ProfileStore(sideEffectsEnabled: false), startsVisible: true)
        .preferredColorScheme(.light)
}

#Preview("Lab - Dark") {
    LabView(profileStore: ProfileStore(sideEffectsEnabled: false), startsVisible: true)
        .preferredColorScheme(.dark)
}

#Preview("Biological Age Hero - Light") {
    ScrollView {
        LabBiologicalAgeHeroView(result: labPreviewBiologicalAgeResult, startsSettled: true)
            .padding(18)
    }
    .background(LabModuleBackground())
    .preferredColorScheme(.light)
}

#Preview("Biological Age Hero - Dark") {
    ScrollView {
        LabBiologicalAgeHeroView(result: labPreviewBiologicalAgeResult, startsSettled: true)
            .padding(18)
    }
    .background(LabModuleBackground())
    .preferredColorScheme(.dark)
}
