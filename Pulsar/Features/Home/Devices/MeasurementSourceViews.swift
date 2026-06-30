//
//  MeasurementSourceViews.swift
//  Pulsar
//

import SwiftUI
import UIKit

struct MeasurementDeviceIconView: View {
    let type: MeasurementDeviceType
    var size: CGFloat = 24
    var tint: Color?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            switch type {
            case .appleWatch:
                appleWatchIcon
            case .ouraRing:
                ringIcon
            case .airPodsPro3:
                Image(systemName: "airpodspro")
                    .font(.system(size: size * 0.74, weight: .semibold))
                    .foregroundStyle(resolvedTint)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var resolvedTint: Color {
        tint ?? (colorScheme == .dark ? .white.opacity(0.92) : Color(red: 0.12, green: 0.18, blue: 0.24))
    }

    private var appleWatchIcon: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let bodyWidth = width * 0.52
            let bodyHeight = height * 0.58

            ZStack {
                RoundedRectangle(cornerRadius: width * 0.12, style: .continuous)
                    .stroke(resolvedTint.opacity(0.86), lineWidth: max(width * 0.075, 1.35))
                    .frame(width: bodyWidth, height: bodyHeight)

                RoundedRectangle(cornerRadius: width * 0.07, style: .continuous)
                    .fill(resolvedTint.opacity(0.12))
                    .frame(width: bodyWidth * 0.64, height: bodyHeight * 0.52)

                Capsule(style: .continuous)
                    .fill(resolvedTint.opacity(0.84))
                    .frame(width: bodyWidth * 0.42, height: max(height * 0.055, 1.2))
                    .offset(y: -bodyHeight * 0.68)

                Capsule(style: .continuous)
                    .fill(resolvedTint.opacity(0.84))
                    .frame(width: bodyWidth * 0.42, height: max(height * 0.055, 1.2))
                    .offset(y: bodyHeight * 0.68)

                Capsule(style: .continuous)
                    .fill(resolvedTint.opacity(0.74))
                    .frame(width: max(width * 0.055, 1.1), height: height * 0.18)
                    .offset(x: bodyWidth * 0.61, y: -bodyHeight * 0.10)
            }
            .frame(width: width, height: height)
        }
    }

    private var ringIcon: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack {
                Circle()
                    .stroke(resolvedTint.opacity(0.23), lineWidth: max(width * 0.22, 3))
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                resolvedTint.opacity(0.96),
                                resolvedTint.opacity(0.46),
                                resolvedTint.opacity(0.88)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: max(width * 0.15, 2.2), lineCap: .round)
                    )
                Circle()
                    .fill(resolvedTint.opacity(0.88))
                    .frame(width: width * 0.12, height: width * 0.12)
                    .offset(x: width * 0.18, y: -width * 0.22)
                Circle()
                    .fill(resolvedTint.opacity(0.58))
                    .frame(width: width * 0.085, height: width * 0.085)
                    .offset(x: width * 0.24, y: width * 0.04)
            }
        }
    }
}

struct MeasurementSourceSheet: View {
    @ObservedObject var manager: MeasurementSourceManager
    var onSyncAppleHealthKit: () async -> Void = {}
    var onDismiss: () -> Void

    @State private var focusedDeviceType: MeasurementDeviceType?
    @State private var sourceChangeConfirmation: String?
    @Environment(\.colorScheme) private var colorScheme

    private var focusedDevice: MeasurementDevice {
        manager.device(for: focusedDeviceType ?? manager.activeDevice.type)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                MeasurementActiveDeviceHero(device: manager.activeDevice)
                    .id(manager.activeDevice.type)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))

                changeSourceSection

                sourcePrioritySection

                MeasurementDeviceDetailPanel(
                    device: focusedDevice,
                    isPrimaryActionDisabled: manager.isPrimaryActionDisabled(for: focusedDevice)
                ) {
                    Task { await handlePrimaryAction(for: focusedDevice.type) }
                } onSync: {
                    Task { await syncNow(for: focusedDevice) }
                } onDisconnect: {
                    Task { await manager.disconnectOura() }
                }

                if focusedDevice.type == .ouraRing {
                    OuraCloudDataPanel(
                        rows: manager.ouraTodayRows,
                        lastSyncAt: focusedDevice.lastSyncAt
                    )
                }

                footerNote
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 42)
        }
        .scrollIndicators(.hidden)
        .background {
            MeasurementSourceBackground()
                .clipShape(MeasurementModalTopShape(radius: 46))
                .ignoresSafeArea()
        }
        .overlay(alignment: .bottom) {
            if let sourceChangeConfirmation {
                SourceChangeConfirmationBanner(message: sourceChangeConfirmation)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.48, dampingFraction: 0.88), value: manager.activeDeviceType)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: focusedDeviceType)
        .animation(.easeInOut(duration: 0.18), value: manager.ouraConnectionFlowState)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: sourceChangeConfirmation)
        .alert(item: ouraConnectionAlertBinding, content: makeOuraConnectionAlert)
        .onAppear {
            manager.refreshDeviceStatus()
            focusedDeviceType = manager.activeDevice.type
        }
        .onChange(of: manager.activeDeviceType) { _, newValue in
            focusedDeviceType = newValue
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Measurement Source")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text("Choose which device powers your health metrics.")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(secondaryText)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            Button("Close", systemImage: "xmark", action: onDismiss)
                .font(.system(size: 20, weight: .semibold))
                .labelStyle(.iconOnly)
                .symbolRenderingMode(.monochrome)
                .tint(.white)
                .buttonStyle(.glass(.clear))
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .frame(width: 48, height: 48)
        }
        .padding(.bottom, 8)
    }

    private var changeSourceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Change source")
                    .font(.title2.bold())
                    .foregroundStyle(primaryText)

                Spacer()

                Text("\(manager.availableDevices.count) devices")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.065), in: Capsule())
            }

            ScrollView(.horizontal) {
                PulsarGlassEffectGroup(spacing: 8) {
                    LazyHStack(spacing: 12) {
                        ForEach(manager.availableDevices) { device in
                            MeasurementDeviceSourceCard(
                                device: device,
                                isFocused: focusedDevice.type == device.type
                            ) {
                                selectDevice(device.type)
                            }
                            .containerRelativeFrame(.horizontal, count: 3, span: 1, spacing: 12)
                            .frame(height: 252, alignment: .top)
                        }
                    }
                }
                .padding(.horizontal, 1)
                .padding(.vertical, 3)
            }
            .scrollIndicators(.hidden)
            .frame(height: 258)
        }
    }

    private var sourcePrioritySection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Current sources")
                    .pulsarTextStyle(.cardTitle)
                    .foregroundStyle(primaryText)

                Spacer()

                if HealthSourcePriorityCategory.allCases.contains(where: { manager.routingDecision(for: $0).isFallback }) {
                    DeviceStatusPill(text: "Using fallback source", tint: Color(red: 0.76, green: 0.34, blue: 0.08))
                }
            }

            VStack(spacing: 11) {
                ForEach(HealthSourcePriorityCategory.allCases) { category in
                    SourcePriorityCategoryRow(
                        category: category,
                        preference: manager.preference(for: category),
                        decision: manager.routingDecision(for: category),
                        onSourceChange: { source in
                            manager.setCurrentSource(source, for: category)
                            showSourceChangeConfirmation(source: source, category: category)
                        },
                        onFallbackChange: { enabled in
                            manager.setFallbackEnabled(enabled, for: category)
                        }
                    )
                }
            }

            #if DEBUG
            SourceRoutingDebugPanel(manager: manager)
            #endif
        }
    }

    private var footerNote: some View {
        Text("Pulsar uses your current source for sleep, recovery, strain, stress, steps, and daily metrics. AirPods Pro 3 are never used there; they are only an emergency workout heart-rate backup through HealthKit.")
            .pulsarTextStyle(.captionEmphasis)
            .foregroundStyle(secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(cardBorder, lineWidth: 1)
            }
    }

    private func selectDevice(_ type: MeasurementDeviceType) {
        focusedDeviceType = type
        Task { await handlePrimaryAction(for: type) }
    }

    private func handlePrimaryAction(for type: MeasurementDeviceType) async {
        focusedDeviceType = type
        var device = manager.device(for: type)

        if type == .airPodsPro3 {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            return
        }

        if type == .ouraRing {
            switch device.connectionStatus {
            case .setupRequired, .disconnected, .tokenExpired:
                await manager.connectOura()
                guard focusedDeviceType == type else { return }
                device = manager.device(for: type)
            case .syncError:
                await manager.syncOuraNow()
                guard focusedDeviceType == type else { return }
                device = manager.device(for: type)
            case .connecting:
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                return
            case .connected, .available:
                break
            }
        }

        guard !device.isActiveSource else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }

        guard device.canBecomeActiveSource else {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            return
        }

        manager.selectActiveDevice(device)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func syncNow(for device: MeasurementDevice) async {
        switch device.type {
        case .appleWatch:
            await onSyncAppleHealthKit()
        case .ouraRing:
            await manager.syncOuraNow()
        case .airPodsPro3:
            break
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func showSourceChangeConfirmation(source: HealthSourceID, category: HealthSourcePriorityCategory) {
        let message = "\(source.priorityDisplayName) will be used for \(category.confirmationTitle) from now on."
        sourceChangeConfirmation = message
        Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            await MainActor.run {
                if sourceChangeConfirmation == message {
                    sourceChangeConfirmation = nil
                }
            }
        }
    }

    private var ouraConnectionAlertBinding: Binding<OuraConnectionAlert?> {
        Binding(
            get: { manager.ouraConnectionAlert },
            set: { newValue in
                if newValue == nil {
                    manager.dismissOuraConnectionAlert()
                }
            }
        )
    }

    private func makeOuraConnectionAlert(_ alert: OuraConnectionAlert) -> Alert {
        #if DEBUG
        if let debugAuthorizationURL = alert.debugAuthorizationURL {
            return Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                primaryButton: .default(Text("Open Oura login in browser")) {
                    UIApplication.shared.open(debugAuthorizationURL)
                    manager.dismissOuraConnectionAlert()
                },
                secondaryButton: .default(Text("OK")) {
                    manager.dismissOuraConnectionAlert()
                }
            )
        }
        #endif
        return Alert(
            title: Text(alert.title),
            message: Text(alert.message),
            dismissButton: .default(Text("OK")) {
                manager.dismissOuraConnectionAlert()
            }
        )
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.97) : Color(red: 0.07, green: 0.10, blue: 0.15)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? Color(red: 0.74, green: 0.80, blue: 0.90).opacity(0.84) : Color(red: 0.34, green: 0.38, blue: 0.46)
    }

    private var cardBackground: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [.white.opacity(0.12), Color(red: 0.05, green: 0.07, blue: 0.11).opacity(0.86)]
                : [.white.opacity(0.90), Color(red: 0.93, green: 0.97, blue: 1.0).opacity(0.70)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBorder: Color {
        colorScheme == .dark
            ? .white.opacity(0.13)
            : Color(red: 0.44, green: 0.56, blue: 0.70).opacity(0.24)
    }
}

