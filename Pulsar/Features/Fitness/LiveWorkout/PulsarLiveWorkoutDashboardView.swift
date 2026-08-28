//
//  PulsarLiveWorkoutDashboardView.swift
//  Pulsar
//

import SwiftUI
import UIKit

struct PulsarLiveWorkoutDashboardView<Background: View>: View {
    var state: PulsarLiveWorkoutDashboardState
    var closeSymbolName: String = "chevron.down"
    var closeAccessibilityLabel: String = "Close workout"
    var secondaryActionSymbolName: String?
    var secondaryActionAccessibilityLabel: String?
    var onClose: () -> Void
    var onSecondaryAction: (() -> Void)?
    var onTogglePause: () -> Void
    var onEnd: () -> Void
    var onOpenNowPlaying: () -> Void
    var onToggleMusicPlayback: () -> Void
    var onNextTrack: () -> Void
    var onPreviousTrack: () -> Void
    var onLock: (() -> Void)?
    var background: Background

    @State private var showingEndConfirmation = false

    init(
        state: PulsarLiveWorkoutDashboardState,
        closeSymbolName: String = "chevron.down",
        closeAccessibilityLabel: String = "Close workout",
        secondaryActionSymbolName: String? = nil,
        secondaryActionAccessibilityLabel: String? = nil,
        onClose: @escaping () -> Void,
        onSecondaryAction: (() -> Void)? = nil,
        onTogglePause: @escaping () -> Void,
        onEnd: @escaping () -> Void,
        onOpenNowPlaying: @escaping () -> Void,
        onToggleMusicPlayback: @escaping () -> Void = {},
        onNextTrack: @escaping () -> Void = {},
        onPreviousTrack: @escaping () -> Void = {},
        onLock: (() -> Void)? = nil,
        @ViewBuilder background: () -> Background
    ) {
        self.state = state
        self.closeSymbolName = closeSymbolName
        self.closeAccessibilityLabel = closeAccessibilityLabel
        self.secondaryActionSymbolName = secondaryActionSymbolName
        self.secondaryActionAccessibilityLabel = secondaryActionAccessibilityLabel
        self.onClose = onClose
        self.onSecondaryAction = onSecondaryAction
        self.onTogglePause = onTogglePause
        self.onEnd = onEnd
        self.onOpenNowPlaying = onOpenNowPlaying
        self.onToggleMusicPlayback = onToggleMusicPlayback
        self.onNextTrack = onNextTrack
        self.onPreviousTrack = onPreviousTrack
        self.onLock = onLock
        self.background = background()
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if state.isPremiumNonGPS {
                    PulsarPremiumWorkoutBackground()
                        .ignoresSafeArea()

                    PulsarPremiumWorkoutAtmosphere()
                        .allowsHitTesting(false)
                } else {
                    background
                        .ignoresSafeArea()

                    PulsarLiveWorkoutAtmosphere(tint: state.tint, glowColor: state.glowColor)
                        .allowsHitTesting(false)
                }

                if state.isPremiumNonGPS {
                    premiumContent(proxy: proxy)
                } else {
                    VStack(spacing: 12) {
                        topBar
                            .padding(.horizontal, 16)
                            .padding(.top, max(12, proxy.safeAreaInsets.top + 6))

                        ScrollView(showsIndicators: false) {
                            cards
                                .padding(.horizontal, 16)
                                .padding(.top, 6)
                                .padding(.bottom, 16)
                        }
                        .scrollContentBackground(.hidden)
                        .contentMargins(.bottom, 4, for: .scrollContent)

                        controls
                            .padding(.horizontal, 16)
                            .padding(.bottom, max(16, proxy.safeAreaInsets.bottom + 8))
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .persistentSystemOverlays(.hidden)
        .pulsarFitnessMonochromeAppearance()
        .confirmationDialog("End this \(state.title.lowercased())?", isPresented: $showingEndConfirmation, titleVisibility: .visible) {
            Button("End Workout", role: .destructive) {
                onEnd()
            }
            Button("Keep Going", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func premiumContent(proxy: GeometryProxy) -> some View {
        let layout = premiumLayout(for: proxy)

        ViewThatFits(in: .vertical) {
            premiumStack(layout: layout)
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.top, layout.topPadding)
                .padding(.bottom, layout.bottomPadding)

            ScrollView(showsIndicators: false) {
                premiumStack(layout: layout)
                    .padding(.horizontal, layout.horizontalPadding)
                    .padding(.top, layout.topPadding)
                    .padding(.bottom, layout.bottomPadding)
            }
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, 4, for: .scrollContent)
        }
    }

    private func premiumStack(layout: PulsarPremiumWorkoutLayout) -> some View {
        VStack(spacing: layout.sectionSpacing) {
            premiumHeader(layout: layout)
            premiumCards(layout: layout)
            premiumControls(layout: layout)
        }
    }

    private func premiumHeader(layout: PulsarPremiumWorkoutLayout) -> some View {
        HStack(alignment: .center, spacing: layout.headerSpacing) {
            VStack(alignment: .leading, spacing: layout.isCompact ? 4 : 5) {
                Label(state.statusText, systemImage: "chart.bar.fill")
                    .font(.system(size: layout.liveBadgeFontSize, weight: .bold, design: .default))
                    .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                    .padding(.horizontal, layout.isCompact ? 8 : 9)
                    .padding(.vertical, layout.isCompact ? 4 : 5)
                    .background(.black.opacity(0.055), in: Capsule(style: .continuous))

                VStack(alignment: .leading, spacing: 0) {
                    Text(state.title)
                        .font(.system(size: layout.titleSize, weight: .bold, design: .default))
                        .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.64)

                    Text(state.subtitle)
                        .font(.system(size: layout.subtitleSize, weight: .medium, design: .default))
                        .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }

            Spacer(minLength: 4)

            PulsarCompactNowPlayingCapsule(
                track: state.nowPlaying,
                controlsDisabled: state.musicControlsDisabled,
                width: layout.topMusicWidth,
                height: layout.topMusicHeight,
                artworkSize: layout.topMusicArtworkSize,
                onOpen: onOpenNowPlaying,
                onTogglePlayback: onToggleMusicPlayback
            )

            PulsarWorkoutToolbarIconButton(
                systemImage: "xmark",
                accessibilityLabel: closeAccessibilityLabel,
                size: layout.closeButtonSize,
                font: .headline.weight(.bold),
                foregroundStyle: .white.opacity(0.88),
                action: onClose
            )
        }
    }

    private func premiumCards(layout: PulsarPremiumWorkoutLayout) -> some View {
        VStack(spacing: layout.cardSpacing) {
            ForEach(state.banners) { banner in
                PulsarLiveWorkoutBannerView(banner: banner)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            HStack(alignment: .center, spacing: layout.cardSpacing) {
                PulsarPremiumHeartRateCard(state: state)
                    .frame(maxWidth: .infinity)
                    .frame(height: layout.heroHeight)

                PulsarPremiumZoneGauge(state: state)
                    .frame(width: layout.gaugeSize, height: layout.gaugeSize)
            }

            PulsarPremiumHeartRateZoneCard(
                state: state,
                contentPadding: layout.zoneCardPadding,
                pillVerticalPadding: layout.zonePillVerticalPadding
            )
            premiumMetricsGrid(layout: layout)
            PulsarPremiumWorkoutInsightCard(state: state, height: layout.insightHeight, isCompact: layout.isCompact)
            PulsarPremiumNowPlayingCard(
                track: state.nowPlaying,
                tint: state.tint,
                height: layout.nowPlayingHeight,
                isCompact: layout.isCompact,
                controlsDisabled: state.musicControlsDisabled,
                onOpen: onOpenNowPlaying,
                onTogglePlayback: onToggleMusicPlayback,
                onNextTrack: onNextTrack,
                onPreviousTrack: onPreviousTrack
            )
        }
    }

    private func premiumMetricsGrid(layout: PulsarPremiumWorkoutLayout) -> some View {
        LazyVGrid(columns: premiumMetricColumns(spacing: layout.metricSpacing), spacing: layout.metricSpacing) {
            ForEach(state.metrics) { metric in
                PulsarPremiumMetricTile(metric: metric, height: layout.metricHeight)
            }
        }
    }

    private func premiumControls(layout: PulsarPremiumWorkoutLayout) -> some View {
        HStack(spacing: layout.controlSpacing) {
            Button(action: { onLock?() }) {
                Image(systemName: "lock.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PulsarLiveWorkoutLockButtonStyle(height: layout.controlHeight))
            .disabled(onLock == nil || state.controlsDisabled || state.isFinishing)
            .frame(width: layout.lockButtonWidth)
            .accessibilityLabel("Lock workout controls")

            Button(action: onTogglePause) {
                Label(state.phase.controlTitle, systemImage: state.phase.controlSymbolName)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PulsarLiveWorkoutControlButtonStyle(tint: state.isPaused ? state.tint : .orange, height: layout.controlHeight))
            .disabled(state.controlsDisabled || state.isFinishing)

            Button {
                showingEndConfirmation = true
            } label: {
                Label("End", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PulsarLiveWorkoutControlButtonStyle(tint: .red, height: layout.controlHeight))
            .disabled(state.controlsDisabled || state.isFinishing)
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            PulsarWorkoutToolbarIconButton(
                systemImage: "music.note",
                accessibilityLabel: "Now Playing",
                action: onOpenNowPlaying
            )

            Label(state.recorderStatusText, systemImage: state.recorderStatusSymbolName)
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .pulsarLiveWorkoutGlass(cornerRadius: 18, tint: state.tint)

            Spacer(minLength: 0)

            PulsarWorkoutToolbarIconButton(
                systemImage: closeSymbolName,
                accessibilityLabel: closeAccessibilityLabel,
                action: onClose
            )

            if let secondaryActionSymbolName, let secondaryActionAccessibilityLabel, let onSecondaryAction {
                PulsarWorkoutToolbarIconButton(
                    systemImage: secondaryActionSymbolName,
                    accessibilityLabel: secondaryActionAccessibilityLabel,
                    action: onSecondaryAction
                )
            }
        }
    }

    @ViewBuilder
    private var cards: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 22) {
                cardStack
            }
        } else {
            cardStack
        }
    }

    private var cardStack: some View {
        VStack(spacing: 12) {
            ForEach(state.banners) { banner in
                PulsarLiveWorkoutBannerView(banner: banner)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            heroCard
            PulsarHeartRateZoneCard(state: state)
            metricsGrid
            PulsarNowPlayingCard(
                track: state.nowPlaying,
                tint: state.tint,
                controlsDisabled: state.musicControlsDisabled,
                onOpen: onOpenNowPlaying,
                onTogglePlayback: onToggleMusicPlayback,
                onNextTrack: onNextTrack,
                onPreviousTrack: onPreviousTrack
            )
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text(state.statusText)
                    } icon: {
                        Image(systemName: state.symbolName)
                    }
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(statusTint)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(statusTint.opacity(0.14), in: Capsule(style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("HEART RATE")
                            .pulsarTextStyle(.overline)
                            .foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(state.heartRateDisplayText)
                                .font(.system(size: state.currentHeartRate == nil ? 28 : 64, weight: .semibold, design: .rounded).monospacedDigit())
                                .lineLimit(2)
                                .minimumScaleFactor(0.50)
                            if !state.heartRateUnitText.isEmpty {
                                Text(state.heartRateUnitText)
                                    .pulsarTextStyle(.cardTitle)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(state.percentOfMaxText)
                            .pulsarTextStyle(.captionEmphasis)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 8) {
                    Text(state.zoneTitleText)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(state.activeZoneColor)
                        .lineLimit(1)
                    Text(state.zoneDetailText)
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                    Text(state.primaryMetricValue)
                        .pulsarTextStyle(.cardTitle)
                                .monospacedDigit()
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(state.activeZoneColor.opacity(0.15), in: Capsule(style: .continuous))
                    Text(state.primaryMetricTitle)
                        .pulsarTextStyle(.overline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 10) {
                PulsarLiveWorkoutStatusPill(
                    title: state.intensityTitle,
                    subtitle: state.intensitySubtitle,
                    symbolName: "waveform.path.ecg",
                    tint: state.activeZoneColor
                )

                PulsarLiveWorkoutStatusPill(
                    title: PulsarRunFormatters.duration(state.elapsedTime),
                    subtitle: "Elapsed",
                    symbolName: "timer",
                    tint: state.tint
                )
            }
        }
        .padding(16)
        .pulsarLiveWorkoutGlass(cornerRadius: 30, tint: state.tint)
        .shadow(color: state.tint.opacity(0.18), radius: 26, y: 14)
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: metricColumns, spacing: 10) {
            ForEach(state.metrics) { metric in
                PulsarLiveWorkoutMetricTile(metric: metric)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button(action: onTogglePause) {
                Label(state.phase.controlTitle, systemImage: state.phase.controlSymbolName)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PulsarLiveWorkoutControlButtonStyle(tint: state.isPaused ? state.tint : .orange))
            .disabled(state.controlsDisabled || state.isFinishing)

            Button {
                showingEndConfirmation = true
            } label: {
                Label("End", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PulsarLiveWorkoutControlButtonStyle(tint: .red))
            .disabled(state.controlsDisabled || state.isFinishing)
        }
    }

    private var metricColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
    }

    private func premiumMetricColumns(spacing: CGFloat) -> [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 0), spacing: spacing), count: 4)
    }

    private var statusTint: Color {
        switch state.phase {
        case .paused: .orange
        case .finishing, .finished: .secondary
        case .preparing, .running: state.tint
        }
    }

    private func premiumLayout(for proxy: GeometryProxy) -> PulsarPremiumWorkoutLayout {
        PulsarPremiumWorkoutLayout(
            size: proxy.size,
            safeAreaInsets: proxy.safeAreaInsets,
            metricCount: state.metrics.count
        )
    }
}

private struct PulsarPremiumWorkoutLayout {
    var size: CGSize
    var safeAreaInsets: EdgeInsets
    var metricCount: Int

    var isCompact: Bool {
        size.height < 780 || size.width < 380 || metricCount > 4
    }

    var horizontalPadding: CGFloat {
        isCompact ? 12 : 16
    }

    var topPadding: CGFloat {
        max(8, safeAreaInsets.top + (isCompact ? -6 : -2))
    }

    var bottomPadding: CGFloat {
        max(8, safeAreaInsets.bottom + (isCompact ? 2 : 5))
    }

    var sectionSpacing: CGFloat {
        isCompact ? 5 : 7
    }

    var cardSpacing: CGFloat {
        isCompact ? 6 : 8
    }

    var metricSpacing: CGFloat {
        isCompact ? 6 : 8
    }

    var headerSpacing: CGFloat {
        isCompact ? 7 : 9
    }

    var controlSpacing: CGFloat {
        isCompact ? 8 : 10
    }

    var liveBadgeFontSize: CGFloat {
        isCompact ? 12 : 13
    }

    var titleSize: CGFloat {
        isCompact ? 23 : 25
    }

    var subtitleSize: CGFloat {
        isCompact ? 13 : 14
    }

    var topMusicWidth: CGFloat {
        min(size.width * (isCompact ? 0.37 : 0.39), isCompact ? 150 : 168)
    }

    var topMusicHeight: CGFloat {
        isCompact ? 48 : 54
    }

    var topMusicArtworkSize: CGFloat {
        isCompact ? 34 : 38
    }

    var closeButtonSize: CGFloat {
        isCompact ? 36 : 40
    }

    var heroHeight: CGFloat {
        isCompact ? 112 : 132
    }

    var gaugeSize: CGFloat {
        isCompact ? 118 : 140
    }

    var zoneCardPadding: CGFloat {
        isCompact ? 11 : 13
    }

    var zonePillVerticalPadding: CGFloat {
        isCompact ? 5 : 7
    }

    var metricHeight: CGFloat {
        isCompact ? 64 : 76
    }

    var insightHeight: CGFloat {
        isCompact ? 58 : 68
    }

    var nowPlayingHeight: CGFloat {
        isCompact ? 64 : 74
    }

    var controlHeight: CGFloat {
        isCompact ? 46 : 52
    }

    var lockButtonWidth: CGFloat {
        isCompact ? 48 : 54
    }
}

private enum PulsarPremiumWorkoutRadius {
    static let smallCard: CGFloat = 16
    static let mediumCard: CGFloat = 18
    static let largeCard: CGFloat = 20
    static let media: CGFloat = 16
    static let control: CGFloat = 18
}

private struct PulsarPremiumWorkoutBackground: View {
    var body: some View {
        PulsarFitnessMonochromeBackground()
    }
}

private struct PulsarPremiumWorkoutAtmosphere: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.012),
                .clear,
                Color.black.opacity(0.007)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

struct PulsarLiveWorkoutAmbientBackground: View {
    var tint: Color
    var glowColor: Color

    var body: some View {
        PulsarFitnessMonochromeDesign.background
        .overlay {
            RadialGradient(
                colors: [.black.opacity(0.028), .clear],
                center: .topTrailing,
                startRadius: 32,
                endRadius: 360
            )
        }
        .overlay {
            LinearGradient(
                colors: [.white.opacity(0.0), .black.opacity(0.025)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

private struct PulsarLiveWorkoutAtmosphere: View {
    var tint: Color
    var glowColor: Color

    var body: some View {
        LinearGradient(
            colors: [
                .white.opacity(0.18),
                .clear,
                .black.opacity(0.018)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.012), .black.opacity(0.035)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 360)
        }
        .ignoresSafeArea()
    }
}

private struct PulsarLiveWorkoutBannerView: View {
    var banner: PulsarLiveWorkoutBanner

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title)
                    .pulsarTextStyle(.captionEmphasis)
                if let message = banner.message {
                    Text(message)
                        .pulsarTextStyle(.captionEmphasis)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } icon: {
            Image(systemName: banner.symbolName)
        }
        .foregroundStyle(banner.tint)
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pulsarLiveWorkoutGlass(cornerRadius: 18, tint: banner.tint)
    }
}

private struct PulsarCompactNowPlayingCapsule: View {
    var track: PulsarNowPlayingTrack
    var controlsDisabled: Bool
    var width: CGFloat = 204
    var height: CGFloat = 64
    var artworkSize: CGFloat = 46
    var onOpen: () -> Void
    var onTogglePlayback: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onOpen) {
                artwork
            }
            .buttonStyle(.plain)

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.displayTitle)
                        .font(.system(size: height < 50 ? 12 : 13, weight: .semibold, design: .default))
                        .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)

                    Text(track.displaySubtitle)
                        .font(.system(size: height < 50 ? 11 : 12, weight: .medium, design: .default))
                        .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(action: onTogglePlayback) {
                Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                    .pulsarTextStyle(.label)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                    .frame(width: height < 50 ? 32 : 36, height: height < 50 ? 32 : 36)
                    .background(.white.opacity(0.72), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(controlsDisabled || !track.isAvailable)
            .opacity(controlsDisabled || !track.isAvailable ? 0.44 : 1)
            .accessibilityLabel(track.isPlaying ? "Pause Music" : "Play Music")
        }
        .padding(height < 50 ? 6 : 7)
        .frame(width: width, height: height)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.92),
                    Color.white.opacity(0.58)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: height / 2, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                .stroke(.black.opacity(0.055), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.22), radius: 12, y: 7)
    }

