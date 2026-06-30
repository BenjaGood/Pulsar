//
//  CycleView.swift
//  Pulsar
//

import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
struct CycleView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let onClose: (() -> Void)?
    @StateObject private var trackingStore: CycleTrackingStore
    @State private var selectedDate: Date
    @State private var showsModelDetails = true
    @State private var activeSheet: CycleActiveSheet?

    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
        let trackingStore = CycleTrackingStore()
        _trackingStore = StateObject(wrappedValue: trackingStore)
        _selectedDate = State(initialValue: trackingStore.today)
    }

    init(trackingStore: CycleTrackingStore, onClose: (() -> Void)? = nil) {
        self.onClose = onClose
        _trackingStore = StateObject(wrappedValue: trackingStore)
        _selectedDate = State(initialValue: trackingStore.today)
    }

    private var model: CycleViewModel {
        CycleInferenceEngine.makeViewModel(
            trackingState: trackingStore.state,
            today: trackingStore.today,
            selectedDate: selectedDate
        )
    }

    private var summary: CycleTrackingSummary {
        trackingStore.summary
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    CycleHeader()

                    if trackingStore.hasCycleData {
                        CycleHeroCard(model: model)

                        CycleWhyTodayRow(model: model) {
                            CycleHaptics.selection()
                            withAnimation(selectionAnimation) {
                                showsModelDetails = true
                            }
                        }

                        CycleTodayStatusCard(
                            model: model,
                            summary: summary,
                            onLogToday: {
                                CycleHaptics.selection()
                                activeSheet = .dailyLog(selectedDate)
                            }
                        )

                        CycleTrackingSummaryCard(
                            summary: summary,
                            onLogBleeding: {
                                CycleHaptics.selection()
                                activeSheet = .logBleeding
                            },
                            onEdit: {
                                CycleHaptics.selection()
                                activeSheet = .editCycleData
                            }
                        )

                        CycleDayStrip(
                            days: model.days,
                            selectedDate: selectedDate,
                            onSelectDate: { date in
                                CycleHaptics.selection()
                                withAnimation(selectionAnimation) {
                                    selectedDate = date
                                }
                            }
                        )

                        CyclePredictionsCard(summary: summary)

                        CycleRecommendationSection(recommendations: model.recommendations)

                        CycleHistorySection(summary: summary)

                        CycleTrendsSection(model: model)

                        CycleDataConfidenceCard(summary: summary)

                        CycleModelDetailsCard(
                            day: model.selectedDay,
                            inputs: model.selectedInputs,
                            isExpanded: $showsModelDetails
                        )
                    } else {
                        CycleOnboardingCard(trackingStore: trackingStore) {
                            selectedDate = trackingStore.today
                        }
                    }

                    CycleDisclaimer()

                    CyclePrivacyNote()
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 42)
            }
            .safeAreaPadding(.bottom, 16)
            .safeAreaInset(edge: .top, spacing: 0) {
                CycleTopBar(
                    onClose: onClose,
                    showsLogButton: trackingStore.hasCycleData,
                    onLogBleeding: {
                        CycleHaptics.selection()
                        activeSheet = .logBleeding
                    }
                )
            }
            .background(CycleModuleBackground())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .logBleeding:
                    CycleBleedingLogSheet(trackingStore: trackingStore, initialMonth: selectedDate)
                case .editCycleData:
                    CycleEditCycleDataSheet(trackingStore: trackingStore)
                case .dailyLog(let date):
                    CycleDailyLogSheet(trackingStore: trackingStore, date: date)
                }
            }
        }
    }

    private var selectionAnimation: Animation? {
        reduceMotion ? .easeInOut(duration: 0.16) : .spring(response: 0.34, dampingFraction: 0.84)
    }
}

private enum CycleActiveSheet: Identifiable {
    case logBleeding
    case editCycleData
    case dailyLog(Date)

    var id: String {
        switch self {
        case .logBleeding: "logBleeding"
        case .editCycleData: "editCycleData"
        case .dailyLog(let date): "dailyLog-\(CycleTrackingCalculator.dateKey(for: date))"
        }
    }
}

private struct CycleTopBar: View {
    let onClose: (() -> Void)?
    let showsLogButton: Bool
    let onLogBleeding: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            if let onClose {
                CycleToolbarGlassButton(
                    systemName: "xmark",
                    pointSize: 27,
                    weight: .regular,
                    accessibilityLabel: "Close Cycle",
                    action: onClose
                )
            } else {
                Color.clear
                    .frame(width: 58, height: 58)
            }

            Spacer(minLength: 12)

            Text("Cycle")
                .pulsarTextStyle(.sectionHeader)
                .foregroundStyle(.white.opacity(0.96))
                .shadow(color: .black.opacity(0.16), radius: 8, y: 4)

            Spacer(minLength: 12)

            if showsLogButton {
                CycleToolbarGlassButton(
                    systemName: "calendar.badge.plus",
                    pointSize: 24,
                    weight: .semibold,
                    accessibilityLabel: "Log bleeding",
                    action: onLogBleeding
                )
            } else {
                Color.clear
                    .frame(width: 58, height: 58)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(alignment: .top) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.012, green: 0.020, blue: 0.046).opacity(0.24),
                            Color(red: 0.026, green: 0.032, blue: 0.060).opacity(0.12),
                            Color.black.opacity(0.03),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 148)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0.0),
                            .init(color: .black.opacity(0.98), location: 0.62),
                            .init(color: .black.opacity(0.56), location: 0.78),
                            .init(color: .black.opacity(0.0), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .zIndex(10)
    }
}

private struct CycleToolbarGlassButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isPressed = false

    let systemName: String
    let pointSize: CGFloat
    let weight: Font.Weight
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        CycleToolbarGlassIcon(systemName: systemName, pointSize: pointSize, weight: weight)
            .scaleEffect(isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.24, dampingFraction: 0.78), value: isPressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, state, _ in
                        state = true
                    }
                    .onEnded { _ in
                        action()
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(accessibilityLabel))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                action()
            }
    }
}

private struct CycleToolbarGlassIcon: View {
    @Environment(\.colorScheme) private var colorScheme

    let systemName: String
    let pointSize: CGFloat
    let weight: Font.Weight

    var body: some View {
        let shape = Circle()

        Image(systemName: systemName)
            .font(.system(size: pointSize, weight: weight))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.white.opacity(0.95))
            .frame(width: 56, height: 56)
            .background(.ultraThinMaterial, in: shape)
            .background(CyclePalette.toolbarGlassFill(for: colorScheme), in: shape)
            .overlay {
                shape
                    .stroke(CyclePalette.toolbarGlassBorder(for: colorScheme), lineWidth: 0.85)
            }
            .overlay(alignment: .topLeading) {
                shape
                    .stroke(.white.opacity(colorScheme == .dark ? 0.18 : 0.48), lineWidth: 0.6)
                    .blur(radius: 0.6)
                    .mask(
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.14 : 0.07), radius: 14, y: 8)
            .contentShape(shape)
            .cycleNativeGlass(shape: shape, tintOpacity: 0.055, isInteractive: true)
    }
}

private struct CycleHeader: View {
    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Image(systemName: "moonphase.waxing.crescent")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(CyclePalette.phase(.luteal).accent)
                .frame(width: 64, height: 64)
                .background(.ultraThinMaterial, in: Circle())
                .background(CyclePalette.logoGlassFill, in: Circle())
                .overlay {
                    Circle()
                        .stroke(CyclePalette.toolbarGlassBorder(for: .dark), lineWidth: 0.9)
                }
                .overlay(alignment: .topLeading) {
                    Circle()
                        .stroke(.white.opacity(0.26), lineWidth: 0.7)
                        .blur(radius: 0.5)
                        .mask(
                            LinearGradient(
                                colors: [.white, .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
                .cycleNativeGlass(shape: Circle(), tintOpacity: 0.060)

            VStack(alignment: .leading, spacing: 6) {
                Text("Cycle")
                    .pulsarTextStyle(.displayLarge)
                    .foregroundStyle(.white.opacity(0.97))
                Text("Track your cycle, symptoms, phases, and wellness trends.")
                    .pulsarTextStyle(.label)
                    .foregroundStyle(CyclePalette.softText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct CycleHeroCard: View {
    let model: CycleViewModel

    private var day: CycleDayModel { model.selectedDay }
    private var token: CyclePhaseToken { CyclePalette.phase(day.estimate.phase) }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Estimated phase")
                        .pulsarTextStyle(.captionEmphasis)
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.78))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                        .background(CyclePalette.pillGlassFill, in: Capsule(style: .continuous))
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(.white.opacity(0.14), lineWidth: 0.8)
                        }
                        .cycleNativeGlass(shape: Capsule(style: .continuous), tintOpacity: 0.040)

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(model.displayPhaseName)
                            .pulsarTextStyle(.displayLarge)
                            .foregroundStyle(.white.opacity(0.96))
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)

                        CycleConfidenceChip(estimate: day.estimate)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(token.subtitle)
                        .pulsarTextStyle(.label)
                        .foregroundStyle(CyclePalette.softText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                CyclePhaseRing(
                    phase: day.estimate.phase,
                    cycleDay: day.cycleDay,
                    predictedCycleLength: model.predictedCycleLength,
                    progress: model.phaseProgress
                )
                .frame(width: 132, height: 132)
                .accessibilityLabel("Cycle phase progress")
                .accessibilityValue("Day \(day.cycleDay) of about \(model.predictedCycleLength), \(model.displayPhaseName)")
            }

            HStack(spacing: 10) {
                CycleHeroMetric(title: "Cycle day", value: "\(day.cycleDay)", symbolName: "calendar")
                CycleHeroMetric(title: "Next event", value: model.nextEvent, symbolName: "sparkles")
            }
        }
        .padding(22)
        .cycleCard(cornerRadius: 32)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.displayPhaseName), estimate strength \(day.estimate.confidenceLabel.rawValue.lowercased()), cycle day \(day.cycleDay). \(model.nextEvent).")
    }
}

private struct CycleWhyTodayRow: View {
    let model: CycleViewModel
    var onTap: () -> Void

    private var day: CycleDayModel { model.selectedDay }
    private var token: CyclePhaseToken { CyclePalette.phase(day.estimate.phase) }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: "sun.horizon.fill")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 46, height: 46)
                    .background(.ultraThinMaterial, in: Circle())
                    .background(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.12),
                                CyclePalette.premiumGlassAccent.opacity(0.08),
                                token.accent.opacity(0.11)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Circle()
                    )
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.24), lineWidth: 0.8)
                    }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Why today?")
                        .pulsarTextStyle(.captionEmphasis)
                        .textCase(.uppercase)
                        .foregroundStyle(CyclePalette.chartAccent.opacity(0.92))
                    Text(day.estimate.evidenceSummary.prefix(1).joined(separator: " • "))
                        .pulsarTextStyle(.cardTitle)
                        .foregroundStyle(CyclePalette.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cycleGlassSurface(cornerRadius: 30, tintOpacity: 0.055, isInteractive: true)
        }
        .buttonStyle(CyclePressButtonStyle())
        .accessibilityElement(children: .combine)
    }
}

private struct CycleConfidenceChip: View {
    let estimate: PhaseEstimate

    var body: some View {
        Label {
            Text(estimate.confidenceLabel.rawValue)
                .pulsarTextStyle(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        } icon: {
            Image(systemName: estimate.confidenceLabel.symbolName)
                .pulsarTextStyle(.overline)
        }
        .foregroundStyle(CyclePalette.primaryText.opacity(0.90))
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(CyclePalette.calendarMarkerFill(isSelected: true), in: Capsule(style: .continuous))
        .cycleNativeGlass(shape: Capsule(style: .continuous), tintOpacity: 0.07, isInteractive: false)
        .overlay {
            Capsule(style: .continuous)
                .stroke(.white.opacity(0.24), lineWidth: 1)
        }
        .accessibilityLabel("Estimate strength \(estimate.confidenceLabel.rawValue)")
    }
}

private struct CycleHeroMetric: View {
    let title: String
    let value: String
    let symbolName: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(CyclePalette.chartAccent.opacity(0.95))
                .frame(width: 38, height: 38)
                .background(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color(red: 0.035, green: 0.050, blue: 0.086).opacity(0.34),
                            CyclePalette.premiumGlassAccent.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.22), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .pulsarTextStyle(.captionEmphasis)
                    .textCase(.uppercase)
                    .foregroundStyle(CyclePalette.softText)
                    .lineLimit(1)
                Text(value)
                    .pulsarTextStyle(title == "Next event" ? .bodyEmphasis : .metricMedium)
                    .foregroundStyle(CyclePalette.primaryText)
                    .lineLimit(3)
                    .minimumScaleFactor(0.78)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cycleGlassSurface(cornerRadius: 20, tintOpacity: 0.045)
        .accessibilityElement(children: .combine)
    }
}

private struct CycleTodayStatusCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let model: CycleViewModel
    let summary: CycleTrackingSummary
    var onLogToday: () -> Void

    private var day: CycleDayModel { model.selectedDay }
    private var token: CyclePhaseToken { CyclePalette.phase(day.estimate.phase) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image("CycleLeaf")
                .resizable()
                .scaledToFit()
                .frame(width: 188)
                .opacity(0.34)
                .saturation(0.82)
                .offset(x: 58, y: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(.white.opacity(0.94))
                        .frame(width: 56, height: 56)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.18),
                                    CyclePalette.premiumGlassAccent.opacity(0.14),
                                    CyclePalette.premiumGlassAccent.opacity(0.20)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Circle()
                        )
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.30), lineWidth: 1)
                        }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Today's status")
                            .pulsarTextStyle(.sectionHeader)
                            .foregroundStyle(CyclePalette.primaryText)
                        Text(statusText)
                            .pulsarTextStyle(.label)
                            .foregroundStyle(CyclePalette.softText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 72)
                }

                HStack(spacing: 12) {
                    CycleStatusChip(title: "Phase", value: CyclePalette.phase(day.estimate.phase).name, symbolName: "moonphase.waxing.crescent", tint: token.accent)
                    CycleStatusChip(title: "Strength", value: day.estimate.confidenceLabel.rawValue, symbolName: "gauge.with.dots.needle.bottom.50percent", tint: token.accent)
                }

                Button {
                    onLogToday()
                } label: {
                    Label("Log symptoms", systemImage: "list.clipboard.fill")
                        .pulsarTextStyle(.buttonTitle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(CyclePalette.primaryText)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.14),
                                    CyclePalette.premiumGlassAccent.opacity(0.12),
                                    Color(red: 0.045, green: 0.055, blue: 0.090).opacity(0.26)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Capsule(style: .continuous)
                        )
                        .cycleNativeGlass(shape: Capsule(style: .continuous), tintOpacity: 0.09, isInteractive: true)
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(CyclePalette.glassBorder(for: colorScheme), lineWidth: 1)
                        }
                }
                .buttonStyle(CyclePressButtonStyle())
            }
            .padding(22)
            .zIndex(1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .cycleCard(cornerRadius: 32)
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        let cycleDay = summary.currentCycleDay.map { "cycle day \($0)" } ?? "your current cycle day"
        return "Estimated from logged bleeding and symptoms. You are on \(cycleDay); recommendations flex with today's symptoms, sleep, and energy."
    }
}

