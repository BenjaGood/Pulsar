//
//  MeasurementSourceViews.swift
//  Pulsar
//

import SwiftUI
import UIKit

struct MeasurementSourceSheet: View {
    @ObservedObject var manager: MeasurementSourceManager
    var onSyncAppleHealthKit: () async -> Void = {}
    var onDismiss: () -> Void

    @State private var pendingSelectionType: MeasurementDeviceType?
    @State private var syncingDeviceType: MeasurementDeviceType?
    @State private var selectionConfirmation: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                header

                MeasurementActiveDeviceHero(device: manager.activeDevice)
                    .id(manager.activeDevice.type)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))

                deviceSelection
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
        .background {
            MeasurementSourceBackground()
                .clipShape(MeasurementModalTopShape(radius: 46))
                .ignoresSafeArea()
        }
        .overlay(alignment: .bottom) {
            if let selectionConfirmation {
                MeasurementSelectionConfirmationBanner(message: selectionConfirmation)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .preferredColorScheme(.light)
        .animation(.spring(response: 0.48, dampingFraction: 0.88), value: manager.activeDeviceType)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: pendingSelectionType)
        .animation(.easeInOut(duration: 0.18), value: manager.ouraConnectionFlowState)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: selectionConfirmation)
        .alert(item: ouraConnectionAlertBinding, content: makeOuraConnectionAlert)
        .onAppear {
            manager.refreshDeviceStatus()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text(dynamicTypeSize.isAccessibilitySize ? "Measurement\nSource" : "Measurement Source")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.72)
                    .accessibilityLabel("Measurement Source")

                Text("Choose which device powers your health metrics.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            Button("Close", systemImage: "xmark", action: onDismiss)
                .font(.body.weight(.semibold))
                .labelStyle(.iconOnly)
                .symbolRenderingMode(.monochrome)
                .tint(.primary)
                .buttonStyle(.glass(.clear))
                .buttonBorderShape(.circle)
                .controlSize(.regular)
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.018), in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.black.opacity(0.04), lineWidth: 0.75)
                }
        }
    }

    private var deviceSelection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Available Devices")
                .font(.title3.bold())
                .foregroundStyle(.primary)

            PulsarGlassEffectGroup(spacing: 10) {
                VStack(spacing: 10) {
                    ForEach(manager.availableDevices) { device in
                        MeasurementDeviceSourceRow(
                            device: device,
                            isSelected: selectedDeviceType == device.type,
                            isSyncing: syncingDeviceType == device.type,
                            isEnabled: device.type != .airPodsPro3
                        ) {
                            selectDevice(device.type)
                        }
                    }
                }
            }
        }
    }

    private var selectedDeviceType: MeasurementDeviceType {
        pendingSelectionType ?? manager.activeDeviceType
    }

    private func selectDevice(_ type: MeasurementDeviceType) {
        guard type != .airPodsPro3, syncingDeviceType == nil else { return }
        pendingSelectionType = type
        syncingDeviceType = type
        Task { await selectAndSync(type) }
    }

    @MainActor
    private func selectAndSync(_ type: MeasurementDeviceType) async {
        var device = manager.device(for: type)
        var alreadySynced = false

        if type == .ouraRing {
            switch device.connectionStatus {
            case .setupRequired, .disconnected, .tokenExpired:
                await manager.connectOura()
                device = manager.device(for: type)
            case .syncError:
                await manager.syncOuraNow()
                device = manager.device(for: type)
                alreadySynced = true
            case .connecting:
                finishSelection()
                return
            case .connected, .available:
                break
            }
        }

        guard device.canBecomeActiveSource else {
            finishSelection()
            return
        }

        if !device.isActiveSource {
            manager.selectActiveDevice(device)
        }

        showSelectionConfirmation(for: device)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        if !alreadySynced {
            await sync(device)
        }

        finishSelection()
    }

    private func sync(_ device: MeasurementDevice) async {
        switch device.type {
        case .appleWatch:
            await onSyncAppleHealthKit()
        case .ouraRing:
            await manager.syncOuraNow()
        case .airPodsPro3:
            break
        }
    }

    private func showSelectionConfirmation(for device: MeasurementDevice) {
        let message = "\(device.name) selected"
        selectionConfirmation = message

        Task {
            try? await Task.sleep(for: .seconds(1.8))
            await MainActor.run {
                if selectionConfirmation == message {
                    selectionConfirmation = nil
                }
            }
        }
    }

    private func finishSelection() {
        pendingSelectionType = nil
        syncingDeviceType = nil
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
}

private enum MeasurementSourcePalette {
    static let connected = Color(red: 0.06, green: 0.72, blue: 0.43)
    static let mutedDot = Color(red: 0.56, green: 0.59, blue: 0.65)
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
        opacity: Double = 0.12,
        isInteractive: Bool = false
    ) -> some View {
        pulsarLiquidGlass(
            cornerRadius: cornerRadius,
            tint: Color.white.opacity(opacity),
            interactive: isInteractive
        )
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.black.opacity(0.045), lineWidth: 0.75)
        }
    }
}