    @ViewBuilder
    private var artwork: some View {
        if let artworkImage = track.artworkImage {
            Image(uiImage: artworkImage)
                .resizable()
                .scaledToFill()
                .frame(width: artworkSize, height: artworkSize)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.10))
                Image(systemName: "music.note")
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
            }
            .frame(width: artworkSize, height: artworkSize)
        }
    }
}

private struct PulsarPremiumHeartRateCard: View {
    var state: PulsarLiveWorkoutDashboardState

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("HEART RATE")
                .font(.system(size: 11, weight: .semibold, design: .default))
                .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)

            if let currentHeartRate = state.currentHeartRate, currentHeartRate > 0 {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("\(Int(currentHeartRate.rounded()))")
                        .font(.system(size: 44, weight: .bold, design: .default).monospacedDigit())
                        .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.54)
                        .layoutPriority(1)

                    Image(systemName: "heart.fill")
                        .pulsarTextStyle(.cardTitle)
                        .foregroundStyle(.red)
                        .symbolEffect(.pulse, options: .repeating, value: currentHeartRate > 0)

                    Text("bpm")
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                }

                HStack(spacing: 6) {
                    Text("Real-time")
                    Circle()
                        .fill(PulsarFitnessMonochromeDesign.active)
                        .frame(width: 5, height: 5)
                }
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "heart")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)

                    Text(state.heartRatePlaceholderText)
                        .font(.system(size: 17, weight: .semibold, design: .default))
                        .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                        .minimumScaleFactor(0.76)

                    Text(state.percentOfMaxText)
                        .font(.system(size: 11, weight: .medium, design: .default))
                        .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pulsarPremiumWorkoutCard(cornerRadius: PulsarPremiumWorkoutRadius.largeCard)
    }
}