private struct CycleStatusChip: View {
    let title: String
    let value: String
    let symbolName: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                .frame(width: 44, height: 44)
                .background(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.14),
                            CyclePalette.premiumGlassAccent.opacity(0.10),
                            Color.black.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .pulsarTextStyle(.overline)
                    .textCase(.uppercase)
                    .foregroundStyle(CyclePalette.softText)
                Text(value)
                    .pulsarTextStyle(.cardTitle)
                    .foregroundStyle(title == "Phase" ? CyclePalette.chartAccent.opacity(0.98) : CyclePalette.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cycleGlassSurface(cornerRadius: 22, tintOpacity: 0.07)
    }
}

private struct CycleOnboardingCard: View {
    @ObservedObject var trackingStore: CycleTrackingStore
    var onSaved: () -> Void

    @State private var lastPeriodStartDate: Date
    @State private var averagePeriodLength = 5
    @State private var averageCycleLength = 28

    init(trackingStore: CycleTrackingStore, onSaved: @escaping () -> Void) {
        self.trackingStore = trackingStore
        self.onSaved = onSaved
        _lastPeriodStartDate = State(initialValue: trackingStore.today)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "calendar.badge.plus")
                    .pulsarTextStyle(.sectionHeader)
                    .foregroundStyle(CyclePalette.phase(.menstrual).accent)
                    .frame(width: 46, height: 46)
                    .background(CyclePalette.phase(.menstrual).tint, in: Circle())

                VStack(alignment: .leading, spacing: 6) {
                    Text("Set up cycle tracking")
                        .pulsarTextStyle(.title)
                    Text("Start with the first day of your most recent period. Pulsar will use bleeding days as the foundation for estimates.")
                        .pulsarTextStyle(.label)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 12) {
                CycleDatePickerRow(
                    title: "When did your last period start?",
                    selection: $lastPeriodStartDate
                )

                CycleStepperRow(
                    title: "Bleeding lasted",
                    value: $averagePeriodLength,
                    range: 1...14,
                    suffix: "days"
                )

                CycleStepperRow(
                    title: "Average cycle length",
                    value: $averageCycleLength,
                    range: 15...90,
                    suffix: "days"
                )
            }

            Button {
                CycleHaptics.success()
                trackingStore.completeOnboarding(
                    lastPeriodStartDate: lastPeriodStartDate,
                    averagePeriodLength: averagePeriodLength,
                    averageCycleLength: averageCycleLength
                )
                onSaved()
            } label: {
                Label("Save and start tracking", systemImage: "checkmark.circle.fill")
                    .pulsarTextStyle(.label)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        LinearGradient(
                            colors: [
                                CyclePalette.phase(.menstrual).accent,
                                CyclePalette.phase(.luteal).accent
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: Capsule(style: .continuous)
                    )
            }
            .buttonStyle(CyclePressButtonStyle())

            Text("Predictions improve as you log more cycles.")
                .pulsarTextStyle(.metadata)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .cycleCard(cornerRadius: 30)
    }
}

private struct CycleTrackingSummaryCard: View {
    let summary: CycleTrackingSummary
    var onLogBleeding: () -> Void
    var onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cycle data")
                        .pulsarTextStyle(.cardTitle)
                    Text("History, baselines, and estimated timing.")
                        .pulsarTextStyle(.metadata)
                        .foregroundStyle(CyclePalette.secondaryText)
                }

                Spacer(minLength: 8)

                Menu {
                    Button("Edit cycle data", systemImage: "slider.horizontal.3") {
                        onEdit()
                    }
                    Button("Log bleeding", systemImage: "drop.fill") {
                        onLogBleeding()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .pulsarTextStyle(.label)
                        .foregroundStyle(CyclePalette.secondaryText)
                        .frame(width: 34, height: 34)
                        .background(CyclePalette.calendarMarkerFill(isSelected: false), in: Circle())
                        .cycleNativeGlass(shape: Circle(), tintOpacity: 0.055, isInteractive: true)
                }
                .accessibilityLabel("Cycle data options")
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 142), spacing: 10)], spacing: 10) {
                CycleSummaryMetric(title: "Current cycle day", value: summary.currentCycleDay.map(String.init) ?? "Not enough data")
                CycleSummaryMetric(title: "Period started", value: summary.latestCycleStartDate?.monthDayText ?? "Not logged")
                CycleSummaryMetric(title: "Next period estimated", value: summary.estimatedNextPeriodDate?.monthDayText ?? "Not enough data")
                CycleSummaryMetric(title: "Estimate strength", value: summary.predictionConfidence.rawValue)
            }

            HStack(spacing: 10) {
                Button {
                    onLogBleeding()
                } label: {
                    Label("Log bleeding", systemImage: "drop.fill")
                        .pulsarTextStyle(.label)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            LinearGradient(
                                colors: [
                                    CyclePalette.premiumRose.opacity(0.18),
                                    Color.white.opacity(0.10),
                                    Color.black.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Capsule(style: .continuous)
                        )
                        .cycleNativeGlass(shape: Capsule(style: .continuous), tintOpacity: 0.07, isInteractive: true)
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(CyclePalette.premiumRose.opacity(0.34), lineWidth: 1)
                        }
                        .foregroundStyle(Color(red: 0.98, green: 0.58, blue: 0.62))
                }
                .buttonStyle(CyclePressButtonStyle())

                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "slider.horizontal.3")
                        .pulsarTextStyle(.label)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(CyclePalette.calendarMarkerFill(isSelected: false), in: Capsule(style: .continuous))
                        .cycleNativeGlass(shape: Capsule(style: .continuous), tintOpacity: 0.055, isInteractive: true)
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(.white.opacity(0.14), lineWidth: 1)
                        }
                        .foregroundStyle(CyclePalette.primaryText)
                }
                .buttonStyle(CyclePressButtonStyle())
            }

            if let ovulationStart = summary.estimatedOvulationStart,
               let ovulationEnd = summary.estimatedOvulationEnd,
               let fertileStart = summary.estimatedFertileWindowStart,
               let fertileEnd = summary.estimatedFertileWindowEnd {
                Text("Estimated ovulation window: \(ovulationStart.monthDayText)-\(ovulationEnd.monthDayText). Fertile window estimate: \(fertileStart.monthDayText)-\(fertileEnd.monthDayText). Estimate only, not birth control.")
                    .pulsarTextStyle(.metadata)
                    .foregroundStyle(CyclePalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .cycleCard(cornerRadius: 26)
    }
}

private struct CycleSummaryMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(CyclePalette.tertiaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
            Text(value)
                .pulsarTextStyle(.label)
                .foregroundStyle(CyclePalette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cycleReadablePanel(cornerRadius: 18)
        .accessibilityElement(children: .combine)
    }
}

private struct CyclePredictionsCard: View {
    let summary: CycleTrackingSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "calendar.badge.clock")
                    .pulsarTextStyle(.cardTitle)
                    .foregroundStyle(CyclePalette.premiumGold)
                    .frame(width: 38, height: 38)
                    .background(CyclePalette.calendarMarkerFill(isSelected: false), in: Circle())
                    .cycleNativeGlass(shape: Circle(), tintOpacity: 0.055)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Predictions")
                        .pulsarTextStyle(.cardTitle)
                    Text("Estimated from your logged history. Dates can shift when cycles vary or logs are limited.")
                        .pulsarTextStyle(.metadata)
                        .foregroundStyle(CyclePalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                CycleSummaryMetric(title: "Next period", value: summary.estimatedNextPeriodDate?.monthDayText ?? "More logs needed")
                CycleSummaryMetric(title: "Ovulation window", value: dateRange(summary.estimatedOvulationStart, summary.estimatedOvulationEnd))
                CycleSummaryMetric(title: "Fertile window", value: dateRange(summary.estimatedFertileWindowStart, summary.estimatedFertileWindowEnd))
                CycleSummaryMetric(title: "Typical cycle", value: "\(summary.averageCycleLength) days")
            }

            Text("Fertile-window estimates are wellness context only and should not be used as contraception.")
                .pulsarTextStyle(.metadata)
                .foregroundStyle(CyclePalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .cycleCard(cornerRadius: 26)
    }

    private func dateRange(_ start: Date?, _ end: Date?) -> String {
        guard let start, let end else { return "More logs needed" }
        if CycleDate.isSameDay(start, end) { return start.monthDayText }
        return "\(start.monthDayText)-\(end.monthDayText)"
    }
}

private struct CycleHistorySection: View {
    let summary: CycleTrackingSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline) {
                Text("Cycle history")
                    .pulsarTextStyle(.cardTitle)
                Spacer()
                Text("\(summary.cycleRecords.count) logged")
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(CyclePalette.secondaryText)
            }
            .padding(.horizontal, 2)

            VStack(spacing: 10) {
                ForEach(Array(summary.cycleRecords.suffix(4).reversed())) { record in
                    CycleHistoryRow(record: record)
                }
            }
        }
    }
}

private struct CycleHistoryRow: View {
    let record: CycleRecord

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.period.startDate.monthDayText)
                    .pulsarTextStyle(.label)
                Text(periodSummary)
                    .pulsarTextStyle(.metadata)
                    .foregroundStyle(CyclePalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Text(record.length.map { "\($0)d cycle" } ?? "Current")
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(CyclePalette.secondaryText)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(CyclePalette.calendarMarkerFill(isSelected: false), in: Capsule(style: .continuous))
        }
        .padding(14)
        .cycleCard(cornerRadius: 22)
    }

    private var periodSummary: String {
        let bleeding = "\(record.period.dayCount) bleeding day\(record.period.dayCount == 1 ? "" : "s")"
        let symptoms = record.symptoms.isEmpty ? "no symptoms logged" : "\(record.symptoms.count) symptom log\(record.symptoms.count == 1 ? "" : "s")"
        return "\(bleeding), \(symptoms)"
    }
}

private struct CycleDataConfidenceCard: View {
    let summary: CycleTrackingSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("Data confidence")
                    .pulsarTextStyle(.cardTitle)
                    .foregroundStyle(.white.opacity(0.96))
            } icon: {
                Image(systemName: summary.predictionConfidence.symbolName)
                    .foregroundStyle(CyclePalette.phase(.follicular).accent)
            }

            Text(confidenceText)
                .pulsarTextStyle(.label)
                .foregroundStyle(CyclePalette.softText)
                .fixedSize(horizontal: false, vertical: true)

            if let notice = summary.cyclePatternNotice {
                Text(notice)
                    .pulsarTextStyle(.metadata)
                    .foregroundStyle(CyclePalette.phase(.menstrual).accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .cycleCard(cornerRadius: 26)
    }

    private var confidenceText: String {
        let sampleText = summary.cycleLengthSamples.isEmpty
            ? "No complete cycle intervals yet"
            : "\(summary.cycleLengthSamples.count) interval\(summary.cycleLengthSamples.count == 1 ? "" : "s") used"
        let variabilityText = summary.cycleLengthVariability.map { ", \($0)d spread" } ?? ""
        return "\(summary.predictionConfidence.rawValue) estimate strength. \(sampleText)\(variabilityText). Baseline: \(summary.baselineCycleLength)d cycles, \(summary.baselinePeriodLength)d periods."
    }
}

private struct CycleDatePickerRow: View {
    let title: String
    @Binding var selection: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .pulsarTextStyle(.label)
            DatePicker(title, selection: $selection, displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct CycleStepperRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let suffix: String

    var body: some View {
        Stepper(value: $value, in: range) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .pulsarTextStyle(.label)
                Spacer()
                Text("\(value) \(suffix)")
                    .pulsarTextStyle(.label)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(14)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct CyclePhaseRing: View {
    let phase: CyclePhase
    let cycleDay: Int
    let predictedCycleLength: Int
    let progress: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedProgress = 0.0

    private var token: CyclePhaseToken { CyclePalette.phase(phase) }

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)

            ZStack {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.34),
                                Color.white.opacity(0.12),
                                token.accent.opacity(0.22)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .accessibilityHidden(true)

                Circle()
                    .trim(from: 0, to: CGFloat(displayedProgress))
                    .stroke(
                        LinearGradient(
                            colors: [
                                token.accent.opacity(0.92),
                                CyclePalette.chartAccent.opacity(0.72),
                                Color.white.opacity(0.36)
                            ],
                            startPoint: .bottomLeading,
                            endPoint: .topTrailing
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: token.accent.opacity(0.18), radius: 8, y: 3)
                    .accessibilityHidden(true)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.96),
                                CyclePalette.chartAccent.opacity(0.88)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 16, height: 16)
                    .shadow(color: token.accent.opacity(0.28), radius: 6, y: 2)
                    .offset(progressDotOffset(diameter: diameter))
                    .accessibilityHidden(true)

                VStack(spacing: 1) {
                    Text("\(cycleDay)")
                        .pulsarTextStyle(.metricLarge)
                        .foregroundStyle(.white.opacity(0.96))
                        .monospacedDigit()
                    Text("day")
                        .pulsarTextStyle(.overline)
                        .textCase(.uppercase)
                        .foregroundStyle(CyclePalette.softText)
                    Text(token.marker)
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(token.accent.opacity(0.95))
                }
                .minimumScaleFactor(0.78)
            }
            .frame(width: diameter, height: diameter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            displayedProgress = progress
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(reduceMotion ? .easeInOut(duration: 0.18) : .easeInOut(duration: 0.72)) {
                displayedProgress = newValue
            }
        }
    }

    private func progressDotOffset(diameter: CGFloat) -> CGSize {
        let radius = diameter / 2 - 6
        let angle = displayedProgress * 2 * Double.pi - Double.pi / 2
        return CGSize(
            width: CGFloat(cos(angle)) * radius,
            height: CGFloat(sin(angle)) * radius
        )
    }
}

private struct CycleDayStrip: View {
    let days: [CycleDayModel]
    let selectedDate: Date
    let onSelectDate: (Date) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline) {
                Text("Daily view")
                    .pulsarTextStyle(.cardTitle)
                Spacer()
                Text("14+ days")
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(CyclePalette.secondaryText)
            }
            .padding(.horizontal, 2)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(days) { day in
                            Button {
                                onSelectDate(day.date)
                            } label: {
                                CycleDayCell(day: day, isSelected: day.date == selectedDate)
                            }
                            .buttonStyle(CyclePressButtonStyle())
                            .id(day.date)
                            .accessibilityLabel(day.accessibilityLabel)
                            .accessibilityValue("Estimate strength \(day.estimate.confidenceLabel.rawValue)")
                            .accessibilityHint("Selects this day and updates recommendations, trends, and model rationale.")
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                }
                .onAppear {
                    proxy.scrollTo(selectedDate, anchor: .center)
                }
                .onChange(of: selectedDate) { _, newValue in
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.16) : .spring(response: 0.34, dampingFraction: 0.86)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
    }
}