private enum MeasurementSourcePalette {
    static let blueEdge = Color(red: 0.58, green: 0.76, blue: 1.0)
    static let blueCore = Color(red: 0.30, green: 0.58, blue: 0.96)
    static let connected = Color(red: 0.22, green: 0.92, blue: 0.58)
    static let mutedDot = Color(red: 0.46, green: 0.53, blue: 0.62)
}

private struct MeasurementModalTopShape: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

private extension View {
    func measurementGlassSurface(
        cornerRadius: CGFloat,
        tint: Color = MeasurementSourcePalette.blueEdge,
        opacity: Double = 0.08,
        isInteractive: Bool = false
    ) -> some View {
        pulsarLiquidGlass(
            cornerRadius: cornerRadius,
            tint: tint.opacity(opacity),
            interactive: isInteractive
        )
    }

}

private struct OuraCloudDataPanel: View {
    let rows: [OuraVisibleDataRow]
    let lastSyncAt: Date?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Oura cloud data")
                        .pulsarTextStyle(.cardTitle)
                        .foregroundStyle(primaryText)
                    Text(lastSyncText)
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(secondaryText)
                }

                Spacer(minLength: 0)

                DeviceStatusPill(text: availableCountText, tint: statusTint)
            }

            VStack(spacing: 10) {
                ForEach(rows) { row in
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: row.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(row.isAvailable ? availableTint : unavailableTint)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline, spacing: 7) {
                                Text(row.title)
                                    .pulsarTextStyle(.captionEmphasis)
                                    .foregroundStyle(primaryText)
                                Text(row.value)
                                    .pulsarTextStyle(.captionEmphasis)
                                    .foregroundStyle(row.isAvailable ? primaryText : secondaryText)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.76)
                            }

                            Text(row.detail)
                                .pulsarTextStyle(.overline)
                                .foregroundStyle(secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(rowBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(cardBorder, lineWidth: 1)
                    }
                }
            }
        }
        .padding(16)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        }
    }

    private var availableCountText: String {
        "\(rows.filter(\.isAvailable).count)/\(rows.count) available"
    }

    private var lastSyncText: String {
        guard let lastSyncAt else { return "Last sync unavailable" }
        return "Last sync \(Self.relativeFormatter.localizedString(for: lastSyncAt, relativeTo: Date()))"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private var availableTint: Color {
        colorScheme == .dark ? Color(red: 0.36, green: 0.94, blue: 0.68) : Color(red: 0.00, green: 0.47, blue: 0.30)
    }

    private var unavailableTint: Color {
        colorScheme == .dark ? Color(red: 1.0, green: 0.70, blue: 0.38) : Color(red: 0.76, green: 0.34, blue: 0.08)
    }

    private var statusTint: Color {
        rows.contains(where: \.isAvailable) ? availableTint : unavailableTint
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.96) : Color(red: 0.07, green: 0.10, blue: 0.15)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.62) : Color(red: 0.35, green: 0.39, blue: 0.47)
    }

    private var cardBackground: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [.white.opacity(0.10), Color(red: 0.05, green: 0.07, blue: 0.11).opacity(0.90)]
                : [.white.opacity(0.92), Color(red: 0.93, green: 0.97, blue: 1.0).opacity(0.70)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var rowBackground: Color {
        colorScheme == .dark ? .white.opacity(0.055) : .white.opacity(0.58)
    }

    private var cardBorder: Color {
        colorScheme == .dark
            ? .white.opacity(0.12)
            : Color(red: 0.44, green: 0.56, blue: 0.70).opacity(0.22)
    }
}

private struct MeasurementActiveDeviceHero: View {
    let device: MeasurementDevice
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = max(proxy.size.width - 36, 0)
            let leftWidth = min(170, max(144, contentWidth * 0.46))