private struct PulsarPremiumZoneGauge: View {
    var state: PulsarLiveWorkoutDashboardState

    private let startDegrees = 132.0
    private let totalDegrees = 276.0
    private let gapDegrees = 8.0

    var body: some View {
        ZStack {
            ForEach(Array(state.zoneProfile.zones.enumerated()), id: \.element.id) { index, zone in
                let segmentDegrees = (totalDegrees - gapDegrees * 4) / 5
                let start = startDegrees + Double(index) * (segmentDegrees + gapDegrees)
                let end = start + segmentDegrees
                let isActive = zone.id == state.heartRateZone?.id

                PulsarGaugeArc(startAngle: .degrees(start), endAngle: .degrees(end))
                    .stroke(
                        zone.color.opacity(isActive ? 1.0 : (state.heartRateZone == nil ? 0.24 : 0.48)),
                        style: StrokeStyle(lineWidth: isActive ? 15 : 12, lineCap: .round)
                    )
                    .shadow(color: zone.color.opacity(isActive ? 0.38 : 0), radius: 8, y: 3)
                    .animation(.spring(response: 0.34, dampingFraction: 0.78), value: isActive)
            }

            Circle()
                .fill(.black.opacity(0.20))
                .frame(width: 78, height: 78)
                .blur(radius: 16)

            VStack(spacing: 3) {
                Text("ZONE")
                    .font(.system(size: 11, weight: .semibold, design: .default))
                    .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)

                Text(state.heartRateZone.map { "\($0.number)" } ?? "--")
                    .font(.system(size: 32, weight: .bold, design: .default).monospacedDigit())
                    .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                    .lineLimit(1)

                Text(state.heartRateZone?.title ?? "Waiting")
                    .font(.system(size: 14, weight: .bold, design: .default))
                    .foregroundStyle(state.heartRateZone?.color ?? Color(red: 1.0, green: 0.45, blue: 0.28))
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.heartRateZone.map { "Heart rate zone \($0.number), \($0.title)" } ?? "Waiting for heart rate zone")
    }
}