private struct CycleDayCell: View {
    let day: CycleDayModel
    let isSelected: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var token: CyclePhaseToken { CyclePalette.phase(day.estimate.phase) }

    var body: some View {
        VStack(spacing: 6) {
            Text(day.weekdayText)
                .pulsarTextStyle(.overline)
                .textCase(.uppercase)
                .foregroundStyle(isSelected ? CyclePalette.primaryText.opacity(0.90) : CyclePalette.secondaryText)

            Text(day.dayNumberText)
                .pulsarTextStyle(.metricMedium)
                .foregroundStyle(CyclePalette.primaryText)
                .monospacedDigit()

            VStack(spacing: 3) {
                Text(token.marker)
                    .pulsarTextStyle(.overline)
                    .foregroundStyle(isSelected ? CyclePalette.primaryText : CyclePalette.chartAccent.opacity(0.92))
                    .frame(width: 24, height: 24)
                    .background(CyclePalette.calendarMarkerFill(isSelected: isSelected), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(isSelected ? CyclePalette.chartAccent.opacity(0.50) : .white.opacity(0.14), lineWidth: 1)
                    }

                if day.isToday {
                    Text("Today")
                        .pulsarTextStyle(.overline)
                        .foregroundStyle(isSelected ? CyclePalette.primaryText.opacity(0.88) : CyclePalette.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }

            HStack(spacing: 3) {
                ForEach(day.markers.prefix(3)) { marker in
                    Text(marker.shortLabel)
                        .font(.system(size: 7, weight: .semibold, design: .rounded))
                        .foregroundStyle(CyclePalette.primaryText.opacity(0.82))
                        .frame(minWidth: 15, minHeight: 15)
                        .padding(.horizontal, 2)
                        .background(CyclePalette.calendarMarkerFill(isSelected: isSelected), in: Capsule(style: .continuous))
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 17)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(width: 66)
        .frame(minHeight: 124)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(CyclePalette.calendarCellFill(isSelected: isSelected))
        )
        .cycleNativeGlass(
            shape: RoundedRectangle(cornerRadius: 22, style: .continuous),
            tintOpacity: isSelected ? 0.085 : 0.045,
            isInteractive: true
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isSelected ? CyclePalette.chartAccent.opacity(0.64) : .white.opacity(0.14), lineWidth: isSelected ? 1.35 : 1)
        }
        .shadow(color: .black.opacity(isSelected ? 0.22 : 0.14), radius: isSelected ? 18 : 12, y: isSelected ? 10 : 7)
        .animation(reduceMotion ? .easeInOut(duration: 0.16) : .spring(response: 0.34, dampingFraction: 0.84), value: isSelected)
    }
}

private struct CycleRecommendationSection: View {
    let recommendations: DailyRecommendations

    private let columns = [
        GridItem(.adaptive(minimum: 230), spacing: 12, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline) {
                Text("Today's guidance")
                    .pulsarTextStyle(.cardTitle)
                Spacer()
                Text(recommendations.rationaleTags.joined(separator: " / "))
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(CyclePalette.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 2)

            LazyVGrid(columns: columns, spacing: 12) {
                CycleRecommendationCard(kind: .move, recommendation: recommendations.move)
                CycleRecommendationCard(kind: .fuel, recommendation: recommendations.fuel)
                CycleRecommendationCard(kind: .recover, recommendation: recommendations.recover)
            }
        }
    }
}

private struct CycleRecommendationCard: View {
    let kind: RecommendationKind
    let recommendation: Recommendation

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                Image(systemName: kind.symbolName)
                    .pulsarTextStyle(.label)
                    .foregroundStyle(kind.accent)
                    .frame(width: 32, height: 32)
                    .background(kind.tint, in: Circle())

                Text(kind.title)
                    .pulsarTextStyle(.captionEmphasis)
                    .textCase(.uppercase)
                    .foregroundStyle(CyclePalette.secondaryText)
            }

            Text(recommendation.title)
                .pulsarTextStyle(.cardTitle)
                .foregroundStyle(CyclePalette.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(recommendation.body)
                .pulsarTextStyle(.label)
                .foregroundStyle(CyclePalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cycleCard(cornerRadius: 24)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible || reduceMotion ? 0 : 8)
        .onAppear {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.14) : .easeOut(duration: 0.34)) {
                isVisible = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kind.title). \(recommendation.title). \(recommendation.body)")
    }
}

private struct CycleTrendsSection: View {
    let model: CycleViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline) {
                Text("Trends")
                    .pulsarTextStyle(.cardTitle)
                Spacer()
                Text("Signals and confidence")
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(CyclePalette.secondaryText)
            }
            .padding(.horizontal, 2)

            VStack(spacing: 12) {
                CycleChartCard(title: "Symptom trend", summary: model.chartSummary) {
                    CycleSymptomTrendChart(days: model.days.filter { $0.date <= model.today }.suffix(14).map { $0 })
                }

                CycleChartCard(title: "Phase confidence", summary: model.timelineSummary) {
                    CycleConfidenceTimeline(days: model.days)
                }
            }
        }
    }
}

private struct CycleChartCard<Chart: View>: View {
    let title: String
    let summary: String
    @ViewBuilder var chart: () -> Chart

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .pulsarTextStyle(.cardTitle)
            chart()
                .frame(height: 116)
            Text(summary)
                .pulsarTextStyle(.metadata)
                .foregroundStyle(CyclePalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .cycleCard(cornerRadius: 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(summary)")
    }
}

private struct CycleSymptomTrendChart: View {
    let days: [CycleDayModel]

    private var values: [Double] {
        days.map(\.symptomBurden)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let points = chartPoints(in: size)

            ZStack {
                VStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { _ in
                        Divider()
                            .overlay(CyclePalette.secondaryText.opacity(0.10))
                        Spacer(minLength: 0)
                    }
                }
                .accessibilityHidden(true)

                if points.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: size.height))
                        points.forEach { point in
                            path.addLine(to: point)
                        }
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: size.height))
                        path.closeSubpath()
                    }
                    .fill(CyclePalette.chartAreaFill)
                    .accessibilityHidden(true)

                    Path { path in
                        path.move(to: points[0])
                        points.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .stroke(CyclePalette.chartAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .accessibilityHidden(true)
                }

                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    Circle()
                        .fill(index == points.count - 1 ? CyclePalette.chartAccent : Color(red: 0.020, green: 0.026, blue: 0.046).opacity(0.92))
                        .stroke(CyclePalette.chartAccent.opacity(index == points.count - 1 ? 0.95 : 0.72), lineWidth: 1.5)
                        .frame(width: index == points.count - 1 ? 8 : 6, height: index == points.count - 1 ? 8 : 6)
                        .position(point)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func chartPoints(in size: CGSize) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let maxValue = 3.0
        let usableHeight = max(size.height - 18, 1)
        return values.enumerated().map { index, value in
            let denominator = max(values.count - 1, 1)
            let x = CGFloat(index) / CGFloat(denominator) * size.width
            let y = size.height - CGFloat(min(max(value, 0), maxValue) / maxValue) * usableHeight - 9
            return CGPoint(x: x, y: y)
        }
    }
}

private struct CycleConfidenceTimeline: View {
    let days: [CycleDayModel]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(days) { day in
                let token = CyclePalette.phase(day.estimate.phase)
                let height = CGFloat(max(26, 28 + day.estimate.confidence * 56))
                VStack(spacing: 2) {
                    Spacer(minLength: 0)
                    Text(token.marker)
                        .font(.system(size: 7, weight: .semibold, design: .rounded))
                        .foregroundStyle(day.isToday ? CyclePalette.primaryText : CyclePalette.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: height, alignment: .bottom)
                        .padding(.bottom, 4)
                        .background(CyclePalette.confidenceBarFill(isToday: day.isToday), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(CyclePalette.confidenceBarStroke(isToday: day.isToday), lineWidth: day.isToday ? 1.4 : 0.8)
                        }
                }
                .accessibilityLabel("\(day.monthDayText), \(token.name), estimate strength \(day.estimate.confidenceLabel.rawValue)")
            }
        }
    }
}

private struct CycleModelDetailsCard: View {
    let day: CycleDayModel
    let inputs: [CycleObservation]
    @Binding var isExpanded: Bool