            ZStack {
                heroSpotlight

                VStack(spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        heroInformation
                            .frame(width: leftWidth, alignment: .leading)
                            .zIndex(2)

                        heroProductStage
                            .frame(maxWidth: .infinity)
                            .frame(height: 274)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 278)

                    MetricPreviewStrip(metrics: device.supportedMetrics, tint: tint)
                }
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 16)
            }
        }
        .frame(height: 400)
        .measurementGlassSurface(
            cornerRadius: 32,
            tint: tint,
            opacity: 0.035
        )
        .shadow(color: .black.opacity(0.16), radius: 22, y: 14)
        .accessibilityElement(children: .contain)
    }

    private var heroInformation: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: device.type == .appleWatch ? "apple.logo" : device.type.symbolName)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(primaryText)
                    .frame(width: 26)

                Text(device.name)
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
            }

            VStack(alignment: .leading, spacing: 8) {
                MeasurementStatusChip(text: device.connectionStatus.label, tint: statusTint, kind: .dot)
                MeasurementStatusChip(text: HealthSourceDisplayCopy.preferredSource, tint: tint, kind: .symbol("star"))
            }

            VStack(alignment: .leading, spacing: 10) {
                PremiumBatteryStatusView(percentage: device.batteryPercentage, style: .hero, tint: tint)

                HStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(tint)
                        .frame(width: 32, height: 32)
                        .background(tint.opacity(0.09), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last sync")
                            .font(.caption)
                            .foregroundStyle(secondaryText)
                        Text(lastSyncText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
            }

            Spacer(minLength: 0)
        }
    }

    private var heroProductStage: some View {
        GeometryReader { proxy in
            let stageWidth = proxy.size.width
            let stageHeight = proxy.size.height

            ZStack {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [tint.opacity(0.12), .black.opacity(0.16), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: stageWidth * 0.46
                        )
                    )
                    .frame(width: stageWidth * 0.88, height: stageHeight * 0.18)
                    .blur(radius: 10)
                    .offset(y: stageHeight * 0.34)

                DeviceProductImageView(
                    assetName: device.type.assetName,
                    deviceType: device.type,
                    mode: .hero
                )
                .frame(width: stageWidth * imageStageWidthMultiplier, height: stageHeight * imageStageHeightMultiplier)
                .offset(x: productOffsetX(stageWidth), y: productOffsetY(stageHeight))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var heroSpotlight: some View {
        RadialGradient(
            colors: [tint.opacity(0.12), .clear],
            center: UnitPoint(x: 0.78, y: 0.32),
            startRadius: 0,
            endRadius: 220
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var lastSyncText: String {
        guard let lastSyncAt = device.lastSyncAt else { return "Unavailable" }
        return lastSyncAt.formatted(.relative(presentation: .named))
    }

    private var tint: Color {
        switch device.type {
        case .appleWatch:
            return colorScheme == .dark ? Color(red: 0.72, green: 0.86, blue: 1.0) : Color(red: 0.08, green: 0.34, blue: 0.58)
        case .ouraRing:
            return colorScheme == .dark ? Color(red: 0.72, green: 0.78, blue: 0.90) : Color(red: 0.18, green: 0.24, blue: 0.34)
        case .airPodsPro3:
            return colorScheme == .dark ? .white.opacity(0.88) : Color(red: 0.45, green: 0.50, blue: 0.58)
        }
    }

    private var statusTint: Color {
        switch device.connectionStatus {
        case .connected:
            return colorScheme == .dark ? Color(red: 0.36, green: 0.94, blue: 0.68) : Color(red: 0.00, green: 0.47, blue: 0.30)
        case .available, .connecting:
            return tint
        case .setupRequired, .tokenExpired, .syncError:
            return colorScheme == .dark ? Color(red: 1.0, green: 0.70, blue: 0.38) : Color(red: 0.76, green: 0.34, blue: 0.08)
        case .disconnected:
            return secondaryText
        }
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.97) : Color(red: 0.07, green: 0.10, blue: 0.15)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? Color(red: 0.76, green: 0.82, blue: 0.91).opacity(0.84) : Color(red: 0.35, green: 0.39, blue: 0.47)
    }

    private var imageStageWidthMultiplier: CGFloat {
        switch device.type {
        case .appleWatch:
            return 1.14
        case .ouraRing:
            return 0.98
        case .airPodsPro3:
            return 0.94
        }
    }

    private var imageStageHeightMultiplier: CGFloat {
        switch device.type {
        case .appleWatch:
            return 1.08
        case .ouraRing:
            return 0.92
        case .airPodsPro3:
            return 0.88
        }
    }

    private func productOffsetX(_ width: CGFloat) -> CGFloat {
        switch device.type {
        case .appleWatch:
            return -width * 0.04
        case .ouraRing:
            return -width * 0.02
        case .airPodsPro3:
            return -width * 0.02
        }
    }

    private func productOffsetY(_ height: CGFloat) -> CGFloat {
        switch device.type {
        case .appleWatch:
            return -height * 0.04
        case .ouraRing:
            return height * 0.02
        case .airPodsPro3:
            return height * 0.03
        }
    }
}

private struct MeasurementDeviceSourceCard: View {
    let device: MeasurementDevice
    let isFocused: Bool
    let onSelect: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 8) {
                    DeviceProductImageView(
                        assetName: device.type.assetName,
                        deviceType: device.type,
                        mode: .card
                    )
                    .frame(height: 116)
                    .frame(maxWidth: .infinity)
                    .offset(y: imageOffsetY)
                    .padding(.top, 10)

                    VStack(spacing: 7) {
                        Text(device.name)
                            .font(.subheadline.bold())
                            .foregroundStyle(primaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.72)
                            .frame(maxWidth: .infinity)

                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusDotTint)
                                .frame(width: 7, height: 7)
                            Text(selectorStatusText)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(selectorStatusTextColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }

                        if device.type == .airPodsPro3 {
                            Label("Battery unavailable", systemImage: "battery.0")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.62)

                            Text("Workout backup only")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.60)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 7)
                                .frame(maxWidth: .infinity)
                                .background(.white.opacity(0.055), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 9)

                    Spacer(minLength: 8)
                }

                if device.isActiveSource {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(MeasurementSourcePalette.blueCore, in: Circle())
                        .shadow(color: MeasurementSourcePalette.blueCore.opacity(0.26), radius: 8, y: 4)
                        .offset(x: -9, y: 9)
                }
            }
            .measurementGlassSurface(
                cornerRadius: 26,
                tint: cardTint,
                opacity: device.isActiveSource ? 0.075 : 0.018,
                isInteractive: true
            )
            .overlay {
                RoundedRectangle(cornerRadius: 26)
                    .stroke(selectionStroke, lineWidth: device.isActiveSource ? 1 : 0.6)
            }
            .contentShape(RoundedRectangle(cornerRadius: 26))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(device.name), \(selectorStatusText)")
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(device.isActiveSource ? .isSelected : [])
    }

    private var cardTint: Color {
        device.isActiveSource ? MeasurementSourcePalette.blueEdge : .white
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.94) : Color(red: 0.07, green: 0.10, blue: 0.15)
    }

    private var selectionStroke: Color {
        if device.isActiveSource {
            return MeasurementSourcePalette.blueEdge.opacity(0.34)
        }
        return isFocused ? .white.opacity(0.12) : .clear
    }

    private var selectorStatusText: String {
        switch device.type {
        case .appleWatch:
            return device.connectionStatus.label
        case .ouraRing:
            return device.connectionStatus == .connected ? "Connected" : "Available"
        case .airPodsPro3:
            return "Available"
        }
    }

    private var selectorStatusTextColor: Color {
        device.connectionStatus == .connected ? MeasurementSourcePalette.connected : .white.opacity(0.70)
    }

    private var statusDotTint: Color {
        device.connectionStatus == .connected ? MeasurementSourcePalette.connected : MeasurementSourcePalette.mutedDot
    }

    private var accessibilityHint: String {
        if device.isActiveSource {
            return "Current measurement source"
        }
        if device.canBecomeActiveSource {
            return "Use as measurement source"
        }
        return device.type == .airPodsPro3 ? "Workout backup only" : device.primaryActionTitle
    }

    private var imageOffsetY: CGFloat {
        switch device.type {
        case .appleWatch:
            return 2
        case .ouraRing:
            return 4
        case .airPodsPro3:
            return 0
        }
    }

}