private struct PulsarGaugeArc: Shape {
    var startAngle: Angle
    var endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path
    }
}

private struct PulsarPremiumHeartRateZoneCard: View {
    var state: PulsarLiveWorkoutDashboardState
    var contentPadding: CGFloat = 16
    var pillVerticalPadding: CGFloat = 9

    var body: some View {
        VStack(alignment: .leading, spacing: contentPadding - 3) {
            HStack(alignment: .firstTextBaseline) {
                Text("Heart Rate Zones")
                    .font(.system(size: 17, weight: .semibold, design: .default))
                    .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)

                Spacer()

                HStack(spacing: 5) {
                    Text("View guide")
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 13, weight: .medium, design: .default))
                .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
            }

            HStack(spacing: 0) {
                ForEach(state.zoneProfile.zones) { zone in
                    PulsarPremiumZonePill(
                        zone: zone,
                        isActive: zone.id == state.heartRateZone?.id,
                        verticalPadding: pillVerticalPadding
                    )
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text(state.activeZoneDescriptionText)
                    .font(.system(size: 14, weight: .bold, design: .default))
                    .foregroundStyle(state.heartRateZone?.color ?? Color(red: 1.0, green: 0.45, blue: 0.28))
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)

                Spacer(minLength: 10)

                Text(state.activeZoneTargetText)
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(contentPadding)
        .pulsarPremiumWorkoutCard(cornerRadius: PulsarPremiumWorkoutRadius.largeCard)
    }
}

