//
//  WorkoutCompleteView.swift
//  Pulsar
//

import SwiftUI
import UIKit

struct WorkoutCompleteView<Details: View>: View {
    private enum ShareContent: Identifiable {
        case gym(PulsarGymWorkoutSummary)
        case run(PulsarRunSummary)

        var id: String {
            switch self {
            case .gym(let summary): "gym-\(summary.sessionId.uuidString)"
            case .run(let summary): "run-\((summary.pulsarWorkoutSessionId ?? summary.id).uuidString)"
            }
        }
    }

    private let title: String
    private let emoji: String
    private let workoutName: String
    private let sourceDeviceName: String
    private let sourceSystemImage: String
    private let startedAt: Date?
    private let heartRateSourceText: String?
    private let metrics: [WorkoutSummaryMetric]
    private let shareContent: ShareContent
    private let shareTitle: String
    private let accent: Color
    private let onDone: (() -> Void)?
    private let details: Details

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var hasAppeared = false
    @State private var isShowingShareComposer = false

    init(
        gymSummary summary: PulsarGymWorkoutSummary,
        onDone: @escaping () -> Void,
        @ViewBuilder details: () -> Details
    ) {
        self.title = "Workout Complete"
        self.emoji = summary.routineEmoji
        self.workoutName = summary.routineName
        self.sourceDeviceName = summary.sourceDeviceName
        self.sourceSystemImage = summary.source == .appleWatch || summary.source == .iPhoneRequestedWatchStart ? "applewatch" : "iphone"
        self.startedAt = summary.startedAt
        self.heartRateSourceText = summary.heartRateSourceSummaryText
        self.metrics = WorkoutCompletionContentBuilder.metrics(for: summary)
        self.shareContent = .gym(summary)
        self.shareTitle = "Share"
        self.accent = Color(red: 0.55, green: 1.0, blue: 0.64)
        self.onDone = onDone
        self.details = details()
    }

    init(
        runSummary summary: PulsarRunSummary,
        onDone: (() -> Void)? = nil,
        @ViewBuilder details: () -> Details
    ) {
        self.title = "Workout Complete"
        self.emoji = summary.workoutKind == .cycling ? "🚲" : "🏃"
        self.workoutName = summary.workoutKind.outdoorTitle
        self.sourceDeviceName = summary.sourceDeviceName
        self.sourceSystemImage = summary.source == .appleWatch ? "applewatch" : "iphone"
        self.startedAt = summary.startedAt
        self.heartRateSourceText = summary.heartRateSourceSummaryText
        self.metrics = WorkoutCompletionContentBuilder.metrics(for: summary)
        self.shareContent = .run(summary)
        self.shareTitle = summary.workoutKind.isOutdoorDistanceWorkout || summary.distanceMeters > 10 ? "Share Route" : "Share"
        self.accent = summary.workoutKind.accentColor
        self.onDone = onDone
        self.details = details()
    }