private enum MeasurementStatusChipKind {
    case dot
    case symbol(String)
}

private struct MeasurementStatusChip: View {
    let text: String
    let tint: Color
    let kind: MeasurementStatusChipKind

    var body: some View {
        HStack(spacing: 8) {
            switch kind {
            case .dot:
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
            case .symbol(let systemName):
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            }

            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(text == "Connected" ? .white.opacity(0.92) : tint)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(0.09), in: Capsule())
    }
}

private struct SourcePriorityCategoryRow: View {
    let category: HealthSourcePriorityCategory
    let preference: HealthSourcePreference
    let decision: SourceRoutingDecision
    let onSourceChange: (HealthSourceID) -> Void
    let onFallbackChange: (Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(category.title)
                        .pulsarTextStyle(.label)
                        .foregroundStyle(primaryText)
                    Text(activeSourceText)
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(decision.isFallback || decision.displayedSource == nil ? fallbackTint : secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Menu {
                    ForEach(category.fallbackOrder, id: \.self) { source in
                        Button {
                            onSourceChange(source)
                        } label: {
                            if preference.currentSource == source {
                                Label(source.priorityDisplayName, systemImage: "checkmark")
                            } else {
                                Text(source.priorityDisplayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 7) {
                        Text(preference.currentSource.priorityDisplayName)
                            .pulsarTextStyle(.captionEmphasis)
                            .lineLimit(1)
                            .minimumScaleFactor(0.74)
                        Image(systemName: "chevron.up.chevron.down")
                            .pulsarTextStyle(.overline)
                    }
                    .foregroundStyle(primaryText)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background(.white.opacity(colorScheme == .dark ? 0.07 : 0.60), in: Capsule(style: .continuous))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(cardBorder, lineWidth: 1)
                    }
                }
            }

            Toggle(isOn: Binding(
                get: { preference.fallbackEnabled },
                set: onFallbackChange
            )) {
                Text("Auto fallback")
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(secondaryText)
            }
            .toggleStyle(.switch)
        }
        .padding(14)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        }
    }

    private var activeSourceText: String {
        let lastData = decision.lastDataAt.map { " · Last data \(Self.relativeFormatter.localizedString(for: $0, relativeTo: Date()))" } ?? ""
        if decision.isFallback, let activeSource = decision.displayedSource {
            return "\(HealthSourceDisplayCopy.preferredSource): \(decision.currentSource.priorityDisplayName) · \(HealthSourceDisplayCopy.activeSource): \(activeSource.priorityDisplayName) via fallback\(lastData)"
        }
        guard let activeSource = decision.displayedSource else {
            return "\(HealthSourceDisplayCopy.preferredSource): \(decision.currentSource.priorityDisplayName) · No recent \(decision.currentSource.priorityDisplayName) data available"
        }
        return "\(HealthSourceDisplayCopy.preferredSource): \(decision.currentSource.priorityDisplayName) · \(HealthSourceDisplayCopy.activeSource): \(activeSource.priorityDisplayName)\(lastData)"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.96) : Color(red: 0.07, green: 0.10, blue: 0.15)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.62) : Color(red: 0.35, green: 0.39, blue: 0.47)
    }

    private var fallbackTint: Color {
        colorScheme == .dark ? Color(red: 1.0, green: 0.70, blue: 0.38) : Color(red: 0.76, green: 0.34, blue: 0.08)
    }

    private var cardBackground: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [.white.opacity(0.10), Color(red: 0.05, green: 0.07, blue: 0.11).opacity(0.88)]
                : [.white.opacity(0.90), Color(red: 0.93, green: 0.97, blue: 1.0).opacity(0.66)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBorder: Color {
        colorScheme == .dark
            ? .white.opacity(0.12)
            : Color(red: 0.44, green: 0.56, blue: 0.70).opacity(0.22)
    }
}

private extension HealthSourceID {
    var priorityDisplayName: String {
        switch self {
        case .appleWatch:
            return "Apple Watch / HealthKit"
        case .ouraRing:
            return "Oura Ring"
        case .airPodsPro3:
            return "AirPods Pro 3"
        case .iPhone:
            return "iPhone Sensors"
        case .manual:
            return "Manual Entry"
        }
    }

    var shortDebugName: String {
        switch self {
        case .appleWatch:
            return "HK"
        case .ouraRing:
            return "Oura"
        case .airPodsPro3:
            return "AirPods"
        case .iPhone:
            return "iPhone"
        case .manual:
            return "Manual"
        }
    }
}

private extension HealthSourcePriorityCategory {
    var confirmationTitle: String {
        switch self {
        case .sleepRecovery:
            return "Sleep & Recovery"
        case .workoutsActivity:
            return "Workouts"
        case .activitySteps:
            return "Activity / Steps"
        case .heartMetrics:
            return "Heart Metrics"
        case .temperatureCycle:
            return "Temperature & Cycle"
        case .stressResilience:
            return "Stress & Resilience"
        case .manualEntries:
            return "Manual Entries"
        }
    }
}

private struct SourceChangeConfirmationBanner: View {
    let message: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(red: 0.18, green: 0.62, blue: 0.39))

            Text(message)
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(primaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(colorScheme == .dark ? .white.opacity(0.14) : Color.black.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.34 : 0.12), radius: 18, y: 10)
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.95) : Color(red: 0.07, green: 0.10, blue: 0.15)
    }
}

#if DEBUG
private struct SourceRoutingDebugPanel: View {
    @ObservedObject var manager: MeasurementSourceManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Source routing debug", systemImage: "ladybug")
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(primaryText)