    private var token: CyclePhaseToken { CyclePalette.phase(day.estimate.phase) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Model details")
                        .pulsarTextStyle(.cardTitle)
                        .foregroundStyle(.white.opacity(0.96))
                    Text("\(day.monthDayText) rationale and raw inputs")
                        .pulsarTextStyle(.metadata)
                        .foregroundStyle(CyclePalette.softText)
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Text(isExpanded ? "Hide" : "Show")
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .cycleGlassSurface(cornerRadius: 18, tintOpacity: 0.13, isInteractive: true)
                }
                .buttonStyle(CyclePressButtonStyle())
                .accessibilityLabel(isExpanded ? "Hide raw model inputs" : "Show raw model inputs")
                .accessibilityHint("Toggles the observations used by the cycle model.")
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(day.rationaleLines, id: \.self) { line in
                    Text(line)
                        .pulsarTextStyle(.label)
                        .foregroundStyle(.white.opacity(0.94))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cycleReadablePanel(cornerRadius: 20)

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(inputs) { input in
                        CycleRawInputRow(input: input)
                        if input.id != inputs.last?.id {
                            Divider()
                                .overlay(CyclePalette.secondaryText.opacity(0.12))
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .cycleCard(cornerRadius: 28)
    }
}

private struct CycleRawInputRow: View {
    let input: CycleObservation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: input.type.symbolName)
                .pulsarTextStyle(.metadata)
                .foregroundStyle(CyclePalette.secondaryText)
                .frame(width: 28, height: 28)
                .background(CyclePalette.calendarMarkerFill(isSelected: false), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(input.type.title)
                    .pulsarTextStyle(.label)
                    .foregroundStyle(.white.opacity(0.94))
                Text(input.value.summary)
                    .pulsarTextStyle(.metadata)
                    .foregroundStyle(CyclePalette.softText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(input.date.monthDayText)
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(CyclePalette.softText)
                Text(input.qualityScore.qualityText)
                    .pulsarTextStyle(.overline)
                    .foregroundStyle(CyclePalette.softText.opacity(0.78))
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(input.type.title), \(input.value.summary), \(input.date.monthDayText), \(input.qualityScore.qualityText)")
    }
}

private struct CycleDisclaimer: View {
    var body: some View {
        Text("Wellness guidance only. This screen assumes adult spontaneous cycles and is not a diagnosis tool. Adapt the model for pregnancy, postpartum, hormonal contraception, or clinician-directed care.")
            .pulsarTextStyle(.caption)
            .foregroundStyle(CyclePalette.secondaryText)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
    }
}

private struct CyclePrivacyNote: View {
    var body: some View {
        Label {
            Text("Cycle logs stay in local Pulsar storage on this device. Keep notification text private if you add reminders later.")
                .pulsarTextStyle(.caption)
                .foregroundStyle(CyclePalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(CyclePalette.phase(.follicular).accent)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cycleGlassSurface(cornerRadius: 20, tintOpacity: 0.045)
    }
}

private struct CycleDailyLogSheet: View {
    @ObservedObject var trackingStore: CycleTrackingStore
    @Environment(\.dismiss) private var dismiss
    let date: Date
    @State private var bleedingIntensity: BleedingIntensity?
    @State private var selectedSymptoms: Set<CycleSymptomKind>
    @State private var symptomSeverity: Int
    @State private var note: String

    init(trackingStore: CycleTrackingStore, date: Date) {
        self.trackingStore = trackingStore
        self.date = CycleDate.startOfDay(date)
        _bleedingIntensity = State(initialValue: trackingStore.bleedingLog(on: date)?.intensity)
        let symptoms = trackingStore.symptoms(on: date)
        _selectedSymptoms = State(initialValue: Set(symptoms.map(\.kind)))
        _symptomSeverity = State(initialValue: symptoms.map(\.severity).max() ?? 2)
        _note = State(initialValue: trackingStore.note(on: date))
    }

    var body: some View {
        ZStack {
            CycleDailyLogSheetBackground()

            VStack(spacing: 0) {
                Capsule(style: .continuous)
                    .fill(CyclePalette.sheetHandleFill)
                    .frame(width: 56, height: 6)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                    .accessibilityHidden(true)

                CycleDailyLogHeader {
                    dismiss()
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        CycleDailyLogIntroCard(dateText: date.monthDayText)

                        CycleDailyLogGlassCard(cornerRadius: 32, tintOpacity: 0.105) {
                            VStack(alignment: .leading, spacing: 20) {
                                CycleDailyLogSectionTitle(
                                    title: "Bleeding",
                                    symbolName: "drop.fill",
                                    accent: CyclePalette.dailyLogBleedingAccent
                                )

                                LazyVGrid(
                                    columns: [
                                        GridItem(.flexible(), spacing: 12),
                                        GridItem(.flexible(), spacing: 12),
                                        GridItem(.flexible(), spacing: 12)
                                    ],
                                    alignment: .leading,
                                    spacing: 14
                                ) {
                                    ForEach(BleedingIntensity.allCases, id: \.self) { intensity in
                                        CycleDailyLogBleedingPill(
                                            intensity: intensity,
                                            isSelected: bleedingIntensity == intensity
                                        ) {
                                            CycleHaptics.selection()
                                            bleedingIntensity = bleedingIntensity == intensity ? nil : intensity
                                        }
                                    }
                                }
                            }
                        }

                        CycleDailyLogGlassCard(cornerRadius: 32, tintOpacity: 0.115) {
                            VStack(alignment: .leading, spacing: 22) {
                                HStack(alignment: .center, spacing: 12) {
                                    CycleDailyLogSectionTitle(
                                        title: "Symptoms",
                                        symbolName: "sparkles",
                                        accent: CyclePalette.phase(.luteal).accent
                                    )

                                    Spacer(minLength: 8)

                                    Text("Severity \(symptomSeverity)/3")
                                        .pulsarTextStyle(.captionEmphasis)
                                        .foregroundStyle(CyclePalette.dailyLogLavenderText)

                                    Image(systemName: "info.circle")
                                        .pulsarTextStyle(.label)
                                        .foregroundStyle(CyclePalette.dailyLogLavenderText.opacity(0.78))
                                        .accessibilityHidden(true)
                                }

                                HStack(alignment: .center, spacing: 10) {
                                    Text("Overall symptom intensity")
                                        .pulsarTextStyle(.label)
                                        .foregroundStyle(.white.opacity(0.92))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.68)
                                        .allowsTightening(true)
                                        .layoutPriority(1)

                                    Spacer(minLength: 4)

                                    CycleDailyLogSeverityControl(value: $symptomSeverity)
                                }
                                .padding(.horizontal, 4)

                                LazyVGrid(
                                    columns: [
                                        GridItem(.flexible(), spacing: 12),
                                        GridItem(.flexible(), spacing: 12)
                                    ],
                                    alignment: .leading,
                                    spacing: 12
                                ) {
                                    ForEach(CycleSymptomKind.allCases, id: \.self) { symptom in
                                        CycleDailyLogSymptomChip(
                                            symptom: symptom,
                                            isSelected: selectedSymptoms.contains(symptom)
                                        ) {
                                            CycleHaptics.selection()
                                            if selectedSymptoms.contains(symptom) {
                                                selectedSymptoms.remove(symptom)
                                            } else {
                                                selectedSymptoms.insert(symptom)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        CycleDailyLogGlassCard(cornerRadius: 28, tintOpacity: 0.08) {
                            VStack(alignment: .leading, spacing: 12) {
                                CycleDailyLogSectionTitle(
                                    title: "Note",
                                    symbolName: "pencil.line",
                                    accent: CyclePalette.phase(.follicular).accent
                                )

                                TextField("Energy, sleep, nutrition, training, or context", text: $note, axis: .vertical)
                                    .pulsarTextStyle(.label)
                                    .foregroundStyle(.white.opacity(0.94))
                                    .tint(CyclePalette.phase(.luteal).accent)
                                    .lineLimit(3...6)
                                    .padding(14)
                                    .cycleReadablePanel(cornerRadius: 20)
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                    .padding(.bottom, 116)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .environment(\.colorScheme, .dark)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CycleDailyLogSaveBar {
                CycleHaptics.success()
                trackingStore.saveDailyLog(
                    date: date,
                    bleedingIntensity: bleedingIntensity,
                    symptoms: selectedSymptoms,
                    symptomSeverity: symptomSeverity,
                    note: note
                )
                dismiss()
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(.clear)
        .presentationCornerRadius(38)
    }
}

private struct CycleDailyLogSheetBackground: View {
    var body: some View {
        CycleModuleBackground()
            .blur(radius: 12)
            .overlay {
                LinearGradient(
                    colors: [
                        Color(red: 0.16, green: 0.18, blue: 0.27).opacity(0.46),
                        Color(red: 0.40, green: 0.33, blue: 0.45).opacity(0.34),
                        Color(red: 0.06, green: 0.08, blue: 0.14).opacity(0.44)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .overlay {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.68)
            }
            .ignoresSafeArea()
    }
}

private struct CycleDailyLogHeader: View {
    var onCancel: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            Button {
                onCancel()
            } label: {
                Text("Cancel")
                    .pulsarTextStyle(.buttonTitle)
                    .foregroundStyle(.white.opacity(0.94))
                    .padding(.horizontal, 22)
                    .frame(height: 50)
                    .cycleGlassSurface(cornerRadius: 25, tintOpacity: 0.075, isInteractive: true)
            }
            .buttonStyle(CyclePressButtonStyle())
            .accessibilityLabel("Cancel daily log")

            Spacer(minLength: 12)
        }
        .overlay {
            Text("Daily Log")
                .pulsarTextStyle(.sectionHeader)
                .foregroundStyle(.white.opacity(0.96))
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 16)
    }
}

private struct CycleDailyLogIntroCard: View {
    let dateText: String

    var body: some View {
        CycleDailyLogGlassCard(cornerRadius: 30, tintOpacity: 0.10) {
            HStack(alignment: .center, spacing: 18) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .frame(width: 64, height: 64)
                    .background(
                        LinearGradient(
                            colors: [
                                CyclePalette.phase(.luteal).tint.opacity(0.82),
                                CyclePalette.phase(.luteal).accent.opacity(0.44)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(.white.opacity(0.26), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 8) {
                    Text(dateText)
                        .pulsarTextStyle(.title)
                        .foregroundStyle(.white.opacity(0.98))
                    Text("Log what matters today. Symptoms guide recommendations more than phase alone.")
                        .pulsarTextStyle(.label)
                        .foregroundStyle(CyclePalette.dailyLogSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct CycleDailyLogGlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let tintOpacity: Double
    @ViewBuilder var content: Content

    init(cornerRadius: CGFloat, tintOpacity: Double, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.tintOpacity = tintOpacity
        self.content = content()
    }

    var body: some View {
        content
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cycleGlassSurface(cornerRadius: cornerRadius, tintOpacity: tintOpacity)
    }
}

private struct CycleDailyLogSectionTitle: View {
    let title: String
    let symbolName: String
    let accent: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbolName)
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.94))
                .frame(width: 46, height: 46)
                .background(
                    LinearGradient(
                        colors: [
                            accent.opacity(0.46),
                            CyclePalette.phase(.luteal).tint.opacity(0.34)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.24), lineWidth: 1)
                }

            Text(title)
                .pulsarTextStyle(.title)
                .foregroundStyle(.white.opacity(0.98))
        }
    }
}

private struct CycleDailyLogBleedingPill: View {
    let intensity: BleedingIntensity
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                CycleBleedingIntensityIcon(intensity: intensity)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(minWidth: 14)
                Text(intensity.title)
                    .pulsarTextStyle(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.56)
                    .allowsTightening(true)
            }
            .foregroundStyle(isSelected ? .white.opacity(0.96) : CyclePalette.dailyLogBleedingAccent.opacity(0.90))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 54)
            .padding(.horizontal, 5)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(isSelected ? CyclePalette.dailyLogBleedingAccent.opacity(0.18) : Color.white.opacity(0.025))
            )
            .cycleGlassSurface(cornerRadius: 22, tintOpacity: isSelected ? 0.13 : 0.045, isInteractive: true)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isSelected ? CyclePalette.dailyLogBleedingAccent.opacity(0.46) : .white.opacity(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(CyclePressButtonStyle())
        .accessibilityLabel("\(intensity.title) bleeding")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct CycleBleedingIntensityIcon: View {
    let intensity: BleedingIntensity

    var body: some View {
        switch intensity {
        case .spotting:
            ZStack {
                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .fill(CyclePalette.dailyLogBleedingAccent)
                        .frame(width: index == 0 ? 5 : 4, height: index == 0 ? 5 : 4)
                        .offset(spotOffset(for: index))
                }
            }
            .frame(width: 21, height: 18)
        case .light:
            Image(systemName: "drop.fill")
                .foregroundStyle(CyclePalette.dailyLogBleedingAccent)
        case .moderate:
            HStack(spacing: 1) {
                Image(systemName: "drop.fill")
                Image(systemName: "drop.fill")
            }
            .foregroundStyle(CyclePalette.dailyLogBleedingAccent)
        case .heavy:
            HStack(spacing: 0) {
                Image(systemName: "drop.fill")
                Image(systemName: "drop.fill")
                Image(systemName: "drop.fill")
            }
            .foregroundStyle(CyclePalette.dailyLogBleedingAccent)
        }
    }

    private func spotOffset(for index: Int) -> CGSize {
        switch index {
        case 0: CGSize(width: -5, height: 2)
        case 1: CGSize(width: 2, height: -5)
        case 2: CGSize(width: 7, height: 4)
        default: CGSize(width: -1, height: 7)
        }
    }
}

private struct CycleDailyLogSeverityControl: View {
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 0) {
            severityButton(symbolName: "minus") {
                value = max(1, value - 1)
            }
            .disabled(value <= 1)

            Text("\(value)")
                .pulsarTextStyle(.cardTitle)
                .foregroundStyle(.white.opacity(0.96))
                .monospacedDigit()
                .frame(width: 42, height: 44)
                .background(.white.opacity(0.07))

            severityButton(symbolName: "plus") {
                value = min(3, value + 1)
            }
            .disabled(value >= 3)
        }
        .frame(height: 44)
        .clipShape(Capsule(style: .continuous))
        .cycleGlassSurface(cornerRadius: 22, tintOpacity: 0.12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Overall symptom intensity")
        .accessibilityValue("\(value) of 3")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = min(3, value + 1)
            case .decrement:
                value = max(1, value - 1)
            default:
                break
            }
        }
    }

    private func severityButton(symbolName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 40, height: 44)
        }
        .buttonStyle(CyclePressButtonStyle())
        .opacity((symbolName == "minus" && value <= 1) || (symbolName == "plus" && value >= 3) ? 0.42 : 1)
    }
}

private struct CycleDailyLogSymptomChip: View {
    let symptom: CycleSymptomKind
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symptom.dailyLogSymbolName)
                    .font(.system(size: 16, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? CyclePalette.dailyLogSelectedText : CyclePalette.dailyLogSecondaryText.opacity(0.82))
                    .frame(width: 19)

                Text(symptom.shortTitle)
                    .pulsarTextStyle(.captionEmphasis)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .allowsTightening(true)
                    .foregroundStyle(isSelected ? CyclePalette.dailyLogSelectedText : CyclePalette.dailyLogSecondaryText)

                Spacer(minLength: 6)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CyclePalette.phase(.luteal).accent)
                        .frame(width: 24, height: 24)
                        .background(CyclePalette.phase(.luteal).tint.opacity(0.92), in: Circle())
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 58)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(isSelected ? CyclePalette.phase(.luteal).accent.opacity(0.17) : Color.white.opacity(0.025))
            )
            .cycleGlassSurface(cornerRadius: 22, tintOpacity: isSelected ? 0.16 : 0.055, isInteractive: true)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isSelected ? CyclePalette.phase(.luteal).tint.opacity(0.52) : .white.opacity(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(CyclePressButtonStyle())
        .accessibilityLabel(symptom.title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct CycleDailyLogSaveBar: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Save day log", systemImage: "checkmark.circle.fill")
                .pulsarTextStyle(.buttonTitle)
                .foregroundStyle(.white.opacity(0.96))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(
                    LinearGradient(
                        colors: [
                            CyclePalette.phase(.luteal).accent.opacity(0.92),
                            Color(red: 0.55, green: 0.38, blue: 0.86).opacity(0.82)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Capsule(style: .continuous)
                )
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.22), lineWidth: 1)
                }
                .shadow(color: CyclePalette.phase(.luteal).accent.opacity(0.18), radius: 18, y: 8)
        }
        .buttonStyle(CyclePressButtonStyle())
        .padding(.horizontal, 30)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay {
                    LinearGradient(
                        colors: [
                            Color(red: 0.13, green: 0.14, blue: 0.21).opacity(0.82),
                            Color(red: 0.13, green: 0.14, blue: 0.21).opacity(0.58),
                            .clear
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

private struct CycleSelectionPill: View {
    let title: String
    let isSelected: Bool
    let tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .pulsarTextStyle(.captionEmphasis)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .foregroundStyle(isSelected ? .white : tint)
                .background(isSelected ? tint : tint.opacity(0.12), in: Capsule(style: .continuous))
        }
        .buttonStyle(CyclePressButtonStyle())
    }
}

private struct CycleBleedingLogSheet: View {
    @ObservedObject var trackingStore: CycleTrackingStore
    @Environment(\.dismiss) private var dismiss
    @State private var visibleMonth: Date
    @State private var selectedDates: Set<Date>

    init(trackingStore: CycleTrackingStore, initialMonth: Date) {
        self.trackingStore = trackingStore
        _visibleMonth = State(initialValue: CycleDate.monthStart(for: initialMonth))
        _selectedDates = State(initialValue: Set(trackingStore.state.bleedingDates))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sheetHeader(
                        title: "Log bleeding",
                        subtitle: "Select every day you had bleeding. Consecutive days stay grouped as one period."
                    )

                    CycleBleedingCalendarCard(
                        visibleMonth: $visibleMonth,
                        selectedDates: $selectedDates,
                        today: trackingStore.today
                    )

                    Text("\(selectedDates.count) bleeding day\(selectedDates.count == 1 ? "" : "s") selected")
                        .pulsarTextStyle(.metadata)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(18)
            }
            .background(CycleModuleBackground())
            .safeAreaInset(edge: .bottom) {
                sheetSaveBar(title: "Save bleeding days")
            }
            .navigationTitle("Bleeding")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func sheetHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: "drop.fill")
                .pulsarTextStyle(.title)
                .foregroundStyle(CyclePalette.phase(.menstrual).accent)
            Text(subtitle)
                .pulsarTextStyle(.label)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .cycleCard(cornerRadius: 26)
    }

    private func sheetSaveBar(title: String) -> some View {
        Button {
            CycleHaptics.success()
            trackingStore.setBleedingDates(selectedDates)
            dismiss()
        } label: {
            Label(title, systemImage: "checkmark.circle.fill")
                .pulsarTextStyle(.label)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(CyclePalette.phase(.menstrual).accent, in: Capsule(style: .continuous))
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
        }
        .buttonStyle(CyclePressButtonStyle())
    }
}

private struct CycleEditCycleDataSheet: View {
    @ObservedObject var trackingStore: CycleTrackingStore
    @Environment(\.dismiss) private var dismiss
    @State private var lastPeriodStartDate: Date
    @State private var averagePeriodLength: Int
    @State private var averageCycleLength: Int
    @State private var visibleMonth: Date
    @State private var selectedDates: Set<Date>
    @State private var selectedSymptoms: Set<CycleSymptomKind>
    @State private var symptomSeverity: Int
    @State private var note: String
    private let originalLatestPeriodDates: Set<Date>

    init(trackingStore: CycleTrackingStore) {
        self.trackingStore = trackingStore
        let summary = trackingStore.summary
        let latestStart = summary.latestCycleStartDate ?? trackingStore.today
        let latestPeriodDates = Set(summary.periodGroups.last?.bleedingDates.map { CycleDate.startOfDay($0) } ?? [])
        self.originalLatestPeriodDates = latestPeriodDates
        _lastPeriodStartDate = State(initialValue: latestStart)
        _averagePeriodLength = State(initialValue: summary.baselinePeriodLength)
        _averageCycleLength = State(initialValue: summary.baselineCycleLength)
        _visibleMonth = State(initialValue: CycleDate.monthStart(for: latestStart))
        _selectedDates = State(initialValue: Set(trackingStore.state.bleedingDates))
        let symptoms = trackingStore.symptoms(on: latestStart)
        _selectedSymptoms = State(initialValue: Set(symptoms.map(\.kind)))
        _symptomSeverity = State(initialValue: symptoms.map(\.severity).max() ?? 2)
        _note = State(initialValue: trackingStore.note(on: latestStart))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("Edit cycle data", systemImage: "slider.horizontal.3")
                            .pulsarTextStyle(.title)
                        Text("Adjust your baseline and bleeding days. Estimates update as soon as you save.")
                            .pulsarTextStyle(.label)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                    .cycleCard(cornerRadius: 26)

                    VStack(spacing: 12) {
                        CycleDatePickerRow(
                            title: "Last period started",
                            selection: $lastPeriodStartDate
                        )

                        CycleStepperRow(
                            title: "Bleeding lasted",
                            value: $averagePeriodLength,
                            range: 1...14,
                            suffix: "days"
                        )

                        CycleStepperRow(
                            title: "Average cycle length",
                            value: $averageCycleLength,
                            range: 15...90,
                            suffix: "days"
                        )

                        Button {
                            CycleHaptics.selection()
                            applyPeriodRange()
                        } label: {
                            Label("Apply period range to calendar", systemImage: "calendar.badge.plus")
                                .pulsarTextStyle(.label)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .foregroundStyle(CyclePalette.phase(.menstrual).accent)
                                .background(CyclePalette.phase(.menstrual).tint, in: Capsule(style: .continuous))
                        }
                        .buttonStyle(CyclePressButtonStyle())
                    }
                    .padding(16)
                    .cycleCard(cornerRadius: 26)

                    CycleBleedingCalendarCard(
                        visibleMonth: $visibleMonth,
                        selectedDates: $selectedDates,
                        today: trackingStore.today
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Start-day symptoms")
                            .pulsarTextStyle(.cardTitle)

                        Stepper(value: $symptomSeverity, in: 1...3) {
                            Text("Symptom intensity \(symptomSeverity)/3")
                                .pulsarTextStyle(.label)
                        }
                        .padding(12)
                        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 10)], spacing: 10) {
                            ForEach(CycleSymptomKind.allCases, id: \.self) { symptom in
                                CycleSelectionPill(
                                    title: symptom.shortTitle,
                                    isSelected: selectedSymptoms.contains(symptom),
                                    tint: CyclePalette.phase(.luteal).accent
                                ) {
                                    CycleHaptics.selection()
                                    if selectedSymptoms.contains(symptom) {
                                        selectedSymptoms.remove(symptom)
                                    } else {
                                        selectedSymptoms.insert(symptom)
                                    }
                                }
                            }
                        }

                        TextField("Notes for this cycle", text: $note, axis: .vertical)
                            .lineLimit(2...5)
                            .padding(12)
                            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .padding(16)
                    .cycleCard(cornerRadius: 26)
                }
                .padding(18)
            }
            .background(CycleModuleBackground())
            .safeAreaInset(edge: .bottom) {
                Button {
                    CycleHaptics.success()
                    trackingStore.saveCycleData(
                        lastPeriodStartDate: lastPeriodStartDate,
                        averagePeriodLength: averagePeriodLength,
                        averageCycleLength: averageCycleLength,
                        bleedingDates: selectedDates,
                        symptomLogs: symptomLogsForSave(),
                        notesByDateKey: notesForSave()
                    )
                    dismiss()
                } label: {
                    Label("Save cycle data", systemImage: "checkmark.circle.fill")
                        .pulsarTextStyle(.label)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(CyclePalette.phase(.luteal).accent, in: Capsule(style: .continuous))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                }
                .buttonStyle(CyclePressButtonStyle())
            }
            .navigationTitle("Cycle Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func applyPeriodRange() {
        let start = CycleDate.startOfDay(lastPeriodStartDate)
        visibleMonth = CycleDate.monthStart(for: start)
        selectedDates.subtract(originalLatestPeriodDates)
        for offset in 0..<averagePeriodLength {
            selectedDates.insert(CycleDate.addDays(offset, to: start))
        }
    }

    private func symptomLogsForSave() -> [SymptomLog] {
        let normalizedStart = CycleDate.startOfDay(lastPeriodStartDate)
        let existing = trackingStore.state.symptomLogs.filter {
            !CycleDate.isSameDay($0.date, normalizedStart)
        }
        let updated = selectedSymptoms.map {
            SymptomLog(date: normalizedStart, kind: $0, severity: symptomSeverity)
        }
        return existing + updated
    }

    private func notesForSave() -> [String: String] {
        let normalizedStart = CycleDate.startOfDay(lastPeriodStartDate)
        let key = CycleTrackingCalculator.dateKey(for: normalizedStart)
        var notes = trackingStore.state.notesByDateKey
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedNote.isEmpty {
            notes.removeValue(forKey: key)
        } else {
            notes[key] = trimmedNote
        }
        return notes
    }
}

private struct CycleBleedingCalendarCard: View {
    @Binding var visibleMonth: Date
    @Binding var selectedDates: Set<Date>
    let today: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                    CycleHaptics.selection()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        visibleMonth = CycleDate.addMonths(-1, to: visibleMonth)
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .pulsarTextStyle(.label)
                        .frame(width: 34, height: 34)
                        .background(.secondary.opacity(0.10), in: Circle())
                }
                .buttonStyle(CyclePressButtonStyle())

                Spacer()

                Text(visibleMonth.formatted(.dateTime.month(.wide).year()))
                    .pulsarTextStyle(.cardTitle)
                    .multilineTextAlignment(.center)

                Spacer()

                Button {
                    CycleHaptics.selection()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        visibleMonth = CycleDate.addMonths(1, to: visibleMonth)
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .pulsarTextStyle(.label)
                        .frame(width: 34, height: 34)
                        .background(.secondary.opacity(0.10), in: Circle())
                }
                .buttonStyle(CyclePressButtonStyle())
            }

            CycleBleedingCalendarGrid(
                month: visibleMonth,
                selectedDates: $selectedDates,
                today: today
            )

            HStack(spacing: 8) {
                CycleCalendarLegendDot(color: CyclePalette.phase(.menstrual).accent, title: "Bleeding")
                CycleCalendarLegendDot(color: .secondary.opacity(0.45), title: "Today")
            }
        }
        .padding(16)
        .cycleCard(cornerRadius: 28)
    }
}