private struct PulsarPremiumZonePill: View {
    var zone: PulsarHeartRateZone
    var isActive: Bool
    var verticalPadding: CGFloat = 9

    var body: some View {
        VStack(spacing: 3) {
            Text("Z\(zone.number)")
                .font(.system(size: 16, weight: .bold, design: .default))
                .foregroundStyle(isActive ? zone.color : zone.color.opacity(0.78))
                .frame(maxWidth: .infinity)
                .padding(.vertical, verticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(zone.color.opacity(isActive ? 0.22 : 0.16))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(zone.color.opacity(isActive ? 0.70 : 0.04), lineWidth: isActive ? 1.5 : 1)
                }
                .shadow(color: zone.color.opacity(isActive ? 0.34 : 0), radius: 8, y: 3)

            Text(zone.percentRangeText)
                .font(.system(size: 11, weight: .semibold, design: .default))
                .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.32, dampingFraction: 0.80), value: isActive)
    }
}

private struct PulsarPremiumMetricTile: View {
    var metric: PulsarLiveWorkoutMetric
    var height: CGFloat = 88

    var body: some View {
        VStack(alignment: .leading, spacing: height < 68 ? 4 : 5) {
            Image(systemName: metric.symbolName)
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(metric.fitnessIconStyle)
                .frame(height: 13, alignment: .leading)

            Text(metric.title.uppercased())
                .font(.system(size: 8.5, weight: .semibold, design: .default))
                .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Text(metric.value)
                .font(.system(size: height < 68 ? 18 : 21, weight: .bold, design: .default).monospacedDigit())
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.48)

            Text(metric.unit ?? " ")
                .font(.system(size: 10, weight: .medium, design: .default))
                .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                .lineLimit(1)
        }
        .padding(height < 68 ? 8 : 10)
        .frame(height: height, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.92),
                    Color.white.opacity(0.62)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: PulsarPremiumWorkoutRadius.smallCard, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: PulsarPremiumWorkoutRadius.smallCard, style: .continuous)
                .stroke(.black.opacity(0.055), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.18), radius: 8, y: 5)
    }
}

private struct PulsarPremiumWorkoutInsightCard: View {
    var state: PulsarLiveWorkoutDashboardState
    var height: CGFloat = 76
    var isCompact = false