            VStack(alignment: .leading, spacing: 9) {
                ForEach(HealthSourcePriorityCategory.allCases) { category in
                    let preference = manager.preference(for: category)
                    let decision = manager.routingDecision(for: category)
                    let resolutions = manager.metricRoutingResolutions(for: category)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(category.confirmationTitle)
                            .pulsarTextStyle(.overline)
                            .foregroundStyle(primaryText)
                        Text("Current \(preference.currentSource.priorityDisplayName) · Displayed \(decision.displayedSource?.priorityDisplayName ?? "none")\(decision.isFallback ? " · fallback" : "")")
                        Text("Switched \(relativeText(for: preference.sourceSwitchTimestamp)) · Last metric data \(relativeText(for: decision.lastDataAt))")
                        ForEach(resolutions) { resolution in
                            Text(metricDebugText(for: resolution))
                                .foregroundStyle(resolution.fallbackUsed || resolution.displayedRecordSource == nil ? fallbackTint : secondaryText)
                            if let reason = resolution.fallbackReason, resolution.fallbackUsed || resolution.displayedRecordSource == nil {
                                Text("Reason: \(reason)")
                                    .foregroundStyle(fallbackTint)
                            }
                        }
                    }
                    .pulsarTextStyle(.overline)
                    .foregroundStyle(secondaryText)
                }
            }

            Divider()
                .overlay(secondaryText.opacity(0.24))

            VStack(alignment: .leading, spacing: 5) {
                Text("Connections")
                    .pulsarTextStyle(.overline)
                    .foregroundStyle(primaryText)
                ForEach(manager.sourcePrioritySnapshots, id: \.sourceID) { snapshot in
                    Text("\(snapshot.sourceID.priorityDisplayName): sync \(relativeText(for: snapshot.lastSyncAt)) · \(snapshot.connectionState.debugLabel)")
                        .pulsarTextStyle(.overline)
                        .foregroundStyle(secondaryText)
                }
            }
        }
        .padding(13)
        .background(debugBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        }
    }

    private func relativeText(for date: Date?) -> String {
        guard let date else { return "none" }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func metricDebugText(for resolution: MetricSourceResolution) -> String {
        let displayed = resolution.displayedRecordSource?.priorityDisplayName ?? "none"
        let sampleCounts = resolution.sourceAvailabilityByProvider
            .filter { $0.source != .manual || $0.sampleCount > 0 }
            .map { "\($0.source.shortDebugName) \($0.sampleCount)" }
            .joined(separator: " · ")
        return "\(resolution.metricTitle): current \(resolution.currentSource.priorityDisplayName) · displayed \(displayed) · latest \(relativeText(for: resolution.lastAvailableSampleDate)) · \(sampleCounts)"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.94) : Color(red: 0.08, green: 0.11, blue: 0.16)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.64) : Color(red: 0.35, green: 0.39, blue: 0.47)
    }

    private var fallbackTint: Color {
        colorScheme == .dark ? Color(red: 1.0, green: 0.70, blue: 0.38) : Color(red: 0.76, green: 0.34, blue: 0.08)
    }

    private var debugBackground: Color {
        colorScheme == .dark ? .white.opacity(0.07) : Color(red: 0.96, green: 0.98, blue: 1.0).opacity(0.82)
    }

    private var cardBorder: Color {
        colorScheme == .dark ? .white.opacity(0.12) : Color(red: 0.44, green: 0.56, blue: 0.70).opacity(0.22)
    }
}
#endif

private extension SourceConnectionState {
    var debugLabel: String {
        switch self {
        case .connected:
            return "connected"
        case .available:
            return "available"
        case .setupRequired:
            return "setup required"
        case .syncing:
            return "syncing"
        case .authExpired:
            return "auth expired"
        case .missingScopes:
            return "missing scopes"
        case .rateLimited:
            return "rate limited"
        case .syncError:
            return "sync error"
        case .disconnected:
            return "disconnected"
        }
    }
}

private struct MeasurementDeviceDetailPanel: View {
    let device: MeasurementDevice
    let isPrimaryActionDisabled: Bool
    let onAction: () -> Void
    let onSync: () -> Void
    let onDisconnect: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(detailTitle)
                        .pulsarTextStyle(.cardTitle)
                        .foregroundStyle(primaryText)
                    Text(detailSubtitle)
                        .pulsarTextStyle(.label)
                        .foregroundStyle(secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                DeviceStatusPill(text: device.connectionStatus.label, tint: statusTint)
            }