    var body: some View {
        ZStack {
            completionBackdrop

            ScrollView {
                PulsarGlassEffectGroup(spacing: 22) {
                    VStack(spacing: 18) {
                        WorkoutCompleteHeader(
                            title: title,
                            emoji: emoji,
                            workoutName: workoutName,
                            sourceDeviceName: sourceDeviceName,
                            sourceSystemImage: sourceSystemImage,
                            startedAt: startedAt,
                            heartRateSourceText: heartRateSourceText,
                            accent: accent,
                            hasAppeared: hasAppeared
                        )
                        .padding(.top, 8)

                        WorkoutCompleteMetricGrid(
                            metrics: metrics,
                            columns: metricColumnCount,
                            hasAppeared: hasAppeared
                        )

                        details

                        WorkoutCompleteActions(
                            shareTitle: shareTitle,
                            accent: accent,
                            onShare: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                isShowingShareComposer = true
                            },
                            onDone: onDone.map { done in
                                {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    done()
                                }
                            }
                        )
                    }
                    .padding(22)
                    .background(containerBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .stroke(.white.opacity(reduceTransparency ? 0.28 : 0.20), lineWidth: 1)
                    }
                    .shadow(color: accent.opacity(reduceTransparency ? 0.10 : 0.22), radius: 34, y: 18)
                    .shadow(color: .black.opacity(0.32), radius: 28, y: 20)
                    .pulsarLiquidGlass(cornerRadius: 34, tint: accent.opacity(0.10), interactive: false, isClear: true)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 28)
                    .frame(maxWidth: 430)
                    .frame(maxWidth: .infinity)
                    .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.96)
                    .opacity(hasAppeared ? 1 : 0)
                }
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard !hasAppeared else { return }
            if !reduceMotion {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                    hasAppeared = true
                }
            } else {
                hasAppeared = true
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        .sheet(isPresented: $isShowingShareComposer) {
            switch shareContent {
            case .gym(let summary):
                PulsarWorkoutShareComposerView(gymSummary: summary)
            case .run(let summary):
                PulsarWorkoutShareComposerView(summary: summary)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var metricColumnCount: Int {
        dynamicTypeSize >= .accessibility2 ? 1 : 2
    }

    private var completionBackdrop: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.90),
                Color(red: 0.03, green: 0.10, blue: 0.16).opacity(0.86),
                Color(red: 0.04, green: 0.01, blue: 0.08).opacity(0.92)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            RadialGradient(
                colors: [
                    accent.opacity(reduceTransparency ? 0.10 : 0.25),
                    Color.clear
                ],
                center: .top,
                startRadius: 30,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }

    private var containerBackground: some View {
        RoundedRectangle(cornerRadius: 34, style: .continuous)
            .fill(Color.black.opacity(reduceTransparency ? 0.88 : 0.30))
            .overlay {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(reduceTransparency ? 0.06 : 0.16),
                                accent.opacity(reduceTransparency ? 0.03 : 0.08),
                                .black.opacity(reduceTransparency ? 0.12 : 0.28)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
    }
}

extension WorkoutCompleteView where Details == EmptyView {
    init(gymSummary summary: PulsarGymWorkoutSummary, onDone: @escaping () -> Void) {
        self.init(gymSummary: summary, onDone: onDone) {
            EmptyView()
        }
    }

    init(runSummary summary: PulsarRunSummary, onDone: (() -> Void)? = nil) {
        self.init(runSummary: summary, onDone: onDone) {
            EmptyView()
        }
    }
}

private struct WorkoutCompleteHeader: View {
    var title: String
    var emoji: String
    var workoutName: String
    var sourceDeviceName: String
    var sourceSystemImage: String
    var startedAt: Date?
    var heartRateSourceText: String?
    var accent: Color
    var hasAppeared: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 34
    @ScaledMetric(relativeTo: .headline) private var workoutNameSize: CGFloat = 18
    @ScaledMetric(relativeTo: .subheadline) private var metadataSize: CGFloat = 15
    @ScaledMetric(relativeTo: .caption) private var footnoteSize: CGFloat = 13

    var body: some View {
        VStack(spacing: 14) {
            WorkoutCompleteSuccessOrb(accent: accent, hasAppeared: hasAppeared)

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: titleSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .accessibilityAddTraits(.isHeader)

                VStack(spacing: 7) {
                    HStack(spacing: 8) {
                        Text(emoji)
                        Text(workoutName)
                    }
                    .font(.system(size: workoutNameSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.74)

                    Label(sourceDeviceName, systemImage: sourceSystemImage)
                        .font(.system(size: metadataSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))

                    if let startedAt {
                        Text(startedAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute()))
                            .font(.system(size: metadataSize, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.54))
                            .multilineTextAlignment(.center)
                    }

                    if let heartRateSourceText {
                        Label(heartRateSourceText, systemImage: "heart.text.square.fill")
                            .font(.system(size: footnoteSize, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.54))
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(workoutName), \(sourceDeviceName)")
    }
}

private struct WorkoutCompleteSuccessOrb: View {
    var accent: Color
    var hasAppeared: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.20))
                .frame(width: 104, height: 104)
                .blur(radius: 16)
                .scaleEffect(hasAppeared && !reduceMotion ? 1.10 : 0.78)

            Image(systemName: "checkmark")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.76, green: 1.0, blue: 0.80))
                .frame(width: 86, height: 86)
                .background(PulsarCircularGlassSurface(cornerRadius: 43, tint: accent.opacity(0.75)))
                .shadow(color: accent.opacity(0.55), radius: hasAppeared && !reduceMotion ? 24 : 12)
        }
        .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.80)
        .animation(reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.72).delay(0.04), value: hasAppeared)
        .accessibilityHidden(true)
    }
}