private struct CycleBleedingCalendarGrid: View {
    let month: Date
    @Binding var selectedDates: Set<Date>
    let today: Date

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 7), count: 7)

    var body: some View {
        VStack(spacing: 9) {
            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(CycleDate.weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .pulsarTextStyle(.overline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(CycleDate.monthGridDates(for: month).enumerated()), id: \.offset) { _, date in
                    if let date {
                        CycleBleedingDateButton(
                            date: date,
                            isSelected: selectedDates.contains(CycleDate.startOfDay(date)),
                            isToday: CycleDate.isSameDay(date, today)
                        ) {
                            let normalizedDate = CycleDate.startOfDay(date)
                            CycleHaptics.selection()
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                if selectedDates.contains(normalizedDate) {
                                    selectedDates.remove(normalizedDate)
                                } else {
                                    selectedDates.insert(normalizedDate)
                                }
                            }
                        }
                    } else {
                        Color.clear
                            .frame(height: 42)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }
}

private struct CycleBleedingDateButton: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    var action: () -> Void

    private var token: CyclePhaseToken { CyclePalette.phase(.menstrual) }

    var body: some View {
        Button(action: action) {
            Text(date.dayNumberText)
                .pulsarTextStyle(.label)
                .monospacedDigit()
                .foregroundStyle(isSelected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(background)
                .overlay {
                    Circle()
                        .stroke(isToday ? token.accent.opacity(0.55) : .clear, lineWidth: 1.4)
                        .padding(3)
                }
        }
        .buttonStyle(CyclePressButtonStyle())
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityValue(isSelected ? "Bleeding selected" : isToday ? "Today" : "Not selected")
        .accessibilityHint("Toggles this date as a bleeding day.")
    }

    @ViewBuilder
    private var background: some View {
        if isSelected {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            token.accent,
                            Color(red: 0.96, green: 0.26, blue: 0.42)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: token.accent.opacity(0.22), radius: 8, y: 4)
        } else {
            Circle()
                .fill(.secondary.opacity(isToday ? 0.13 : 0.07))
        }
    }
}

private struct CycleCalendarLegendDot: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .pulsarTextStyle(.overline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CycleCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        content
            .cycleGlassSurface(cornerRadius: cornerRadius, tintOpacity: 0.052)
    }
}

private struct CycleGlassSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let tintOpacity: Double
    let isInteractive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26.0, *) {
            let glass = Glass.regular
                .tint(CyclePalette.glassEffectTint(for: colorScheme, opacity: tintOpacity))
            glassBase(content, shape: shape, includesMaterial: false)
                .glassEffect(isInteractive ? glass.interactive() : glass, in: shape)
        } else {
            glassBase(content, shape: shape, includesMaterial: true)
        }
    }

    @ViewBuilder
    private func glassBase(_ content: Content, shape: RoundedRectangle, includesMaterial: Bool) -> some View {
        if includesMaterial {
            glassDecoration(
                content.background(.ultraThinMaterial, in: shape),
                shape: shape
            )
        } else {
            glassDecoration(content, shape: shape)
        }
    }

    private func glassDecoration<DecoratedContent: View>(_ content: DecoratedContent, shape: RoundedRectangle) -> some View {
        content
            .background(CyclePalette.glassTint(for: colorScheme, opacity: tintOpacity), in: shape)
            .background {
                shape
                    .fill(CyclePalette.glassSpecularHighlight(for: colorScheme))
                    .blendMode(.screen)
                    .opacity(colorScheme == .dark ? 0.64 : 0.54)
            }
            .background {
                shape
                    .fill(CyclePalette.glassReadabilityWash(for: colorScheme))
            }
            .overlay {
                shape
                    .stroke(CyclePalette.glassBorder(for: colorScheme), lineWidth: 1)
            }
            .overlay {
                shape
                    .strokeBorder(.white.opacity(colorScheme == .dark ? 0.18 : 0.52), lineWidth: 0.65)
                    .blur(radius: 0.7)
                    .mask(
                        LinearGradient(
                            colors: [.white, .clear, .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay(alignment: .topLeading) {
                shape
                    .stroke(.white.opacity(colorScheme == .dark ? 0.20 : 0.56), lineWidth: 0.65)
                    .blur(radius: 0.6)
                    .opacity(0.72)
                    .mask(
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.12), radius: 22, y: 12)
    }
}

private struct CycleNativeGlassModifier<GlassShape: Shape>: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let shape: GlassShape
    let tintOpacity: Double
    let isInteractive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            let glass = Glass.regular
                .tint(CyclePalette.glassEffectTint(for: colorScheme, opacity: tintOpacity))
            content
                .glassEffect(isInteractive ? glass.interactive() : glass, in: shape)
        } else {
            content
        }
    }
}

private struct CycleReadablePanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background(.ultraThinMaterial, in: shape)
            .background(CyclePalette.readablePanelFill(for: colorScheme), in: shape)
            .overlay {
                shape
                    .stroke(CyclePalette.readablePanelBorder(for: colorScheme), lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                shape
                    .stroke(.white.opacity(colorScheme == .dark ? 0.24 : 0.56), lineWidth: 0.6)
                    .blur(radius: 0.5)
                    .mask(
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
    }
}

private extension View {
    func cycleCard(cornerRadius: CGFloat) -> some View {
        modifier(CycleCardModifier(cornerRadius: cornerRadius))
    }

    func cycleGlassSurface(cornerRadius: CGFloat, tintOpacity: Double = 0.16, isInteractive: Bool = false) -> some View {
        modifier(CycleGlassSurfaceModifier(cornerRadius: cornerRadius, tintOpacity: tintOpacity, isInteractive: isInteractive))
    }

    func cycleNativeGlass<GlassShape: Shape>(shape: GlassShape, tintOpacity: Double = 0.12, isInteractive: Bool = false) -> some View {
        modifier(CycleNativeGlassModifier(shape: shape, tintOpacity: tintOpacity, isInteractive: isInteractive))
    }

    func cycleReadablePanel(cornerRadius: CGFloat) -> some View {
        modifier(CycleReadablePanelModifier(cornerRadius: cornerRadius))
    }
}

private struct CyclePressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.24, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

private enum CycleHaptics {
    static func selection() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}

private enum RecommendationKind {
    case move
    case fuel
    case recover

    var title: String {
        switch self {
        case .move: "Move"
        case .fuel: "Fuel"
        case .recover: "Recover"
        }
    }

    var symbolName: String {
        switch self {
        case .move: "figure.run"
        case .fuel: "fork.knife"
        case .recover: "moon.zzz.fill"
        }
    }

    var accent: Color {
        switch self {
        case .move: Color(red: 0.14, green: 0.55, blue: 0.42)
        case .fuel: Color(red: 0.67, green: 0.38, blue: 0.10)
        case .recover: Color(red: 0.43, green: 0.33, blue: 0.68)
        }
    }

    var tint: Color {
        accent.opacity(0.14)
    }
}

private enum CycleObservationType: String, CaseIterable {
    case bleeding
    case lhTest
    case wristTemp
    case bbt
    case symptom
    case sleep
    case workout

    var title: String {
        switch self {
        case .bleeding: "Bleeding"
        case .lhTest: "LH test"
        case .wristTemp: "Wrist temperature"
        case .bbt: "Basal body temperature"
        case .symptom: "Symptom"
        case .sleep: "Sleep"
        case .workout: "Workout"
        }
    }

    var symbolName: String {
        switch self {
        case .bleeding: "drop.fill"
        case .lhTest: "checkmark.seal.fill"
        case .wristTemp, .bbt: "thermometer.medium"
        case .symptom: "heart.text.square.fill"
        case .sleep: "bed.double.fill"
        case .workout: "figure.indoor.cycle"
        }
    }
}

private enum CycleObservationSource: String {
    case manual
    case wearable
    case healthkit
    case imported
}

private enum LHTestResult: String {
    case negative
    case positive
}

private enum WorkoutIntensity: String {
    case easy
    case moderate
    case hard
}

private enum CycleObservationValue: Equatable {
    case bleeding(flow: BleedingIntensity, heavyBleeding: Bool = false)
    case lhTest(result: LHTestResult, ratio: Double?)
    case temperature(deviationC: Double, elevated: Bool)
    case symptom(CycleSymptomKind, severity: Int)
    case sleep(durationMinutes: Int, awakenings: Int, efficiency: Double?)
    case workout(kind: String, planned: Bool, intensity: WorkoutIntensity, durationMinutes: Int?)

    var summary: String {
        switch self {
        case .bleeding(flow: let flow, heavyBleeding: let heavyBleeding):
            return "\(flow.rawValue) flow\(heavyBleeding ? ", heavy bleeding logged" : "")"
        case .lhTest(result: let result, ratio: let ratio):
            if let ratio {
                return "\(result.rawValue) result, ratio \(String(format: "%.2f", ratio))"
            }
            return "\(result.rawValue) result"
        case .temperature(deviationC: let deviationC, elevated: _):
            return "\(deviationC >= 0 ? "+" : "")\(String(format: "%.2f", deviationC)) C deviation"
        case .symptom(let symptom, severity: let severity):
            return "\(symptom.title), severity \(severity)/3"
        case .sleep(durationMinutes: let durationMinutes, awakenings: let awakenings, efficiency: _):
            return "\(durationMinutes.hoursMinutesText), \(awakenings) awakenings"
        case .workout(kind: let kind, planned: _, intensity: let intensity, durationMinutes: let durationMinutes):
            let minutes = durationMinutes.map { ", \($0) min" } ?? ""
            return "\(kind), \(intensity.rawValue)\(minutes)"
        }
    }
}

private struct CycleObservation: Identifiable, Equatable {
    let id: String
    let date: Date
    let type: CycleObservationType
    let value: CycleObservationValue
    let source: CycleObservationSource
    let qualityScore: Double
}

private struct CycleHistory: Identifiable, Equatable {
    let id: String
    let startDate: Date
    let length: Int
    let ovulationDay: Int?
    let usable: Bool
}

private struct PhaseEstimate: Equatable {
    let date: Date
    let phase: CyclePhase
    let confidence: Double
    let confidenceLabel: PredictionConfidence
    let posteriorByPhase: [CyclePhase: Double]
    let evidenceSummary: [String]
}

private struct Recommendation: Equatable {
    let title: String
    let body: String
    let emphasis: RecommendationEmphasis
}

private enum RecommendationEmphasis: Equatable {
    case light
    case steady
    case push
    case recover
}

private struct DailyRecommendations: Equatable {
    let move: Recommendation
    let fuel: Recommendation
    let recover: Recommendation
    let rationaleTags: [String]
}

private struct CycleDayMarker: Identifiable, Equatable {
    let id: String
    let label: String
    let shortLabel: String
}

private struct CycleDayModel: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let isToday: Bool
    let cycleDay: Int
    let estimate: PhaseEstimate
    let observations: [CycleObservation]
    let symptomBurden: Double
    let markers: [CycleDayMarker]

    var weekdayText: String { date.weekdayShortText }
    var dayNumberText: String { date.dayNumberText }
    var monthDayText: String { date.monthDayText }

    var accessibilityLabel: String {
        let markerText = markers.isEmpty ? "" : " Markers: \(markers.map(\.label).joined(separator: ", "))."
        return "\(weekdayText) \(monthDayText), cycle day \(cycleDay), \(CyclePalette.phase(estimate.phase).name), \(estimate.confidenceLabel.rawValue).\(isToday ? " Today." : "")\(markerText)"
    }

    var rationaleLines: [String] {
        let phaseName = estimate.phase == .luteal && cycleDay >= 24 ? "late luteal" : CyclePalette.phase(estimate.phase).name.lowercased()
        return [
            "Phase: \(phaseName). The model weights bleeding onset first, then LH timing, then sustained temperature shift.",
            "Estimate strength: \(estimate.confidenceLabel.rawValue). Wrist temperature supports the luteal transition, but is weighted below sustained BBT.",
            "Guidance uses phase plus today's symptoms, sleep, and planned workout. Symptoms affect recommendations more than phase detection."
        ]
    }
}