    var body: some View {
        let tint = state.heartRateZone?.color ?? state.tint

        HStack(spacing: isCompact ? 10 : 12) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.18), lineWidth: isCompact ? 4.5 : 5.5)
                Circle()
                    .trim(from: 0, to: insightProgress)
                    .stroke(tint, style: StrokeStyle(lineWidth: isCompact ? 4.5 : 5.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Image(systemName: state.symbolName)
                    .font((isCompact ? Font.caption : .subheadline).weight(.bold))
                    .foregroundStyle(tint)
            }
            .frame(width: isCompact ? 38 : 46, height: isCompact ? 38 : 46)

            VStack(alignment: .leading, spacing: 1) {
                Text(state.insightTitle)
                    .font(.system(size: isCompact ? 11 : 12, weight: .medium, design: .default))
                    .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                    .lineLimit(1)

                Text(state.intensityTitle)
                    .font(.system(size: isCompact ? 16 : 18, weight: .bold, design: .default))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)

                Text(state.intensitySubtitle)
                    .font(.system(size: isCompact ? 11 : 12, weight: .medium, design: .default))
                    .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 8)

            PulsarWorkoutInsightSparkline(tint: tint)
                .frame(width: isCompact ? 92 : 120, height: isCompact ? 32 : 40)
                .opacity(state.currentHeartRate == nil ? 0.36 : 1)
        }
        .padding(.horizontal, isCompact ? 12 : 14)
        .frame(height: height)
        .pulsarPremiumWorkoutCard(cornerRadius: PulsarPremiumWorkoutRadius.largeCard)
    }

    private var insightProgress: CGFloat {
        guard let zone = state.heartRateZone else { return 0.22 }
        return CGFloat(min(max(Double(zone.number) / 5.0, 0.18), 1.0))
    }
}

private struct PulsarPremiumNowPlayingCard: View {
    var track: PulsarNowPlayingTrack
    var tint: Color
    var height: CGFloat = 84
    var isCompact = false
    var controlsDisabled: Bool
    var onOpen: () -> Void
    var onTogglePlayback: () -> Void
    var onNextTrack: () -> Void
    var onPreviousTrack: () -> Void

    var body: some View {
        HStack(spacing: isCompact ? 8 : 10) {
            Button(action: onOpen) {
                artwork
            }
            .buttonStyle(.plain)

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.isPlaying ? "Now Playing" : "Music")
                        .font(.system(size: isCompact ? 10 : 11, weight: .medium, design: .default))
                        .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                        .lineLimit(1)

                    Text(track.displayTitle)
                        .font(.system(size: isCompact ? 15 : 17, weight: .semibold, design: .default))
                        .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)

                    Text(track.displaySubtitle)
                        .font(.system(size: isCompact ? 12 : 13, weight: .medium, design: .default))
                        .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(track.progress == nil ? 0.07 : 0.11))
                            Capsule(style: .continuous)
                                .fill(tint.opacity(track.progress == nil ? 0.22 : 0.86))
                                .frame(width: max(6, proxy.size.width * min(max(track.progress ?? 0, 0), 1)))
                        }
                    }
                    .frame(height: 3)
                    .padding(.top, 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            HStack(spacing: isCompact ? 3 : 5) {
                musicControlButton(systemName: "backward.fill", label: "Previous Track", action: onPreviousTrack)
                musicControlButton(
                    systemName: track.isPlaying ? "pause.fill" : "play.fill",
                    label: track.isPlaying ? "Pause Music" : "Play Music",
                    prominence: true,
                    action: onTogglePlayback
                )
                musicControlButton(systemName: "forward.fill", label: "Next Track", action: onNextTrack)
            }
        }
        .padding(.horizontal, isCompact ? 10 : 12)
        .frame(height: height)
        .pulsarPremiumWorkoutCard(cornerRadius: PulsarPremiumWorkoutRadius.largeCard, interactive: true)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var artwork: some View {
        let size: CGFloat = isCompact ? 42 : 48
        if let artworkImage = track.artworkImage {
            Image(uiImage: artworkImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.07), lineWidth: 1)
                }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.09))
                Image(systemName: "music.note")
                    .pulsarTextStyle(.label)
                    .foregroundStyle(track.isAvailable ? tint : .secondary)
            }
            .frame(width: size, height: size)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.white.opacity(0.06), lineWidth: 1)
            }
        }
    }

    private func musicControlButton(
        systemName: String,
        label: String,
        prominence: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(prominence ? .subheadline.weight(.bold) : .caption.weight(.semibold))
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                .frame(width: prominence ? (isCompact ? 32 : 36) : (isCompact ? 27 : 31), height: prominence ? (isCompact ? 32 : 36) : (isCompact ? 27 : 31))
                .background(Color.white.opacity(prominence ? 0.11 : 0.075), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(controlsDisabled || !track.isAvailable)
        .opacity(controlsDisabled || !track.isAvailable ? 0.42 : 1)
        .accessibilityLabel(label)
    }
}

private struct PulsarWorkoutInsightSparkline: View {
    var tint: Color

