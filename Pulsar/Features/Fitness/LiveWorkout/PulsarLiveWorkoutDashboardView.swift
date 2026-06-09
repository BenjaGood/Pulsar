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
        self.background = background()
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                background
                    .ignoresSafeArea()

                PulsarLiveWorkoutAtmosphere(tint: state.tint, glowColor: state.glowColor)
                    .allowsHitTesting(false)

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
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .confirmationDialog("End this \(state.title.lowercased())?", isPresented: $showingEndConfirmation, titleVisibility: .visible) {
            Button("End Workout", role: .destructive) {
                onEnd()
            }
            Button("Keep Going", role: .cancel) {}
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
                .font(.caption.weight(.bold))
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
                    .font(.caption.weight(.black))
                    .foregroundStyle(statusTint)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(statusTint.opacity(0.14), in: Capsule(style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("HEART RATE")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(state.heartRateDisplayText)
                                .font(.system(size: state.currentHeartRate == nil ? 28 : 64, weight: .black, design: .rounded).monospacedDigit())
                                .lineLimit(2)
                                .minimumScaleFactor(0.50)
                            if !state.heartRateUnitText.isEmpty {
                                Text(state.heartRateUnitText)
                                    .font(.headline.weight(.black))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(state.percentOfMaxText)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 8) {
                    Text(state.zoneTitleText)
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(state.activeZoneColor)
                        .lineLimit(1)
                    Text(state.zoneDetailText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                    Text(state.primaryMetricValue)
                        .font(.headline.weight(.black).monospacedDigit())
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(state.activeZoneColor.opacity(0.15), in: Capsule(style: .continuous))
                    Text(state.primaryMetricTitle)
                        .font(.caption2.weight(.black))
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

    private var statusTint: Color {
        switch state.phase {
        case .paused: .orange
        case .finishing, .finished: .secondary
        case .preparing, .running: state.tint
        }
    }
}

struct PulsarLiveWorkoutAmbientBackground: View {
    var tint: Color
    var glowColor: Color

    var body: some View {
        Color(red: 0.01, green: 0.012, blue: 0.017)
        .overlay {
            RadialGradient(
                colors: [glowColor.opacity(0.20), .clear],
                center: .topTrailing,
                startRadius: 32,
                endRadius: 360
            )
        }
        .overlay {
            LinearGradient(
                colors: [.black.opacity(0.0), .black.opacity(0.58)],
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
                .black.opacity(0.10),
                tint.opacity(0.04),
                .black.opacity(0.34)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, glowColor.opacity(0.08), .black.opacity(0.48)],
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
                    .font(.caption.weight(.black))
                if let message = banner.message {
                    Text(message)
                        .font(.caption.weight(.semibold))
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

private struct PulsarHeartRateZoneCard: View {
    var state: PulsarLiveWorkoutDashboardState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Heart Rate Zones")
                        .font(.headline.weight(.black))
                    Text(state.zoneDetailText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(state.heartRateZone.map { "Z\($0.number)" } ?? "No Zone")
                    .font(.system(size: 26, weight: .black, design: .rounded))
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
            .font(.caption2.weight(.bold))
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
                .font(.caption2.weight(.black))
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
                .font(.caption.weight(.black))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(subtitle)
                    .font(.caption2.weight(.bold))
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
                    .font(.caption.weight(.black))
                    .foregroundStyle(metric.tint)
                Spacer(minLength: 0)
            }

            Text(metric.value)
                .font(.system(size: 22, weight: .black, design: .rounded).monospacedDigit())
                .lineLimit(2)
                .minimumScaleFactor(0.50)

            HStack(spacing: 4) {
                Text(metric.title)
                if let unit = metric.unit {
                    Text(unit)
                }
            }
            .font(.caption2.weight(.bold))
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
                            .font(.caption2.weight(.black))
                            .foregroundStyle(.secondary)
                        Circle()
                            .fill(track.isPlaying ? Color.green : Color.secondary)
                            .frame(width: 5, height: 5)
                    }

                    Text(track.displayTitle)
                        .font(.subheadline.weight(.black))
                        .lineLimit(2)
                        .minimumScaleFactor(0.76)
                    Text(track.displaySubtitle)
                        .font(.caption.weight(.semibold))
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
                    .font(.title3.weight(.black))
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
                .font(prominence ? .headline.weight(.black) : .caption.weight(.black))
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

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .padding(.vertical, 16)
            .background(tint.gradient, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).stroke(.white.opacity(0.30), lineWidth: 1))
            .shadow(color: tint.opacity(configuration.isPressed ? 0.16 : 0.34), radius: configuration.isPressed ? 8 : 18, y: 9)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

private extension View {
    @ViewBuilder
    func pulsarLiveWorkoutGlass(cornerRadius: CGFloat, tint: Color, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(
                .regular.tint(tint.opacity(0.16)).interactive(interactive),
                in: .rect(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            self
                .background(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.13),
                            Color.white.opacity(0.055),
                            tint.opacity(0.045)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.30), tint.opacity(0.20), .white.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
        }
    }
}

#Preview {
    let zoneProfile = PulsarHeartRateZoneProfile(maxHeartRate: 190, source: .manual)
    PulsarLiveWorkoutDashboardView(
        state: PulsarLiveWorkoutDashboardState(
            title: "Indoor Running",
            subtitle: "Personalized Training",
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
                PulsarLiveWorkoutMetric(title: "Pace", value: "5:18 /km", symbolName: "speedometer", tint: .cyan),
                PulsarLiveWorkoutMetric(title: "Heart", value: "148", unit: "bpm", symbolName: "heart.fill", tint: .red)
            ]
        ),
        onClose: {},
        onTogglePause: {},
        onEnd: {},
        onOpenNowPlaying: {}
    ) {
        PulsarLiveWorkoutAmbientBackground(tint: WorkoutAccent.velocity.color, glowColor: .orange)
    }
}