private struct CycleViewModel: Equatable {
    let today: Date
    let days: [CycleDayModel]
    let selectedDay: CycleDayModel
    let selectedInputs: [CycleObservation]
    let recommendations: DailyRecommendations
    let nextEvent: String
    let predictedCycleLength: Int
    let phaseProgress: Double
    let chartSummary: String
    let timelineSummary: String

    var displayPhaseName: String {
        if selectedDay.estimate.phase == .luteal && selectedDay.cycleDay >= 24 {
            return "Late luteal"
        }
        return CyclePalette.phase(selectedDay.estimate.phase).name
    }
}

private enum CycleInferenceEngine {
    static func makeViewModel(
        trackingState: CycleTrackingState,
        today: Date,
        selectedDate: Date
    ) -> CycleViewModel {
        let observations = observations(from: trackingState)
        let cycleHistory = cycleHistory(from: trackingState)
        let fallbackCycleLength = CycleTrackingCalculator.summary(for: trackingState, today: today).averageCycleLength
        let predictedCycleLength = predictedCycleLength(from: cycleHistory, fallback: fallbackCycleLength)
        let range = CycleDate.range(start: CycleDate.addDays(-7, to: today), count: 22)
        let days = range.map { date in
            makeDay(
                date: date,
                today: today,
                observations: observations,
                cycleHistory: cycleHistory,
                fallbackCycleLength: fallbackCycleLength
            )
        }
        let selectedDay = days.first { CycleDate.isSameDay($0.date, selectedDate) }
            ?? days.first { $0.isToday }
            ?? days[0]
        let selectedInputs = relevantInputs(observations: observations, selectedDate: selectedDay.date)
        let nextEvent = nextPredictedEvent(
            for: selectedDay,
            observations: observations,
            cycleHistory: cycleHistory,
            fallbackCycleLength: fallbackCycleLength
        )

        return CycleViewModel(
            today: today,
            days: days,
            selectedDay: selectedDay,
            selectedInputs: selectedInputs,
            recommendations: recommendations(for: selectedDay),
            nextEvent: nextEvent,
            predictedCycleLength: predictedCycleLength,
            phaseProgress: min(max(Double(selectedDay.cycleDay) / Double(max(predictedCycleLength, 1)), 0.03), 0.98),
            chartSummary: chartSummary(for: selectedDay),
            timelineSummary: timelineSummary(days: days)
        )
    }

    private static func observations(from trackingState: CycleTrackingState) -> [CycleObservation] {
        let bleedingObservations = CycleTrackingCalculator.normalizedBleedingLogs(for: trackingState).map { log in
            CycleObservation(
                id: "bleeding-\(CycleTrackingCalculator.dateKey(for: log.date))",
                date: log.date,
                type: .bleeding,
                value: .bleeding(flow: log.intensity, heavyBleeding: log.intensity == .heavy),
                source: .manual,
                qualityScore: 1.0
            )
        }

        let symptomObservations = CycleTrackingCalculator.normalizedSymptomLogs(trackingState.symptomLogs).map { log in
            CycleObservation(
                id: log.id,
                date: log.date,
                type: .symptom,
                value: .symptom(log.kind, severity: log.severity),
                source: .manual,
                qualityScore: 0.86
            )
        }

        return (bleedingObservations + symptomObservations).sorted {
            if $0.date == $1.date { return $0.id < $1.id }
            return $0.date < $1.date
        }
    }

    private static func cycleHistory(from trackingState: CycleTrackingState) -> [CycleHistory] {
        let groups = CycleTrackingCalculator.periodGroups(from: trackingState.bleedingDates)
        guard groups.count >= 2 else { return [] }

        return zip(groups, groups.dropFirst()).enumerated().map { index, pair in
            let length = CycleTrackingCalculator.daysBetween(pair.0.startDate, pair.1.startDate)
            return CycleHistory(
                id: "cycle-\(CycleTrackingCalculator.dateKey(for: pair.0.startDate))-\(index)",
                startDate: pair.0.startDate,
                length: length,
                ovulationDay: max(10, length - 14),
                usable: (18...60).contains(length)
            )
        }
    }

    private static func makeDay(
        date: Date,
        today: Date,
        observations: [CycleObservation],
        cycleHistory: [CycleHistory],
        fallbackCycleLength: Int
    ) -> CycleDayModel {
        let dayObservations = observations.filter { CycleDate.isSameDay($0.date, date) }
        let cycleDay = cycleDay(for: date, observations: observations)
        return CycleDayModel(
            date: date,
            isToday: CycleDate.isSameDay(date, today),
            cycleDay: cycleDay,
            estimate: phaseEstimate(
                for: date,
                observations: observations,
                cycleHistory: cycleHistory,
                fallbackCycleLength: fallbackCycleLength
            ),
            observations: dayObservations,
            symptomBurden: symptomBurden(in: dayObservations),
            markers: markers(for: dayObservations)
        )
    }

    private static func phaseEstimate(
        for date: Date,
        observations: [CycleObservation],
        cycleHistory: [CycleHistory],
        fallbackCycleLength: Int
    ) -> PhaseEstimate {
        let currentCycleDay = cycleDay(for: date, observations: observations)
        let bleedingToday = observations.contains { CycleDate.isSameDay($0.date, date) && $0.type == .bleeding }
        let latestPositiveLH = latestPositiveLH(observations: observations, through: date)
        let daysSinceLH = latestPositiveLH.map { CycleDate.daysBetween($0.date, date) }
        let tempSignal = sustainedTemperatureSignal(observations: observations, through: date)
        let positiveLHCycleDay = latestPositiveLH.map { cycleDay(for: $0.date, observations: observations) }
        let conflicts = signalConflicts(on: date, observations: observations, positiveLHDate: latestPositiveLH?.date, sustainedTemperatureRise: tempSignal.isSustained)

        var phase = datePhase(
            cycleDay: currentCycleDay,
            cycleHistory: cycleHistory,
            fallbackCycleLength: fallbackCycleLength,
            positiveLHCycleDay: positiveLHCycleDay
        )
        if bleedingToday && currentCycleDay <= 5 {
            phase = .menstrual
        } else if let daysSinceLH, (-1...2).contains(daysSinceLH) {
            phase = .ovulatory
        } else if let daysSinceLH, daysSinceLH > 2, tempSignal.isSustained {
            phase = .luteal
        }

        let usableCycles = cycleHistory.filter(\.usable).count
        let variabilityPenalty = cycleVariabilityPenalty(cycleHistory)
        let missingPenalty = (latestPositiveLH == nil ? 0.04 : 0) + (tempSignal.count == 0 ? 0.04 : 0)
        let wristPenalty = tempSignal.kind == .wristTemp && phase == .luteal ? 0.15 : 0
        let conflictPenalty = conflicts.isEmpty ? 0 : 0.18
        let historyPenalty = usableCycles < 3 ? 0.06 : 0

        var confidence = 0.42
        if phase != .uncertain { confidence += 0.18 }
        if bleedingToday { confidence += currentCycleDay <= 2 ? 0.34 : 0.16 }
        if latestPositiveLH != nil { confidence += 0.10 }
        if phase == .ovulatory, let daysSinceLH, abs(daysSinceLH) <= 1 { confidence += 0.16 }
        if phase == .luteal, tempSignal.isSustained { confidence += tempSignal.kind == .bbt ? 0.22 : 0.16 }
        if phase == .luteal, latestPositiveLH != nil, tempSignal.isSustained { confidence += 0.08 }

        confidence = min(max(confidence - variabilityPenalty - missingPenalty - wristPenalty - conflictPenalty - historyPenalty, 0.18), 0.96)
        confidence = (confidence * 100).rounded() / 100

        let label = confidenceLabel(
            phase: phase,
            confidence: confidence,
            bleedingToday: bleedingToday,
            cycleDay: currentCycleDay,
            tempSignal: tempSignal,
            conflicts: conflicts
        )

        return PhaseEstimate(
            date: date,
            phase: phase,
            confidence: confidence,
            confidenceLabel: label,
            posteriorByPhase: posterior(phase: phase, confidence: confidence),
            evidenceSummary: evidenceSummary(
                date: date,
                cycleDay: currentCycleDay,
                latestPositiveLH: latestPositiveLH,
                tempSignal: tempSignal,
                observations: observations,
                conflicts: conflicts
            )
        )
    }

    private static func recommendations(for day: CycleDayModel) -> DailyRecommendations {
        let symptoms = symptomObservations(in: day.observations)
        let symptomBurden = symptomBurden(in: day.observations)
        let sleep = day.observations.first { $0.type == .sleep }
        let workout = day.observations.first { $0.type == .workout }
        let shortSleep = sleep?.value.sleepMinutes.map { $0 < 420 } ?? false
        let hardWorkout = workout?.value.workoutIntensity == .hard
        let symptomNames = symptoms.map { $0.value.symptomName }.compactMap { $0 }
        let hasHeavyBleeding = day.observations.contains { $0.value.isHeavyBleeding }

        if day.estimate.phase == .menstrual || (day.estimate.phase == .follicular && day.cycleDay <= 5) {
            let highSymptoms = symptomBurden >= 2 || hasHeavyBleeding
            return DailyRecommendations(
                move: Recommendation(
                    title: highSymptoms ? "Choose light to moderate work" : "Ease in with steady movement",
                    body: highSymptoms
                        ? "Keep training conversational today. Mobility, zone 2, or a shorter strength session respects higher symptom load."
                        : "A moderate session is reasonable if cramps and fatigue are low. Keep one repeat in reserve.",
                    emphasis: highSymptoms ? .recover : .steady
                ),
                fuel: Recommendation(
                    title: hasHeavyBleeding ? "Hydrate and watch iron patterns" : "Prioritize fluids and regular meals",
                    body: hasHeavyBleeding
                        ? "Log heavy bleeding patterns and consider asking a clinician about ferritin or iron status if this repeats."
                        : "Pair meals with protein and iron-rich foods when appetite allows. Add sodium if bleeding and sweat losses overlap.",
                    emphasis: .steady
                ),
                recover: Recommendation(
                    title: "Protect sleep pressure",
                    body: "Lower evening intensity, use heat or relaxation if helpful, and let symptoms guide tomorrow's load.",
                    emphasis: .recover
                ),
                rationaleTags: ["bleeding", highSymptoms ? "symptoms" : "early cycle", "recovery"]
            )
        }

        if day.estimate.phase == .follicular {
            return DailyRecommendations(
                move: Recommendation(
                    title: symptomBurden < 1.5 ? "Support a key session" : "Build, but keep feedback loops open",
                    body: symptomBurden < 1.5
                        ? "This is a good window for quality work if readiness is high. Warm up fully and keep technique crisp."
                        : "Training can progress, but keep intensity adjustable if fatigue or cramps show up.",
                    emphasis: symptomBurden < 1.5 ? .push : .steady
                ),
                fuel: Recommendation(
                    title: "Fuel harder work",
                    body: "Place carbohydrates around demanding sessions and distribute protein across meals to support adaptation.",
                    emphasis: .push
                ),
                recover: Recommendation(
                    title: "Bank recovery early",
                    body: "Use the easier-feeling days well: consistent sleep, daylight, and post-session downshifts.",
                    emphasis: .steady
                ),
                rationaleTags: ["follicular", "training readiness", "fuel timing"]
            )
        }

        if day.estimate.phase == .ovulatory {
            return DailyRecommendations(
                move: Recommendation(
                    title: "Keep the plan if readiness is favorable",
                    body: shortSleep
                        ? "The LH window supports planned work, but short sleep argues for trimming the hardest block."
                        : "If symptoms are low, the planned session can stay. Use warm-up feel to confirm the day.",
                    emphasis: shortSleep ? .steady : .push
                ),
                fuel: Recommendation(
                    title: "Keep energy available",
                    body: "Do not underfuel intensity. A carb-forward pre-session snack can protect output and mood.",
                    emphasis: .steady
                ),
                recover: Recommendation(
                    title: "Check sleep and soreness",
                    body: "If soreness or sleep debt is rising, trade peak intensity for controlled quality.",
                    emphasis: shortSleep ? .recover : .steady
                ),
                rationaleTags: ["LH evidence", "sleep check", "symptoms"]
            )
        }

        if day.estimate.phase == .luteal {
            return DailyRecommendations(
                move: Recommendation(
                    title: hardWorkout ? "Make intervals conditional" : "Train with a recovery margin",
                    body: hardWorkout
                        ? "Start the bike intervals, then cap the final reps or swap to tempo if bloating, fatigue, or power drift climbs."
                        : "Steady training fits today. Keep effort honest and avoid chasing numbers if fatigue is louder than usual.",
                    emphasis: shortSleep || symptomBurden >= 1.5 ? .steady : .push
                ),
                fuel: Recommendation(
                    title: "Normalize higher hunger",
                    body: "Cravings and late-luteal hunger can be useful signals. Add carbs around training and anchor meals with protein.",
                    emphasis: .steady
                ),
                recover: Recommendation(
                    title: shortSleep ? "Prioritize sleep protection tonight" : "Add a recovery buffer",
                    body: shortSleep
                        ? "Last night's sleep was short. Keep caffeine earlier, downshift after dinner, and give tomorrow's plan room to flex."
                        : "Use a longer cool-down, fluids, and a calmer evening routine if PMS-like symptoms are building.",
                    emphasis: .recover
                ),
                rationaleTags: compactTags(["late luteal", shortSleep ? "short sleep" : nil] + symptomNames)
            )
        }

        return DailyRecommendations(
            move: Recommendation(
                title: "Use today's readiness",
                body: "Phase confidence is low, so use sleep, soreness, symptoms, and warm-up feel to choose intensity.",
                emphasis: .steady
            ),
            fuel: Recommendation(
                title: "Avoid accidental underfueling",
                body: "Keep meals regular and add carbohydrates if a harder workout stays on the plan.",
                emphasis: .steady
            ),
            recover: Recommendation(
                title: "Let uncertainty reduce pressure",
                body: "Collect one or two high-quality logs today. Better data will sharpen the next recommendation.",
                emphasis: .recover
            ),
            rationaleTags: ["uncertain phase", "readiness", "data gap"]
        )
    }