private struct MeasurementActiveDeviceHero: View {
    let device: MeasurementDevice

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                regularLayout
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 18)
        .frame(
            height: dynamicTypeSize.isAccessibilitySize ? 900 : 424,
            alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center
        )
        .measurementGlassSurface(cornerRadius: 32, opacity: 0.16)
        .shadow(color: .black.opacity(0.055), radius: 28, y: 14)
        .accessibilityElement(children: .contain)
    }

    private var regularLayout: some View {
        VStack(spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                heroInformation
                    .frame(width: 176, alignment: .leading)

                MeasurementHeroProductImage(device: device)
                    .frame(maxWidth: .infinity)
                    .frame(height: 286)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 292)

            MeasurementHeroMetricStrip(metrics: device.supportedMetrics)
        }
    }

    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 20) {
            heroInformation

            MeasurementHeroProductImage(device: device)
                .frame(maxWidth: .infinity)
                .frame(height: 250)

            MeasurementHeroMetricStrip(metrics: device.supportedMetrics)
        }
    }

    private var heroInformation: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(device.name)
                    .font(.title3.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
            } icon: {
                Image(systemName: device.type == .appleWatch ? "apple.logo" : device.type.heroSymbolName)
                    .font(.title3.bold())
                    .frame(width: 28)
            }
            .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 10) {
                MeasurementHeroStatusChip(
                    text: device.connectionStatus.label,
                    tint: statusTint,
                    symbolName: nil
                )
                MeasurementHeroStatusChip(
                    text: HealthSourceDisplayCopy.preferredSource,
                    tint: .secondary,
                    symbolName: "star"
                )
            }

            VStack(alignment: .leading, spacing: 12) {
                MeasurementHeroBatteryView(percentage: device.batteryPercentage)

                HStack(spacing: 11) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.74), in: Circle())
                        .overlay {
                            Circle()
                                .stroke(Color.black.opacity(0.04), lineWidth: 0.75)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last sync")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(lastSyncText)
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(0.04), lineWidth: 0.75)
                }
            }
        }
    }

    private var lastSyncText: String {
        guard let lastSyncAt = device.lastSyncAt else { return "Unavailable" }
        return lastSyncAt.formatted(.relative(presentation: .named))
    }

    private var statusTint: Color {
        switch device.connectionStatus {
        case .connected:
            return MeasurementSourcePalette.connected
        case .available, .connecting:
            return .secondary
        case .setupRequired, .tokenExpired, .syncError:
            return Color(red: 0.76, green: 0.34, blue: 0.08)
        case .disconnected:
            return .secondary
        }
    }
}

private struct MeasurementHeroStatusChip: View {
    let text: String
    let tint: Color
    let symbolName: String?

    var body: some View {
        HStack(spacing: 8) {
            if let symbolName {
                Image(systemName: symbolName)
                    .font(.subheadline.bold())
            } else {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
            }

            Text(text)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.70), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.black.opacity(0.045), lineWidth: 0.75)
        }
    }
}

private struct MeasurementHeroBatteryView: View {
    let percentage: Int?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedLevel: CGFloat = 0

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .stroke(Color.black.opacity(0.055), lineWidth: 5)

                if percentage != nil {
                    Circle()
                        .trim(from: 0, to: animatedLevel)
                        .stroke(
                            MeasurementSourcePalette.connected,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                } else {
                    Image(systemName: "battery.0")
                        .font(.body.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 2) {
                Text(percentage.map { "\($0)%" } ?? "No data")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text("Battery")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.66), in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.black.opacity(0.04), lineWidth: 0.75)
        }
        .onAppear(perform: updateLevel)
        .onChange(of: percentage) { _, _ in
            updateLevel()
        }
    }

    private func updateLevel() {
        let level = CGFloat(max(0, min(percentage ?? 0, 100))) / 100
        withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .easeOut(duration: 0.85)) {
            animatedLevel = level
        }
    }
}

private struct MeasurementHeroProductImage: View {
    let device: MeasurementDevice

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var hasAppeared = false

    var body: some View {
        Image(device.type.assetName)
            .interpolation(.high)
            .antialiased(true)
            .resizable()
            .scaledToFit()
            .scaleEffect(productScale)
            .shadow(color: .black.opacity(0.09), radius: 14, y: 10)
            .opacity(hasAppeared ? 1 : 0)
            .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.98)
            .onAppear {
                guard !hasAppeared else { return }
                withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.48, dampingFraction: 0.90)) {
                    hasAppeared = true
                }
            }
            .accessibilityHidden(true)
    }

    private var productScale: CGFloat {
        if dynamicTypeSize.isAccessibilitySize {
            return device.type == .appleWatch ? 1.0 : 0.90
        }

        switch device.type {
        case .appleWatch:
            return 1.34
        case .ouraRing:
            return 1.10
        case .airPodsPro3:
            return 1.04
        }
    }
}