            HStack(alignment: .center, spacing: 16) {
                DeviceProductImageView(
                    assetName: device.type.assetName,
                    deviceType: device.type,
                    mode: .detail
                )
                    .frame(width: 134, height: 138)

                VStack(alignment: .leading, spacing: 11) {
                    Text(device.name)
                        .pulsarTextStyle(.sectionHeader)
                        .foregroundStyle(primaryText)
                        .lineLimit(2)

                    PremiumBatteryStatusView(percentage: device.batteryPercentage, style: .compact, tint: tint)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Last sync")
                            .pulsarTextStyle(.overline)
                            .foregroundStyle(secondaryText)
                        Text(lastSyncText)
                            .pulsarTextStyle(.captionEmphasis)
                            .foregroundStyle(primaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 94), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(device.supportedMetrics) { metric in
                    Text(metric.label)
                        .pulsarTextStyle(.overline)
                        .foregroundStyle(metricText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(metricBackground, in: Capsule(style: .continuous))
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(cardBorder, lineWidth: 1)
                        }
                }
            }

            Text(explanation)
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(insetBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(cardBorder, lineWidth: 1)
                }

            Button(action: onAction) {
                Text(device.primaryActionTitle)
                    .pulsarTextStyle(.label)
                    .foregroundStyle(buttonText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(buttonBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(buttonBorder, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .disabled(isPrimaryActionDisabled)

            if device.connectionStatus == .connected || device.connectionStatus == .syncError {
                HStack(spacing: 10) {
                    Button(action: onSync) {
                        Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                            .pulsarTextStyle(.captionEmphasis)
                            .foregroundStyle(tint)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(metricBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(buttonBorder, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)

                    if device.type == .ouraRing {
                        Button(action: onDisconnect) {
                            Label("Disconnect", systemImage: "xmark.circle")
                                .pulsarTextStyle(.captionEmphasis)
                                .foregroundStyle(statusTint)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(metricBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(cardBorder, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(17)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        }
    }

    private var detailSubtitle: String {
        switch device.type {
        case .appleWatch:
            return device.isActiveSource ? "Powering your current health measurements." : "Available for wearable measurements."
        case .ouraRing:
            switch device.connectionStatus {
            case .connected:
                return "Oura Ring connected. Cloud sync is enabled for sleep, recovery, HRV, temperature trends, activity, and workouts."
            case .connecting:
                return "Waiting for Oura authorization."
            case .syncError:
                return "Oura is connected, but the last sync needs attention."
            case .tokenExpired:
                return "Connect Oura again to refresh authorization."
            case .setupRequired:
                #if DEBUG
                return "Backend token exchange must be configured before OAuth can start."
                #else
                return "Oura connection is not available yet."
                #endif
            case .available, .disconnected:
                return "Sign in with Oura to sync sleep, recovery, HRV, temperature trends, and activity."
            }
        case .airPodsPro3:
            return "AirPods Pro 3 heart rate is available only during workouts. It is recommended as a backup source if your Apple Watch or Garmin runs out of battery or loses connection."
        }
    }

    private var detailTitle: String {
        if device.type == .airPodsPro3 {
            return "Emergency workout backup"
        }
        if device.type == .ouraRing, device.connectionStatus != .connected {
            return "Connect your Oura Ring"
        }
        return "Device details"
    }

    private var explanation: String {
        switch device.type {
        case .appleWatch:
            return "Apple Watch data is prioritized for sleep, recovery, strain, stress, and workout metrics when it is the active source."
        case .ouraRing:
            return "Pulsar reads Oura cloud data after the ring syncs to Oura. This is not direct Bluetooth or live ring streaming."
        case .airPodsPro3:
            return "Pulsar never uses AirPods Pro 3 for daily tracking, recovery, stress scoring, strain, steps, sleep, HRV, or always-on monitoring. Heart-rate data is consumed only through Apple-supported HealthKit workout flows; Pulsar does not pair with AirPods or read sensors directly."
        }
    }

    private var lastSyncText: String {
        guard let lastSyncAt = device.lastSyncAt else { return "Unavailable" }
        return lastSyncAt.formatted(.relative(presentation: .named))
    }

    private var tint: Color {
        switch device.type {
        case .appleWatch:
            return colorScheme == .dark ? Color(red: 0.72, green: 0.86, blue: 1.0) : Color(red: 0.08, green: 0.34, blue: 0.58)
        case .ouraRing:
            return colorScheme == .dark ? Color(red: 0.72, green: 0.78, blue: 0.90) : Color(red: 0.18, green: 0.24, blue: 0.34)
        case .airPodsPro3:
            return colorScheme == .dark ? .white.opacity(0.88) : Color(red: 0.45, green: 0.50, blue: 0.58)
        }
    }

    private var statusTint: Color {
        switch device.connectionStatus {
        case .connected:
            return colorScheme == .dark ? Color(red: 0.36, green: 0.94, blue: 0.68) : Color(red: 0.00, green: 0.47, blue: 0.30)
        case .available, .connecting:
            return tint
        case .setupRequired, .tokenExpired, .syncError:
            return colorScheme == .dark ? Color(red: 1.0, green: 0.70, blue: 0.38) : Color(red: 0.76, green: 0.34, blue: 0.08)
        case .disconnected:
            return secondaryText
        }
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.96) : Color(red: 0.07, green: 0.10, blue: 0.15)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.63) : Color(red: 0.35, green: 0.39, blue: 0.47)
    }

    private var metricText: Color {
        colorScheme == .dark ? .white.opacity(0.72) : Color(red: 0.24, green: 0.30, blue: 0.38)
    }

    private var cardBackground: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [.white.opacity(0.11), Color(red: 0.05, green: 0.07, blue: 0.11).opacity(0.90)]
                : [.white.opacity(0.92), Color(red: 0.93, green: 0.97, blue: 1.0).opacity(0.70)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var insetBackground: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [.white.opacity(0.07), .white.opacity(0.035)]
                : [Color.white.opacity(0.72), Color(red: 0.91, green: 0.96, blue: 1.0).opacity(0.42)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var metricBackground: Color {
        colorScheme == .dark ? .white.opacity(0.065) : Color.white.opacity(0.60)
    }

    private var buttonBackground: LinearGradient {
        if device.isActiveSource {
            return LinearGradient(
                colors: colorScheme == .dark ? [.white.opacity(0.07), .white.opacity(0.04)] : [Color.white.opacity(0.64), Color.white.opacity(0.34)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        if !device.canBecomeActiveSource {
            return LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 1.0, green: 0.64, blue: 0.28).opacity(0.15), .white.opacity(0.04)]
                    : [Color(red: 1.0, green: 0.75, blue: 0.42).opacity(0.24), Color.white.opacity(0.46)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: colorScheme == .dark ? [tint.opacity(0.26), tint.opacity(0.12)] : [tint.opacity(0.20), Color.white.opacity(0.58)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var buttonText: Color {
        if device.isActiveSource { return secondaryText }
        if !device.canBecomeActiveSource { return statusTint }
        return colorScheme == .dark ? .white.opacity(0.94) : tint
    }

    private var buttonBorder: Color {
        if device.isActiveSource { return cardBorder }
        return tint.opacity(colorScheme == .dark ? 0.22 : 0.18)
    }

    private var cardBorder: Color {
        colorScheme == .dark
            ? .white.opacity(0.12)
            : Color(red: 0.44, green: 0.56, blue: 0.70).opacity(0.22)
    }
}

private enum BatteryStatusStyle {
    case compact
    case hero
}

private struct PremiumBatteryStatusView: View {
    let percentage: Int?
    var style: BatteryStatusStyle = .compact
    let tint: Color

    @State private var animatedLevel: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let percentage {
                chargedView(percentage: percentage)
                    .onAppear {
                        animatedLevel = 0
                        withAnimation(.easeOut(duration: 0.9)) {
                            animatedLevel = CGFloat(max(0, min(percentage, 100))) / 100
                        }
                    }
                    .onChange(of: percentage) { _, newValue in
                        withAnimation(.easeOut(duration: 0.75)) {
                            animatedLevel = CGFloat(max(0, min(newValue, 100))) / 100
                        }
                    }
            } else {
                unavailableView
            }
        }
    }

    @ViewBuilder
    private func chargedView(percentage: Int) -> some View {
        let content = HStack(spacing: style == .hero ? 13 : 8) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(colorScheme == .dark ? 0.09 : 0.16), lineWidth: style == .hero ? 7 : 4)
                Circle()
                    .trim(from: 0, to: animatedLevel)
                    .stroke(
                        batteryTint,
                        style: StrokeStyle(lineWidth: style == .hero ? 6 : 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Image(systemName: "bolt.fill")
                    .font(.system(size: style == .hero ? 10 : 7, weight: .bold))
                    .foregroundStyle(batteryTint)
                    .opacity(0.0)
            }
            .frame(width: style == .hero ? 48 : 26, height: style == .hero ? 48 : 26)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(percentage)%")
                    .font(style == .hero ? .system(size: 21, weight: .bold, design: .default) : .caption.weight(.bold))
                    .foregroundStyle(primaryText)
                Text("Battery")
                    .font(.system(size: style == .hero ? 14 : 11, weight: .medium, design: .default))
                    .foregroundStyle(secondaryText)
            }
        }
        .padding(style == .hero ? 12 : 0)
        .frame(maxWidth: style == .hero ? .infinity : nil, alignment: .leading)

        if style == .hero {
            content.background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
        } else {
            content
        }
    }

    @ViewBuilder
    private var unavailableView: some View {
        let content = HStack(spacing: style == .hero ? 11 : 8) {
            ZStack {
                Circle()
                    .fill(colorScheme == .dark ? .white.opacity(0.065) : Color.white.opacity(0.58))
                Image(systemName: "battery.0")
                    .font(.system(size: style == .hero ? 15 : 11, weight: .semibold))
                    .foregroundStyle(secondaryText)
            }
            .frame(width: style == .hero ? 42 : 26, height: style == .hero ? 42 : 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(style == .hero ? "No data" : "Battery unavailable")
                    .font(style == .hero ? .system(size: 20, weight: .bold, design: .default) : .caption.weight(.bold))
                    .foregroundStyle(primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                if style == .hero {
                    Text("Battery")
                        .font(.system(size: 14, weight: .medium, design: .default))
                        .foregroundStyle(secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
        }
        .padding(style == .hero ? 13 : 0)
        .frame(maxWidth: style == .hero ? .infinity : nil, alignment: .leading)

        if style == .hero {
            content.background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
        } else {
            content
        }
    }

    private var batteryTint: Color {
        guard let percentage else { return secondaryText }
        if style == .hero {
            return colorScheme == .dark ? Color(red: 0.42, green: 0.66, blue: 1.0) : Color(red: 0.08, green: 0.34, blue: 0.58)
        }
        switch percentage {
        case 0..<20:
            return colorScheme == .dark ? Color(red: 1.0, green: 0.33, blue: 0.34) : Color(red: 0.78, green: 0.07, blue: 0.12)
        case 20..<45:
            return colorScheme == .dark ? Color(red: 1.0, green: 0.70, blue: 0.32) : Color(red: 0.78, green: 0.40, blue: 0.04)
        default:
            return colorScheme == .dark ? Color(red: 0.36, green: 0.94, blue: 0.68) : Color(red: 0.00, green: 0.50, blue: 0.32)
        }
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.95) : Color(red: 0.08, green: 0.11, blue: 0.16)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.58) : Color(red: 0.38, green: 0.42, blue: 0.50)
    }

    private var insetBackground: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [.white.opacity(0.075), .white.opacity(0.035)]
                : [Color.white.opacity(0.70), Color(red: 0.91, green: 0.96, blue: 1.0).opacity(0.42)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBorder: Color {
        colorScheme == .dark
            ? .white.opacity(0.12)
            : Color(red: 0.44, green: 0.56, blue: 0.70).opacity(0.22)
    }
}

private enum DeviceProductImageMode {
    case hero
    case card
    case detail
}

private struct DeviceProductImageView: View {
    let assetName: String
    let deviceType: MeasurementDeviceType
    let mode: DeviceProductImageMode
    var maxHeight: CGFloat?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        GeometryReader { proxy in
            let resolvedHeight = maxHeight.map { min(proxy.size.height, $0) } ?? proxy.size.height
            let containerSize = CGSize(width: proxy.size.width, height: resolvedHeight)

            ZStack {
                productGlow(in: containerSize)

                productImage
                    .frame(
                        width: containerSize.width * imageWidthMultiplier,
                        height: containerSize.height * imageHeightMultiplier
                    )
                    .scaleEffect(deviceScale)
                    .offset(y: imageVerticalOffset)
                    .shadow(
                        color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.12),
                        radius: mode == .hero ? 15 : 8,
                        y: mode == .hero ? 12 : 6
                    )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .opacity(hasAppeared ? 1 : 0)
            .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.98)
        }
        .onAppear {
            guard !hasAppeared else { return }
            withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.48, dampingFraction: 0.90)) {
                hasAppeared = true
            }
        }
    }

    @ViewBuilder
    private var productImage: some View {
        if UIImage(named: assetName) != nil {
            Image(assetName)
                .interpolation(.high)
                .antialiased(true)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
        } else {
            fallbackRender
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var fallbackRender: some View {
        switch deviceType {
        case .appleWatch:
            AppleWatchDeviceIllustrationView(tint: tint)
        case .ouraRing:
            OuraRingDeviceIllustrationView(tint: tint)
        case .airPodsPro3:
            Image(systemName: "airpodspro")
                .font(.system(size: 96, weight: .semibold))
                .foregroundStyle(tint)
        }
    }

    private func productGlow(in size: CGSize) -> some View {
        RadialGradient(
            colors: [
                tint.opacity(colorScheme == .dark ? (mode == .hero ? 0.10 : 0.055) : 0.05),
                .clear
            ],
            center: .center,
            startRadius: 0,
            endRadius: size.height * 0.48
        )
        .frame(width: size.height * 0.90, height: size.height * 0.74)
        .blur(radius: mode == .hero ? 12 : 8)
    }

    private var imageWidthMultiplier: CGFloat {
        switch mode {
        case .hero:
            return 0.86
        case .card:
            return 0.88
        case .detail:
            return 0.94
        }
    }

    private var imageHeightMultiplier: CGFloat {
        switch mode {
        case .hero:
            return 0.96
        case .card:
            return 0.94
        case .detail:
            return 0.92
        }
    }

    private var deviceScale: CGFloat {
        switch (deviceType, mode) {
        case (.appleWatch, .hero):
            return 1.05
        case (.appleWatch, .card):
            return 1.04
        case (.appleWatch, .detail):
            return 1.02
        case (.ouraRing, .hero):
            return 0.92
        case (.ouraRing, .card):
            return 0.92
        case (.ouraRing, .detail):
            return 0.93
        case (.airPodsPro3, .hero):
            return 0.92
        case (.airPodsPro3, .card):
            return 0.94
        case (.airPodsPro3, .detail):
            return 0.96
        }
    }

    private var imageVerticalOffset: CGFloat {
        switch (deviceType, mode) {
        case (.appleWatch, .hero):
            return -4
        case (.ouraRing, .hero):
            return 2
        default:
            return 0
        }
    }

    private var tint: Color {
        switch deviceType {
        case .appleWatch:
            return colorScheme == .dark ? Color(red: 0.72, green: 0.86, blue: 1.0) : Color(red: 0.08, green: 0.34, blue: 0.58)
        case .ouraRing:
            return colorScheme == .dark ? Color(red: 0.72, green: 0.78, blue: 0.90) : Color(red: 0.18, green: 0.24, blue: 0.34)
        case .airPodsPro3:
            return colorScheme == .dark ? .white.opacity(0.86) : Color(red: 0.52, green: 0.56, blue: 0.63)
        }
    }
}

private struct AppleWatchDeviceIllustrationView: View {
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                VStack(spacing: -size * 0.04) {
                    strapSegment(height: size * 0.34, top: true)
                    Color.clear.frame(height: size * 0.42)
                    strapSegment(height: size * 0.34, top: false)
                }
                .frame(width: size * 0.42)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.10), radius: 18, y: 10)

                RoundedRectangle(cornerRadius: size * 0.19, style: .continuous)
                    .fill(bodyGradient)
                    .frame(width: size * 0.70, height: size * 0.80)
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.19, style: .continuous)
                            .stroke(.white.opacity(colorScheme == .dark ? 0.30 : 0.72), lineWidth: 1.2)
                    }
                    .shadow(color: tint.opacity(colorScheme == .dark ? 0.16 : 0.08), radius: 16, y: 10)

                RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
                    .fill(screenGradient)
                    .frame(width: size * 0.54, height: size * 0.62)
                    .overlay(alignment: .topTrailing) {
                        RoundedRectangle(cornerRadius: size * 0.10, style: .continuous)
                            .fill(.white.opacity(colorScheme == .dark ? 0.14 : 0.24))
                            .frame(width: size * 0.19, height: size * 0.40)
                            .rotationEffect(.degrees(28))
                            .offset(x: -size * 0.08, y: -size * 0.03)
                            .blur(radius: 0.4)
                    }
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: size * 0.035) {
                            Circle()
                                .fill(tint)
                                .frame(width: size * 0.075, height: size * 0.075)
                            Capsule(style: .continuous)
                                .fill(.white.opacity(colorScheme == .dark ? 0.58 : 0.70))
                                .frame(width: size * 0.31, height: max(size * 0.025, 2))
                            Capsule(style: .continuous)
                                .fill(tint.opacity(0.84))
                                .frame(width: size * 0.22, height: max(size * 0.025, 2))
                        }
                        .padding(size * 0.10)
                    }

                Capsule(style: .continuous)
                    .fill(crownGradient)
                    .frame(width: size * 0.062, height: size * 0.22)
                    .offset(x: size * 0.39, y: -size * 0.10)

                Capsule(style: .continuous)
                    .fill(crownGradient.opacity(0.78))
                    .frame(width: size * 0.044, height: size * 0.13)
                    .offset(x: -size * 0.39, y: size * 0.12)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func strapSegment(height: CGFloat, top: Bool) -> some View {
        RoundedRectangle(cornerRadius: height * 0.26, style: .continuous)
            .fill(strapGradient)
            .overlay {
                RoundedRectangle(cornerRadius: height * 0.26, style: .continuous)
                    .stroke(.white.opacity(colorScheme == .dark ? 0.10 : 0.48), lineWidth: 1)
            }
            .frame(height: height)
            .mask {
                RoundedRectangle(cornerRadius: height * (top ? 0.24 : 0.30), style: .continuous)
            }
    }

    private var strapGradient: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.white.opacity(0.13), tint.opacity(0.14), Color.black.opacity(0.34)]
                : [Color.white.opacity(0.96), tint.opacity(0.10), Color(red: 0.74, green: 0.82, blue: 0.91).opacity(0.62)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var bodyGradient: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.white.opacity(0.34), Color(red: 0.13, green: 0.16, blue: 0.21), Color.black.opacity(0.48)]
                : [Color.white, Color(red: 0.79, green: 0.85, blue: 0.92), Color(red: 0.44, green: 0.54, blue: 0.64).opacity(0.60)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var screenGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.02, green: 0.05, blue: 0.09),
                tint.opacity(colorScheme == .dark ? 0.30 : 0.38),
                Color.black.opacity(0.92)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var crownGradient: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.white.opacity(0.28), Color.black.opacity(0.44)]
                : [Color.white.opacity(0.92), Color(red: 0.55, green: 0.64, blue: 0.72).opacity(0.64)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct OuraRingDeviceIllustrationView: View {
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                Ellipse()
                    .fill(.black.opacity(colorScheme == .dark ? 0.34 : 0.12))
                    .frame(width: size * 0.72, height: size * 0.18)
                    .blur(radius: 12)
                    .offset(y: size * 0.34)

                Circle()
                    .fill(tint.opacity(colorScheme == .dark ? 0.16 : 0.08))
                    .frame(width: size * 0.78, height: size * 0.78)
                    .blur(radius: 22)

                ringBody(size: size, lineWidth: size * 0.19)
                    .frame(width: size * 0.72, height: size * 0.54)
                    .rotationEffect(.degrees(-10))

                ringHighlight(size: size)
                    .frame(width: size * 0.72, height: size * 0.54)
                    .rotationEffect(.degrees(-10))

                sensorCluster(size: size)
                    .offset(x: size * 0.22, y: -size * 0.08)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func ringBody(size: CGFloat, lineWidth: CGFloat) -> some View {
        Ellipse()
            .stroke(ringShadowGradient, lineWidth: lineWidth)
            .overlay {
                Ellipse()
                    .stroke(.white.opacity(colorScheme == .dark ? 0.24 : 0.66), lineWidth: lineWidth * 0.26)
                    .blur(radius: 0.6)
                    .offset(x: -size * 0.018, y: -size * 0.018)
            }
            .shadow(color: tint.opacity(colorScheme == .dark ? 0.24 : 0.12), radius: 20, y: 12)
    }

    private func ringHighlight(size: CGFloat) -> some View {
        ZStack {
            Ellipse()
                .trim(from: 0.04, to: 0.26)
                .stroke(.white.opacity(colorScheme == .dark ? 0.42 : 0.88), style: StrokeStyle(lineWidth: size * 0.045, lineCap: .round))
            Ellipse()
                .trim(from: 0.55, to: 0.78)
                .stroke(tint.opacity(colorScheme == .dark ? 0.58 : 0.44), style: StrokeStyle(lineWidth: size * 0.04, lineCap: .round))
        }
    }

    private func sensorCluster(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(tint)
                .frame(width: size * 0.052, height: size * 0.052)
            Circle()
                .fill(.white.opacity(colorScheme == .dark ? 0.62 : 0.88))
                .frame(width: size * 0.038, height: size * 0.038)
                .offset(x: size * 0.070, y: size * 0.045)
            Circle()
                .fill(.white.opacity(colorScheme == .dark ? 0.48 : 0.72))
                .frame(width: size * 0.030, height: size * 0.030)
                .offset(x: -size * 0.058, y: size * 0.052)
        }
    }

    private var ringShadowGradient: AngularGradient {
        AngularGradient(
            colors: colorScheme == .dark
                ? [
                    Color.white.opacity(0.34),
                    tint.opacity(0.62),
                    Color(red: 0.08, green: 0.10, blue: 0.12),
                    Color.white.opacity(0.22),
                    tint.opacity(0.44)
                ]
                : [
                    Color.white,
                    tint.opacity(0.48),
                    Color(red: 0.45, green: 0.53, blue: 0.60).opacity(0.56),
                    Color.white.opacity(0.92),
                    tint.opacity(0.36)
                ],
            center: .center
        )
    }
}

private struct MetricPreviewStrip: View {
    let metrics: [MeasurementHealthMetricType]
    let tint: Color

    var body: some View {
        let visibleMetrics = displayMetrics
        let columnCount = max(visibleMetrics.count, 1)
        let columns = Array(
            repeating: GridItem(.flexible(minimum: 0), spacing: 4, alignment: .center),
            count: columnCount
        )
        let preferredWidth = CGFloat(columnCount * 64 + max(columnCount - 1, 0) * 4)

        LazyVGrid(columns: columns, alignment: .center, spacing: 0) {
            ForEach(visibleMetrics) { metric in
                MetricPill(metric: metric, tint: tint)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: preferredWidth)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    private var displayMetrics: [MeasurementHealthMetricType] {
        let preferred: [MeasurementHealthMetricType] = [.heartRate, .hrv, .respiratoryRate, .sleep, .activity]
        let available = preferred.filter { metrics.contains($0) }
        return available.isEmpty ? Array(metrics.prefix(5)) : available
    }
}

private struct MetricPill: View {
    let metric: MeasurementHealthMetricType
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: metric.symbolName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.065), in: Circle())

            Text(metric.heroLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.52)
                .allowsTightening(true)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct DeviceStatusPill: View {
    let text: String
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .pulsarTextStyle(.overline)
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(tint.opacity(colorScheme == .dark ? 0.14 : 0.09), in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(tint.opacity(colorScheme == .dark ? 0.24 : 0.16), lineWidth: 1)
            }
    }
}

private extension MeasurementDeviceType {
    var symbolName: String {
        switch self {
        case .appleWatch:
            return "applewatch"
        case .ouraRing:
            return "circle"
        case .airPodsPro3:
            return "airpodspro"
        }
    }
}

private extension MeasurementHealthMetricType {
    var symbolName: String {
        switch self {
        case .heartRate:
            return "heart"
        case .hrv:
            return "waveform.path.ecg"
        case .respiratoryRate:
            return "lungs"
        case .sleep:
            return "moon"
        case .activity, .strain:
            return "figure.run"
        case .workouts:
            return "figure.strengthtraining.traditional"
        case .recovery, .readiness:
            return "sparkles"
        case .restingHeartRate:
            return "heart.circle"
        case .oxygenSaturation:
            return "drop"
        case .stress:
            return "brain.head.profile"
        case .temperature:
            return "thermometer.medium"
        case .cycle:
            return "moonphase.waxing.crescent"
        }
    }

    var heroLabel: String {
        switch self {
        case .respiratoryRate:
            return "Respiratory"
        case .heartRate:
            return "Heart rate"
        default:
            return label
        }
    }
}

private struct MeasurementSourceBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.006, green: 0.025, blue: 0.052),
                    Color(red: 0.012, green: 0.046, blue: 0.084),
                    Color(red: 0.010, green: 0.041, blue: 0.065),
                    Color(red: 0.004, green: 0.018, blue: 0.034)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    MeasurementSourcePalette.blueCore.opacity(0.16),
                    .clear
                ],
                center: UnitPoint(x: 0.82, y: 0.16),
                startRadius: 0,
                endRadius: 310
            )

            RadialGradient(
                colors: [
                    Color(red: 0.10, green: 0.30, blue: 0.42).opacity(0.10),
                    .clear
                ],
                center: UnitPoint(x: 0.15, y: 0.74),
                startRadius: 0,
                endRadius: 380
            )
        }
        .ignoresSafeArea()
    }
}

#Preview("Measurement Source") {
    MeasurementSourceSheet(manager: MeasurementSourceManager(), onDismiss: {})
}

#Preview("Measurement Source Dark") {
    MeasurementSourceSheet(manager: MeasurementSourceManager(), onDismiss: {})
        .preferredColorScheme(.dark)
}