    private static func datePhase(
        cycleDay: Int,
        cycleHistory: [CycleHistory],
        fallbackCycleLength: Int,
        positiveLHCycleDay: Int?
    ) -> CyclePhase {
        guard cycleDay > 0 else { return .uncertain }
        if cycleDay <= 5 { return .menstrual }

        let averageOvulationDay = Int(
            (median(cycleHistory.compactMap { $0.usable ? $0.ovulationDay : nil })
                ?? Double(max(12, fallbackCycleLength - 14))).rounded()
        )

        if let positiveLHCycleDay {
            if (positiveLHCycleDay - 1)...(positiveLHCycleDay + 2) ~= cycleDay {
                return .ovulatory
            }
            if cycleDay > positiveLHCycleDay + 2 {
                return .luteal
            }
        }

        if (averageOvulationDay - 2)...(averageOvulationDay + 2) ~= cycleDay {
            return .ovulatory
        }
        if cycleDay > averageOvulationDay + 2 {
            return .luteal
        }
        return .follicular
    }

    private static func confidenceLabel(
        phase: CyclePhase,
        confidence: Double,
        bleedingToday: Bool,
        cycleDay: Int,
        tempSignal: TemperatureSignal,
        conflicts: [String]
    ) -> PredictionConfidence {
        if !conflicts.isEmpty || confidence < 0.46 { return .limited }
        if bleedingToday && cycleDay <= 2 { return .strong }
        if phase == .luteal && tempSignal.kind == .bbt && tempSignal.isSustained && confidence >= 0.78 {
            return .strong
        }
        if confidence >= 0.68 { return .moderate }
        return .limited
    }

    private static func evidenceSummary(
        date: Date,
        cycleDay: Int,
        latestPositiveLH: CycleObservation?,
        tempSignal: TemperatureSignal,
        observations: [CycleObservation],
        conflicts: [String]
    ) -> [String] {
        var summary = ["Cycle day \(cycleDay)"]

        if let latestPositiveLH {
            let delta = CycleDate.daysBetween(latestPositiveLH.date, date)
            summary.append(delta == 0 ? "Positive LH today" : "Positive LH \(delta)d ago")
        }

        if tempSignal.count > 0 {
            summary.append("\(tempSignal.kind.title) elevated \(tempSignal.count)d")
        }

        let symptoms = symptomObservations(in: observations.filter { CycleDate.isSameDay($0.date, date) })
            .compactMap { $0.value.symptomName }
        if !symptoms.isEmpty {
            summary.append("Symptoms: \(symptoms.joined(separator: ", "))")
        }

        if !conflicts.isEmpty {
            summary.append("Conflicts: \(conflicts.joined(separator: ", "))")
        }

        return summary
    }

    private static func posterior(phase: CyclePhase, confidence: Double) -> [CyclePhase: Double] {
        let other = ((1 - confidence) / Double(CyclePhase.allCases.count - 1) * 100).rounded() / 100
        return Dictionary(uniqueKeysWithValues: CyclePhase.allCases.map { item in
            (item, item == phase ? confidence : other)
        })
    }

    private static func markers(for observations: [CycleObservation]) -> [CycleDayMarker] {
        var markers: [CycleDayMarker] = []
        if observations.contains(where: { $0.type == .bleeding }) {
            markers.append(.init(id: "bleeding", label: "Bleeding logged", shortLabel: "B"))
        }
        if observations.contains(where: { $0.value.isPositiveLH }) {
            markers.append(.init(id: "lh", label: "Positive LH test", shortLabel: "LH"))
        }
        if observations.contains(where: { $0.type == .wristTemp || $0.type == .bbt }) {
            markers.append(.init(id: "temp", label: "Temperature signal", shortLabel: "T"))
        }
        if observations.contains(where: { $0.type == .symptom }) {
            markers.append(.init(id: "symptom", label: "Symptoms logged", shortLabel: "S"))
        }
        if observations.contains(where: { $0.type == .workout }) {
            markers.append(.init(id: "workout", label: "Workout planned", shortLabel: "W"))
        }
        return markers
    }

    private static func relevantInputs(observations: [CycleObservation], selectedDate: Date) -> [CycleObservation] {
        let start = CycleDate.addDays(-14, to: selectedDate)
        return observations
            .filter { observation in
                observation.date >= start && observation.date <= selectedDate &&
                    (CycleDate.isSameDay(observation.date, selectedDate) || observation.type.isModelSignal)
            }
            .suffix(16)
            .map { $0 }
    }

    private static func predictedCycleLength(from cycleHistory: [CycleHistory], fallback: Int) -> Int {
        Int((median(cycleHistory.filter(\.usable).map(\.length)) ?? Double(fallback)).rounded())
    }

    private static func cycleVariabilityPenalty(_ cycleHistory: [CycleHistory]) -> Double {
        let lengths = cycleHistory.filter(\.usable).map(\.length)
        guard !lengths.isEmpty else { return 0.04 }
        guard lengths.count >= 3 else { return 0.06 }
        let spread = (lengths.max() ?? 0) - (lengths.min() ?? 0)
        if spread >= 7 { return 0.10 }
        if spread >= 5 { return 0.07 }
        if spread >= 3 { return 0.04 }
        return 0.02
    }

    private static func cycleDay(for date: Date, observations: [CycleObservation]) -> Int {
        guard let onset = latestBleedingOnset(observations: observations, through: date) else { return 0 }
        return CycleDate.daysBetween(onset, date) + 1
    }

    private static func latestBleedingOnset(observations: [CycleObservation], through date: Date) -> Date? {
        let bleedingDates = Array(Set(observations
            .filter { $0.type == .bleeding && $0.date <= date }
            .map(\.date)))
            .sorted()

        let onsets = bleedingDates.enumerated().filter { index, bleedingDate in
            guard index > 0 else { return true }
            return CycleDate.daysBetween(bleedingDates[index - 1], bleedingDate) >= CycleTrackingCalculator.minimumCycleStartGapDays
        }
        .map(\.element)

        return onsets.last
    }

    private static func latestPositiveLH(observations: [CycleObservation], through date: Date) -> CycleObservation? {
        observations
            .filter { $0.date <= date && $0.value.isPositiveLH }
            .sorted { $0.date < $1.date }
            .last
    }

    private static func sustainedTemperatureSignal(observations: [CycleObservation], through date: Date) -> TemperatureSignal {
        let elevatedTemps = observations
            .filter { ($0.type == .wristTemp || $0.type == .bbt) && $0.date <= date && $0.value.isElevatedTemperature }
            .sorted { $0.date < $1.date }

        var count = 0
        var cursor = elevatedTemps.last?.date
        while let date = cursor, elevatedTemps.contains(where: { CycleDate.isSameDay($0.date, date) }) {
            count += 1
            cursor = CycleDate.addDays(-1, to: date)
        }

        let recentTemps = elevatedTemps.suffix(count)
        let kind: TemperatureSignalKind
        if recentTemps.contains(where: { $0.type == .bbt }) {
            kind = .bbt
        } else if count > 0 {
            kind = .wristTemp
        } else {
            kind = .none
        }

        return TemperatureSignal(
            count: count,
            kind: kind,
            isSustained: kind == .bbt ? count >= 3 : count >= 6
        )
    }

    private static func signalConflicts(
        on date: Date,
        observations: [CycleObservation],
        positiveLHDate: Date?,
        sustainedTemperatureRise: Bool
    ) -> [String] {
        var conflicts: [String] = []
        let bleedingToday = observations.contains { CycleDate.isSameDay($0.date, date) && $0.type == .bleeding }
        if bleedingToday, let positiveLHDate, abs(CycleDate.daysBetween(positiveLHDate, date)) <= 1 {
            conflicts.append("bleeding overlaps LH surge")
        }
        if bleedingToday, sustainedTemperatureRise {
            conflicts.append("bleeding overlaps elevated temperature")
        }
        return conflicts
    }

    private static func nextPredictedEvent(
        for day: CycleDayModel,
        observations: [CycleObservation],
        cycleHistory: [CycleHistory],
        fallbackCycleLength: Int
    ) -> String {
        let latestLH = latestPositiveLH(observations: observations, through: day.date)
        let latestOnset = latestBleedingOnset(observations: observations, through: day.date)
        let predictedLength = predictedCycleLength(from: cycleHistory, fallback: fallbackCycleLength)

        if day.estimate.phase == .ovulatory {
            let daysFromLH = latestLH.map { CycleDate.daysBetween($0.date, day.date) } ?? 0
            return daysFromLH <= 0 ? "Ovulation probable in 1 day" : "Ovulation window now"
        }

        let nextPeriodDate = latestLH.map { CycleDate.addDays(14, to: $0.date) }
            ?? latestOnset.map { CycleDate.addDays(predictedLength, to: $0) }

        if let nextPeriodDate {
            let daysUntil = CycleDate.daysBetween(day.date, nextPeriodDate)
            if daysUntil == 0 { return "Period estimated today" }
            if daysUntil > 0 { return "Period estimated in \(daysUntil) day\(daysUntil == 1 ? "" : "s")" }
        }

        if let latestOnset {
            let predictedOvulation = CycleDate.addDays(max(12, predictedLength - 14), to: latestOnset)
            let daysUntil = CycleDate.daysBetween(day.date, predictedOvulation)
            if daysUntil > 0 { return "Ovulation estimated in \(daysUntil) days" }
        }

        return "Prediction updates with more data"
    }

    private static func symptomBurden(in observations: [CycleObservation]) -> Double {
        let severities = observations.compactMap(\.value.symptomSeverity)
        guard !severities.isEmpty else { return 0 }
        let average = Double(severities.reduce(0, +)) / Double(severities.count)
        return (average * 100).rounded() / 100
    }

    private static func symptomObservations(in observations: [CycleObservation]) -> [CycleObservation] {
        observations.filter { $0.type == .symptom }
    }

    private static func chartSummary(for day: CycleDayModel) -> String {
        let symptoms = symptomObservations(in: day.observations).compactMap(\.value.symptomName)
        let sleepText = day.observations.first(where: { $0.type == .sleep })?.value.sleepMinutes.map {
            " Sleep was \($0.hoursMinutesText) with \(day.observations.first(where: { $0.type == .sleep })?.value.sleepAwakenings ?? 0) awakenings."
        } ?? ""

        if symptoms.isEmpty {
            return "No symptoms logged for \(day.monthDayText).\(sleepText)"
        }

        return "Symptoms are \(day.symptomBurden.burdenText) today: \(symptoms.joined(separator: ", ")).\(sleepText)"
    }

    private static func timelineSummary(days: [CycleDayModel]) -> String {
        let today = days.first(where: \.isToday) ?? days[days.count / 2]
        return "\(CyclePalette.phase(today.estimate.phase).name) estimate strength is \(today.estimate.confidenceLabel.rawValue.lowercased()); confidence improves as cycle history, LH, and sustained temperature signals align."
    }

    private static func median(_ values: [Int]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return Double(sorted[middle - 1] + sorted[middle]) / 2
        }
        return Double(sorted[middle])
    }

    private static func compactTags(_ tags: [String?]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap { tag in
            guard let tag, !seen.contains(tag) else { return nil }
            seen.insert(tag)
            return tag
        }
    }
}

private struct TemperatureSignal: Equatable {
    let count: Int
    let kind: TemperatureSignalKind
    let isSustained: Bool
}

private enum TemperatureSignalKind: Equatable {
    case none
    case wristTemp
    case bbt

    var title: String {
        switch self {
        case .none: "Temperature"
        case .wristTemp: "Wrist temp"
        case .bbt: "BBT"
        }
    }
}

private extension CycleObservationType {
    var isModelSignal: Bool {
        switch self {
        case .bleeding, .lhTest, .wristTemp, .bbt:
            true
        case .symptom, .sleep, .workout:
            false
        }
    }
}

private extension CycleObservationValue {
    var isPositiveLH: Bool {
        if case .lhTest(result: .positive, ratio: _) = self { return true }
        return false
    }

    var isElevatedTemperature: Bool {
        if case .temperature(deviationC: let deviationC, elevated: let elevated) = self {
            return elevated && deviationC >= 0.20
        }
        return false
    }

    var symptomSeverity: Int? {
        if case .symptom(_, severity: let severity) = self { return severity }
        return nil
    }

    var symptomName: String? {
        if case .symptom(let symptom, severity: _) = self { return symptom.title }
        return nil
    }