    var body: some View {
        ZStack {
            VStack(spacing: 9) {
                ForEach(0..<3, id: \.self) { _ in
                    Rectangle()
                        .fill(.white.opacity(0.055))
                        .frame(height: 1)
                }
            }

            PulsarSparklineShape()
                .stroke(tint.opacity(0.92), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

            PulsarSparklineShape()
                .stroke(tint.opacity(0.24), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                .blur(radius: 6)
        }
    }
}

private struct PulsarSparklineShape: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [CGPoint] = [
            CGPoint(x: 0.00, y: 0.70),
            CGPoint(x: 0.12, y: 0.58),
            CGPoint(x: 0.24, y: 0.34),
            CGPoint(x: 0.38, y: 0.28),
            CGPoint(x: 0.52, y: 0.26),
            CGPoint(x: 0.66, y: 0.44),
            CGPoint(x: 0.78, y: 0.50),
            CGPoint(x: 0.90, y: 0.45),
            CGPoint(x: 1.00, y: 0.42)
        ]

        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: rect.minX + first.x * rect.width, y: rect.minY + first.y * rect.height))

        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height))
        }

        return path
    }
}

private struct PulsarHeartRateZoneCard: View {
    var state: PulsarLiveWorkoutDashboardState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Heart Rate Zones")
                        .pulsarTextStyle(.cardTitle)
                    Text(state.zoneDetailText)
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(state.heartRateZone.map { "Z\($0.number)" } ?? "No Zone")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(state.activeZoneColor)
            }

            HStack(spacing: 6) {
                ForEach(state.zoneProfile.zones) { zone in
                    PulsarHeartRateZoneSegment(
                        zone: zone,
                        isActive: zone.id == state.heartRateZone?.id
                    )
                }
            }
            .frame(height: 58)

            HStack {
                Text(state.zoneProfile.maxHeartRateText)
                Spacer(minLength: 10)
                Text(state.percentOfMaxText)
            }
            .pulsarTextStyle(.overline)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .pulsarLiveWorkoutGlass(cornerRadius: 26, tint: state.activeZoneColor)
    }
}

private struct PulsarHeartRateZoneSegment: View {
    var zone: PulsarHeartRateZone
    var isActive: Bool

    var body: some View {
        VStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(zone.color.opacity(isActive ? 0.96 : 0.24))
                .overlay {
                    if isActive {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(.white.opacity(0.70), lineWidth: 1)
                    }
                }
                .frame(height: isActive ? 20 : 12)
                .shadow(color: zone.color.opacity(isActive ? 0.40 : 0), radius: 10, y: 5)

            Text("Z\(zone.number)")
                .pulsarTextStyle(.overline)
                .foregroundStyle(isActive ? zone.color : .secondary)

            Text(zone.percentRangeText)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isActive)
    }
}