private struct WorkoutCompleteMetricGrid: View {
    var metrics: [WorkoutSummaryMetric]
    var columns: Int
    var hasAppeared: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12), count: columns),
            spacing: 12
        ) {
            ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                WorkoutCompleteMetricCard(metric: metric)
                    .gridCellColumns(metric.layout == .fullWidth || columns == 1 ? columns : 1)
                    .opacity(hasAppeared || reduceMotion ? 1 : 0)
                    .offset(y: hasAppeared || reduceMotion ? 0 : 8)
                    .animation(
                        reduceMotion ? nil : .easeOut(duration: 0.24).delay(Double(index) * 0.03 + 0.10),
                        value: hasAppeared
                    )
            }
        }
    }
}

private struct WorkoutCompleteMetricCard: View {
    var metric: WorkoutSummaryMetric
    @ScaledMetric(relativeTo: .title3) private var valueSize: CGFloat = 24
    @ScaledMetric(relativeTo: .subheadline) private var labelSize: CGFloat = 15

    var body: some View {
        HStack(spacing: 13) {
            PulsarGlassIconCircle(size: 52, tint: metric.tint, systemImage: metric.systemImage, symbolScale: 0.42)

            VStack(alignment: .leading, spacing: 4) {
                Text(metric.value)
                    .font(.system(size: valueSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)

                Text(metric.title)
                    .font(.system(size: labelSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            }

            Spacer(minLength: 0)
        }
        .frame(minHeight: 88)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.20))
                .overlay {
                    LinearGradient(
                        colors: [.white.opacity(0.15), metric.tint.opacity(0.08), .black.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .pulsarLiquidGlass(cornerRadius: 24, tint: metric.tint.opacity(0.08), interactive: false, isClear: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.title)
        .accessibilityValue(metric.accessibilityValue)
    }
}

private struct WorkoutCompleteActions: View {
    var shareTitle: String
    var accent: Color
    var onShare: () -> Void
    var onDone: (() -> Void)?
    @ScaledMetric(relativeTo: .title3) private var buttonTitleSize: CGFloat = 22

    var body: some View {
        VStack(spacing: 12) {
            Button(action: onShare) {
                Label(shareTitle, systemImage: "square.and.arrow.up")
                    .font(.system(size: buttonTitleSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.24),
                                        accent.opacity(0.62),
                                        Color(red: 0.34, green: 0.90, blue: 0.48).opacity(0.80)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(.white.opacity(0.34), lineWidth: 1)
                    }
                    .shadow(color: accent.opacity(0.32), radius: 18, y: 8)
            }
            .buttonStyle(PulsarGymPressButtonStyle())
            .accessibilityLabel(shareTitle)

            if let onDone {
                Button(action: onDone) {
                    Text("Done")
                        .font(.system(size: buttonTitleSize, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(.white.opacity(0.10), in: Capsule(style: .continuous))
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(.white.opacity(0.16), lineWidth: 1)
                        }
                    }
                .buttonStyle(PulsarGymPressButtonStyle())
                .accessibilityLabel("Done")
            }
        }
    }
}