    var sleepMinutes: Int? {
        if case .sleep(durationMinutes: let durationMinutes, awakenings: _, efficiency: _) = self { return durationMinutes }
        return nil
    }

    var sleepAwakenings: Int? {
        if case .sleep(durationMinutes: _, awakenings: let awakenings, efficiency: _) = self { return awakenings }
        return nil
    }

    var workoutIntensity: WorkoutIntensity? {
        if case .workout(kind: _, planned: _, intensity: let intensity, durationMinutes: _) = self { return intensity }
        return nil
    }

    var isHeavyBleeding: Bool {
        if case .bleeding(flow: .heavy, heavyBleeding: _) = self { return true }
        if case .bleeding(flow: _, heavyBleeding: true) = self { return true }
        return false
    }
}

private struct CyclePhaseToken {
    let name: String
    let marker: String
    let subtitle: String
    let accent: Color
    let tint: Color
}

private enum CyclePalette {
    static let primaryText = Color.white.opacity(0.96)
    static let secondaryText = Color(red: 0.84, green: 0.84, blue: 0.90).opacity(0.84)
    static let tertiaryText = Color.white.opacity(0.58)
    static let softText = secondaryText
    static let premiumGlassAccent = Color(red: 0.56, green: 0.70, blue: 0.76)
    static let premiumGold = Color(red: 0.90, green: 0.72, blue: 0.42)
    static let premiumRose = Color(red: 0.86, green: 0.30, blue: 0.38)
    static let sheetHandleFill = Color(red: 0.82, green: 0.80, blue: 0.90).opacity(0.58)
    static let dailyLogSecondaryText = Color(red: 0.84, green: 0.82, blue: 0.91).opacity(0.94)
    static let dailyLogLavenderText = Color(red: 0.77, green: 0.62, blue: 0.98).opacity(0.94)
    static let dailyLogSelectedText = Color(red: 0.94, green: 0.89, blue: 1.0).opacity(0.98)
    static let dailyLogBleedingAccent = Color(red: 1.0, green: 0.46, blue: 0.53)

    static func phase(_ phase: CyclePhase) -> CyclePhaseToken {
        switch phase {
        case .menstrual:
            CyclePhaseToken(
                name: "Menstrual",
                marker: "M",
                subtitle: "Bleeding phase. Lower-pressure movement and recovery cues are prioritized.",
                accent: Color(red: 0.78, green: 0.25, blue: 0.31),
                tint: Color(red: 0.98, green: 0.86, blue: 0.89)
            )
        case .follicular:
            CyclePhaseToken(
                name: "Follicular",
                marker: "F",
                subtitle: "Building phase. Training readiness can rise when sleep and symptoms cooperate.",
                accent: Color(red: 0.13, green: 0.50, blue: 0.45),
                tint: Color(red: 0.84, green: 0.94, blue: 0.91)
            )
        case .ovulatory:
            CyclePhaseToken(
                name: "Ovulatory",
                marker: "O",
                subtitle: "Ovulation window. Strong LH evidence can sharpen phase confidence.",
                accent: Color(red: 0.62, green: 0.42, blue: 0.10),
                tint: Color(red: 0.96, green: 0.90, blue: 0.75)
            )
        case .luteal:
            CyclePhaseToken(
                name: "Luteal",
                marker: "L",
                subtitle: "Post-ovulatory phase. Appetite, temperature, and recovery needs may trend higher.",
                accent: Color(red: 0.43, green: 0.33, blue: 0.66),
                tint: Color(red: 0.91, green: 0.88, blue: 0.98)
            )
        case .uncertain:
            CyclePhaseToken(
                name: "Uncertain",
                marker: "?",
                subtitle: "Signals are limited or conflicting. Recommendations lean on today's logs.",
                accent: Color.secondary,
                tint: Color.secondary.opacity(0.12)
            )
        }
    }

    static func cardFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.048)
            : Color.white.opacity(0.74)
    }

    static func cardBackground(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color.white.opacity(0.095),
                    Color(red: 0.06, green: 0.055, blue: 0.075).opacity(0.88),
                    Color(red: 0.15, green: 0.10, blue: 0.18).opacity(0.22)
                ]
                : [
                    Color.white.opacity(0.92),
                    Color(red: 0.98, green: 0.96, blue: 0.98).opacity(0.74),
                    Color(red: 0.91, green: 0.97, blue: 1.00).opacity(0.42)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func cardBorder(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.18 : 0.86),
                Color(red: 0.92, green: 0.36, blue: 0.50).opacity(colorScheme == .dark ? 0.14 : 0.18),
                Color.black.opacity(colorScheme == .dark ? 0.20 : 0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func cardStroke(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white.opacity(0.16) : .white.opacity(0.72)
    }

    static func cardShadow(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .black.opacity(0.28) : Color(red: 0.50, green: 0.44, blue: 0.48).opacity(0.10)
    }

    static func glassTint(for colorScheme: ColorScheme, opacity: Double) -> LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color.white.opacity(0.052),
                    Color(red: 0.020, green: 0.030, blue: 0.060).opacity(0.24),
                    Color.black.opacity(0.050),
                    premiumGlassAccent.opacity(min(opacity * 0.20, 0.018))
                ]
                : [
                    Color.white.opacity(0.56),
                    Color(red: 0.91, green: 0.95, blue: 0.98).opacity(0.20),
                    premiumGlassAccent.opacity(min(opacity * 0.32, 0.070))
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func glassEffectTint(for colorScheme: ColorScheme, opacity: Double) -> Color {
        Color(red: 0.010, green: 0.022, blue: 0.052)
            .opacity(colorScheme == .dark ? min(opacity + 0.015, 0.090) : min(opacity + 0.050, 0.14))
    }

    static func glassSpecularHighlight(for colorScheme: ColorScheme) -> RadialGradient {
        RadialGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.064 : 0.46),
                Color.white.opacity(colorScheme == .dark ? 0.012 : 0.16),
                .clear
            ],
            center: .topLeading,
            startRadius: 0,
            endRadius: colorScheme == .dark ? 280 : 340
        )
    }

    static func glassReadabilityWash(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [
                .clear,
                Color.black.opacity(colorScheme == .dark ? 0.040 : 0.015),
                Color.black.opacity(colorScheme == .dark ? 0.086 : 0.04)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func glassBorder(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.22 : 0.76),
                Color.white.opacity(colorScheme == .dark ? 0.045 : 0.30),
                premiumGlassAccent.opacity(colorScheme == .dark ? 0.13 : 0.30),
                Color.black.opacity(colorScheme == .dark ? 0.10 : 0.07)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func toolbarGlassFill(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.065 : 0.54),
                Color(red: 0.025, green: 0.032, blue: 0.062).opacity(colorScheme == .dark ? 0.20 : 0.10),
                premiumGlassAccent.opacity(colorScheme == .dark ? 0.025 : 0.12),
                Color.black.opacity(colorScheme == .dark ? 0.14 : 0.02)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func toolbarGlassBorder(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.30 : 0.78),
                premiumGlassAccent.opacity(colorScheme == .dark ? 0.14 : 0.34),
                Color.black.opacity(colorScheme == .dark ? 0.16 : 0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var logoGlassFill: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.082),
                Color(red: 0.032, green: 0.038, blue: 0.066).opacity(0.34),
                phase(.luteal).accent.opacity(0.16),
                Color.black.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var pillGlassFill: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.075),
                Color(red: 0.036, green: 0.044, blue: 0.072).opacity(0.24),
                Color.black.opacity(0.055)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func readablePanelFill(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color.white.opacity(0.072),
                    Color(red: 0.030, green: 0.042, blue: 0.074).opacity(0.54),
                    Color.black.opacity(0.24)
                ]
                : [
                    Color.white.opacity(0.78),
                    Color(red: 0.94, green: 0.92, blue: 0.98).opacity(0.70),
                    Color.white.opacity(0.54)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func readablePanelBorder(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.24 : 0.74),
                premiumGlassAccent.opacity(colorScheme == .dark ? 0.14 : 0.34),
                Color.black.opacity(colorScheme == .dark ? 0.20 : 0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func calendarCellFill(isSelected: Bool) -> LinearGradient {
        LinearGradient(
            colors: isSelected
                ? [
                    Color.white.opacity(0.130),
                    Color(red: 0.030, green: 0.046, blue: 0.080).opacity(0.58),
                    premiumGlassAccent.opacity(0.072)
                ]
                : [
                    Color.white.opacity(0.055),
                    Color(red: 0.026, green: 0.034, blue: 0.060).opacity(0.34),
                    Color.black.opacity(0.10)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func calendarMarkerFill(isSelected: Bool) -> LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(isSelected ? 0.24 : 0.15),
                Color(red: 0.035, green: 0.050, blue: 0.086).opacity(isSelected ? 0.46 : 0.30),
                premiumGlassAccent.opacity(isSelected ? 0.12 : 0.060)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static let chartAccent = Color(red: 0.60, green: 0.74, blue: 0.76)

    static var chartAreaFill: LinearGradient {
        LinearGradient(
            colors: [
                chartAccent.opacity(0.18),
                Color.white.opacity(0.040),
                Color.black.opacity(0.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static func confidenceBarFill(isToday: Bool) -> LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(isToday ? 0.24 : 0.15),
                Color(red: 0.040, green: 0.054, blue: 0.086).opacity(isToday ? 0.48 : 0.34),
                premiumGlassAccent.opacity(isToday ? 0.16 : 0.060)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func confidenceBarStroke(isToday: Bool) -> Color {
        isToday ? chartAccent.opacity(0.70) : .white.opacity(0.11)
    }
}

private extension CycleSymptomKind {
    var dailyLogSymbolName: String {
        switch self {
        case .cramps: "water.waves"
        case .bloating: "sparkle.magnifyingglass"
        case .fatigue: "battery.25"
        case .moodShift: "face.smiling"
        case .breastTenderness: "target"
        case .headache: "head.profile"
        case .cravings: "heart"
        case .lowEnergy: "bolt"
        case .sleepDisruption: "moon.zzz"
        case .libido: "heart"
        case .cervicalFluid: "drop"
        case .nausea: "water.waves"
        }
    }
}

private enum CycleDate {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    static func make(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    static func addDays(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: date)) ?? date
    }

    static func addMonths(_ months: Int, to date: Date) -> Date {
        calendar.date(byAdding: .month, value: months, to: monthStart(for: date)) ?? date
    }

    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static func monthStart(for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components).map(calendar.startOfDay(for:)) ?? calendar.startOfDay(for: date)
    }

    static func daysBetween(_ start: Date, _ end: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }

    static func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
    }

    static func range(start: Date, count: Int) -> [Date] {
        (0..<count).map { addDays($0, to: start) }
    }

    static var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let firstIndex = max(calendar.firstWeekday - 1, 0)
        return Array(symbols[firstIndex...] + symbols[..<firstIndex]).map { String($0.prefix(2)).uppercased() }
    }

    static func monthGridDates(for month: Date) -> [Date?] {
        let start = monthStart(for: month)
        guard let range = calendar.range(of: .day, in: .month, for: start) else { return [] }
        let weekday = calendar.component(.weekday, from: start)
        let leadingBlanks = (weekday - calendar.firstWeekday + 7) % 7
        let monthDates = range.compactMap { day -> Date? in
            calendar.date(byAdding: .day, value: day - 1, to: start).map(calendar.startOfDay(for:))
        }
        let cells: [Date?] = Array(repeating: nil, count: leadingBlanks) + monthDates.map(Optional.some)
        let trailingBlanks = (7 - cells.count % 7) % 7
        return cells + Array(repeating: nil, count: trailingBlanks)
    }
}

private extension Date {
    var weekdayShortText: String {
        formatted(.dateTime.weekday(.abbreviated))
    }

    var dayNumberText: String {
        formatted(.dateTime.day())
    }

    var monthDayText: String {
        formatted(.dateTime.month(.abbreviated).day())
    }
}

private extension Int {
    var hoursMinutesText: String {
        "\(self / 60)h \(self % 60)m"
    }
}

private extension Double {
    var percentText: String {
        "\(Int((self * 100).rounded()))%"
    }

    var qualityText: String {
        if self >= 0.90 { return "High quality" }
        if self >= 0.75 { return "Good quality" }
        return "Low quality"
    }

    var burdenText: String {
        if self >= 2.25 { return "high" }
        if self >= 1.25 { return "moderate" }
        if self > 0 { return "low" }
        return "not logged"
    }
}

private struct CycleModuleBackground: View {
    var body: some View {
        GeometryReader { proxy in
            Image("CycleBackground")
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.00),
                            Color.black.opacity(0.06),
                            Color(red: 0.05, green: 0.07, blue: 0.11).opacity(0.16)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        }
        .ignoresSafeArea()
    }
}

private enum CyclePreviewData {
    static var trackedState: CycleTrackingState {
        let today = CycleDate.startOfDay(.now)
        let latestStart = CycleDate.addDays(-25, to: today)
        let bleedingDates = (0..<5).map { CycleDate.addDays($0, to: latestStart) }
        return CycleTrackingState(
            bleedingDates: bleedingDates,
            lastPeriodStartDate: latestStart,
            averageCycleLength: 28,
            averagePeriodLength: 5,
            onboardingCompleted: true,
            notesByDateKey: [:]
        )
    }

    static var dailyLogState: CycleTrackingState {
        let today = CycleDate.startOfDay(.now)
        let latestStart = CycleDate.addDays(-41, to: today)
        let bleedingDates = (0..<4).map { CycleDate.addDays($0, to: latestStart) }
        return CycleTrackingState(
            bleedingDates: bleedingDates,
            lastPeriodStartDate: latestStart,
            averageCycleLength: 28,
            averagePeriodLength: 4,
            onboardingCompleted: true,
            notesByDateKey: [
                CycleTrackingCalculator.dateKey(for: today): "Slept lightly, planning an easier evening."
            ],
            bleedingLogs: [
                BleedingLog(date: today, intensity: .light)
            ],
            symptomLogs: [
                SymptomLog(date: today, kind: .cramps, severity: 2),
                SymptomLog(date: today, kind: .bloating, severity: 2),
                SymptomLog(date: today, kind: .breastTenderness, severity: 2),
                SymptomLog(date: today, kind: .lowEnergy, severity: 2)
            ]
        )
    }
}

#Preview("Cycle Data") {
    CycleView(trackingStore: CycleTrackingStore(initialState: CyclePreviewData.trackedState))
}

#Preview("Onboarding") {
    CycleView(trackingStore: CycleTrackingStore(initialState: .empty))
}

#Preview("Daily Log") {
    CycleDailyLogSheet(
        trackingStore: CycleTrackingStore(initialState: CyclePreviewData.dailyLogState),
        date: CycleDate.startOfDay(.now)
    )
}