private struct MeasurementHeroMetricStrip: View {
    let metrics: [MeasurementHealthMetricType]

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 0), spacing: 4, alignment: .center),
        count: 5
    )

    var body: some View {
        LazyVGrid(columns: columns, alignment: .center, spacing: 0) {
            ForEach(displayMetrics) { metric in
                VStack(spacing: 6) {
                    Image(systemName: metric.heroSymbolName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color(red: 0.24, green: 0.27, blue: 0.32))
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.74), in: Circle())
                        .overlay {
                            Circle()
                                .stroke(Color.black.opacity(0.04), lineWidth: 0.75)
                        }
                        .shadow(color: .black.opacity(0.035), radius: 8, y: 4)

                    Text(metric.heroLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.52)
                        .allowsTightening(true)
                        .frame(maxWidth: .infinity)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 16)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.055))
                .frame(height: 0.5)
        }
    }

    private var displayMetrics: [MeasurementHealthMetricType] {
        let preferred: [MeasurementHealthMetricType] = [.heartRate, .hrv, .respiratoryRate, .sleep, .activity]
        let available = preferred.filter { metrics.contains($0) }
        return available.isEmpty ? Array(metrics.prefix(5)) : available
    }
}

private struct MeasurementDeviceSourceRow: View {
    let device: MeasurementDevice
    let isSelected: Bool
    let isSyncing: Bool
    let isEnabled: Bool
    let onSelect: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                Image(device.type.assetName)
                    .interpolation(.high)
                    .antialiased(true)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 54, height: 54)
                    .shadow(color: .black.opacity(0.055), radius: 6, y: 4)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(device.name)
                        .font(.headline)
                        .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    HStack(spacing: 6) {
                        if isSyncing {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(MeasurementSourcePalette.connected)
                        } else {
                            Circle()
                                .fill(statusDotTint)
                                .frame(width: 7, height: 7)
                        }

                        Text(statusText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(statusTextColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.subheadline.bold())
                        .foregroundStyle(MeasurementSourcePalette.connected)
                        .frame(width: 32, height: 32)
                        .background(.white.opacity(0.92), in: Circle())
                        .overlay {
                            Circle()
                                .stroke(Color.black.opacity(0.045), lineWidth: 0.75)
                        }
                        .shadow(color: .black.opacity(0.07), radius: 10, y: 5)
                        .transition(.scale.combined(with: .opacity))
                } else if !isEnabled {
                    Image(systemName: "minus")
                        .font(.subheadline.bold())
                        .foregroundStyle(.tertiary)
                        .frame(width: 32, height: 32)
                        .background(.black.opacity(0.025), in: Circle())
                } else {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.bold())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .measurementGlassSurface(
                cornerRadius: 22,
                opacity: isSelected ? 0.19 : 0.11,
                isInteractive: isEnabled
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(selectionStroke, lineWidth: 0.75)
            }
            .shadow(
                color: .black.opacity(isSelected ? 0.06 : 0.025),
                radius: isSelected ? 18 : 12,
                y: isSelected ? 9 : 6
            )
            .scaleEffect(isSelected && !reduceMotion ? 1.006 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(device.name), \(statusText)")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var selectionStroke: Color {
        isSelected ? MeasurementSourcePalette.connected.opacity(0.18) : .clear
    }

    private var statusText: String {
        guard isEnabled else { return "Unavailable as a preferred source" }
        return device.connectionStatus == .connected ? "Connected" : "Available"
    }

    private var statusTextColor: Color {
        device.connectionStatus == .connected ? MeasurementSourcePalette.connected : Color.secondary
    }

    private var statusDotTint: Color {
        device.connectionStatus == .connected ? MeasurementSourcePalette.connected : MeasurementSourcePalette.mutedDot
    }

    private var accessibilityValue: String {
        if isSelected { return "Selected" }
        return isEnabled ? "Not selected" : "Unavailable"
    }

    private var accessibilityHint: String {
        if isSelected { return "Current measurement source" }
        return isEnabled ? "Double tap to select" : "Cannot be used as the preferred source"
    }
}

private extension MeasurementDeviceType {
    var heroSymbolName: String {
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
    var heroSymbolName: String {
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

private struct MeasurementSelectionConfirmationBanner: View {
    let message: String

    var body: some View {
        Label {
            Text(message)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(MeasurementSourcePalette.connected)
        }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.10), radius: 18, y: 10)
            .accessibilityAddTraits(.isStaticText)
    }
}

private struct MeasurementSourceBackground: View {
    var body: some View {
        ZStack {
            Color.white

            RadialGradient(
                colors: [
                    Color.black.opacity(0.025),
                    .clear
                ],
                center: UnitPoint(x: 0.12, y: 0.10),
                startRadius: 0,
                endRadius: 420
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