private struct PulsarLiveWorkoutStatusPill: View {
    var title: String
    var subtitle: String
    var symbolName: String
    var tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbolName)
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .pulsarTextStyle(.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(subtitle)
                    .pulsarTextStyle(.overline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct PulsarLiveWorkoutMetricTile: View {
    var metric: PulsarLiveWorkoutMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: metric.symbolName)
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(metric.fitnessIconStyle)
                Spacer(minLength: 0)
            }

            Text(metric.value)
                .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(2)
                .minimumScaleFactor(0.50)

            HStack(spacing: 4) {
                Text(metric.title)
                if let unit = metric.unit {
                    Text(unit)
                }
            }
            .pulsarTextStyle(.overline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.70)
        }
        .padding(13)
        .frame(minHeight: 108, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.095), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct PulsarNowPlayingCard: View {
    var track: PulsarNowPlayingTrack
    var tint: Color
    var controlsDisabled: Bool
    var onOpen: () -> Void
    var onTogglePlayback: () -> Void
    var onNextTrack: () -> Void
    var onPreviousTrack: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                artwork
            }
            .buttonStyle(.plain)

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(track.isPlaying ? "Now Playing" : "Music")
                            .pulsarTextStyle(.overline)
                            .foregroundStyle(.secondary)
                        Circle()
                            .fill(track.isPlaying ? PulsarFitnessMonochromeDesign.active : Color.secondary)
                            .frame(width: 5, height: 5)
                    }

                    Text(track.displayTitle)
                        .pulsarTextStyle(.label)
                        .lineLimit(2)
                        .minimumScaleFactor(0.76)
                    Text(track.displaySubtitle)
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    if let progress = track.progress {
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.12))
                                Capsule(style: .continuous)
                                    .fill(tint.opacity(0.82))
                                    .frame(width: max(8, proxy.size.width * min(max(progress, 0), 1)))
                            }
                        }
                        .frame(height: 4)
                        .padding(.top, 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            HStack(spacing: 7) {
                musicControlButton(systemName: "backward.fill", label: "Previous Track", action: onPreviousTrack)
                musicControlButton(
                    systemName: track.isPlaying ? "pause.fill" : "play.fill",
                    label: track.isPlaying ? "Pause Music" : "Play Music",
                    prominence: true,
                    action: onTogglePlayback
                )
                musicControlButton(systemName: "forward.fill", label: "Next Track", action: onNextTrack)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pulsarLiveWorkoutGlass(cornerRadius: 24, tint: tint, interactive: true)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var artwork: some View {
        if let artworkImage = track.artworkImage {
            Image(uiImage: artworkImage)
                .resizable()
                .scaledToFill()
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.20), lineWidth: 1)
                }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                Image(systemName: "music.note")
                    .pulsarTextStyle(.sectionHeader)
                    .foregroundStyle(track.isAvailable ? tint : .secondary)
            }
            .frame(width: 54, height: 54)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
        }
    }

    private func musicControlButton(
        systemName: String,
        label: String,
        prominence: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(prominence ? .headline.weight(.semibold) : .caption.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: prominence ? 40 : 32, height: prominence ? 40 : 32)
                .background(Color.white.opacity(prominence ? 0.13 : 0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(controlsDisabled || !track.isAvailable)
        .opacity(controlsDisabled || !track.isAvailable ? 0.42 : 1)
        .accessibilityLabel(label)
    }
}

private struct PulsarLiveWorkoutControlButtonStyle: ButtonStyle {
    var tint: Color
    var height: CGFloat? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font((height == nil ? Font.headline : .subheadline).weight(.bold))
            .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
            .padding(.vertical, height == nil ? 16 : 0)
            .frame(height: height)
            .background(.white.opacity(0.76), in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).stroke(.black.opacity(0.07), lineWidth: 0.7))
            .shadow(
                color: tint.opacity(configuration.isPressed ? (height == nil ? 0.16 : 0.14) : (height == nil ? 0.34 : 0.28)),
                radius: configuration.isPressed ? (height == nil ? 8 : 6) : (height == nil ? 18 : 13),
                y: height == nil ? 9 : 7
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

private struct PulsarLiveWorkoutLockButtonStyle: ButtonStyle {
    var height: CGFloat? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .pulsarTextStyle(.label)
            .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
            .padding(.vertical, height == nil ? 16 : 0)
            .frame(height: height)
            .background(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.92),
                        Color.white.opacity(0.62)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: PulsarPremiumWorkoutRadius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: PulsarPremiumWorkoutRadius.control, style: .continuous)
                    .stroke(.black.opacity(0.07), lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(configuration.isPressed ? 0.14 : 0.24), radius: configuration.isPressed ? 6 : 12, y: 7)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

private extension View {
    @ViewBuilder
    func pulsarPremiumWorkoutCard(cornerRadius: CGFloat, interactive: Bool = false) -> some View {
        self.pulsarFitnessMonochromeSurface(
            cornerRadius: cornerRadius,
            isInteractive: interactive,
            shadowOpacity: 0.055
        )
    }

    @ViewBuilder
    func pulsarLiveWorkoutGlass(cornerRadius: CGFloat, tint: Color, interactive: Bool = false) -> some View {
        self.pulsarFitnessMonochromeSurface(
            cornerRadius: cornerRadius,
            isInteractive: interactive,
            shadowOpacity: 0.045
        )
    }
}

private extension PulsarLiveWorkoutMetric {
    var fitnessIconStyle: Color {
        let normalizedTitle = title.lowercased()
        let representsPhysiology =
            normalizedTitle.contains("heart") ||
            normalizedTitle.contains("hrv") ||
            normalizedTitle.contains("calories")
        return representsPhysiology ? tint : PulsarFitnessMonochromeDesign.primaryText
    }
}

#if DEBUG
#Preview {
    let zoneProfile = PulsarHeartRateZoneProfile(maxHeartRate: 190, source: .manual)
    PulsarLiveWorkoutDashboardView(
        state: PulsarLiveWorkoutDashboardState(
            title: "Indoor Running",
            subtitle: "Treadmill",
            symbolName: "figure.run",
            tint: WorkoutAccent.velocity.color,
            glowColor: Color(red: 1.0, green: 0.72, blue: 0.42),
            phase: .running,
            statusText: "LIVE",
            recorderStatusText: "Apple Health Live",
            recorderStatusSymbolName: "iphone",
            primaryMetricTitle: "DISTANCE",
            primaryMetricValue: "1.24",
            primaryMetricSubtitle: "kilometers",
            elapsedTime: 612,
            currentHeartRate: 148,
            heartRateZone: zoneProfile.zone(for: 148),
            zoneProfile: zoneProfile,
            intensityTitle: "Aerobic",
            intensitySubtitle: "Productive tempo",
            nowPlaying: .preview,
            metrics: [
                PulsarLiveWorkoutMetric(title: "Elapsed", value: "10:12", symbolName: "timer", tint: .green),
                PulsarLiveWorkoutMetric(title: "Calories", value: "118", unit: "cal", symbolName: "flame.fill", tint: .orange),
                PulsarLiveWorkoutMetric(title: "Distance", value: "2.38", unit: "km", symbolName: "point.topleft.down.curvedto.point.bottomright.up", tint: .cyan),
                PulsarLiveWorkoutMetric(title: "Pace", value: "5:18", unit: "/km", symbolName: "speedometer", tint: .purple),
                PulsarLiveWorkoutMetric(title: "Speed", value: "11.5", unit: "km/h", symbolName: "gauge.with.dots.needle.bottom.50percent", tint: .yellow),
                PulsarLiveWorkoutMetric(title: "Cadence", value: "162", unit: "spm", symbolName: "metronome.fill", tint: .mint),
                PulsarLiveWorkoutMetric(title: "Incline", value: "1.0", unit: "%", symbolName: "figure.run.treadmill", tint: .pink),
                PulsarLiveWorkoutMetric(title: "HRV", value: "58", unit: "ms", symbolName: "heart.text.square.fill", tint: .red)
            ],
            presentationStyle: .premiumNonGPS
        ),
        onClose: {},
        onTogglePause: {},
        onEnd: {},
        onOpenNowPlaying: {}
    ) {
        PulsarLiveWorkoutAmbientBackground(tint: WorkoutAccent.velocity.color, glowColor: .orange)
    }
}
#endif
