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
            case .amazfitHelioRing:
                ringIcon
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
    var onDismiss: () -> Void

    @State private var focusedDeviceType: MeasurementDeviceType?
    @Environment(\.colorScheme) private var colorScheme

    private var focusedDevice: MeasurementDevice {
        manager.device(for: focusedDeviceType ?? manager.activeDevice.type)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                header

                MeasurementActiveDeviceHero(device: manager.activeDevice)
                    .id(manager.activeDevice.type)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))

                changeSourceSection

                MeasurementDeviceDetailPanel(device: focusedDevice) {
                    handlePrimaryAction(for: focusedDevice)
                }

                footerNote
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 42)
        }
        .background(MeasurementSourceBackground())
        .presentationDragIndicator(.visible)
        .animation(.spring(response: 0.48, dampingFraction: 0.88), value: manager.activeDeviceType)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: focusedDeviceType)
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
            VStack(alignment: .leading, spacing: 7) {
                Text("Measurement Source")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(primaryText)
                Text("Choose which device powers your health metrics.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(secondaryText)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(cardBorder, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    private var changeSourceSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Change source")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(primaryText)

                Spacer()

                Text("\(manager.availableDevices.count) devices")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(colorScheme == .dark ? 0.07 : 0.58), in: Capsule(style: .continuous))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(cardBorder, lineWidth: 1)
                    }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 13) {
                    ForEach(manager.availableDevices) { device in
                        MeasurementDeviceSourceCard(
                            device: device,
                            isFocused: focusedDevice.type == device.type
                        ) {
                            focusedDeviceType = device.type
                        } onAction: {
                            handlePrimaryAction(for: device)
                        }
                        .frame(width: 268, height: 382, alignment: .top)
                    }
                }
                .padding(.horizontal, 1)
                .padding(.vertical, 2)
            }
        }
    }

    private var footerNote: some View {
        Text("Pulsar uses your selected source to prioritize sleep, recovery, strain, stress, and workout metrics when multiple devices are available.")
            .font(.caption.weight(.medium))
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

    private func handlePrimaryAction(for device: MeasurementDevice) {
        focusedDeviceType = device.type

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

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.96) : Color(red: 0.07, green: 0.10, blue: 0.15)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.66) : Color(red: 0.34, green: 0.38, blue: 0.46)
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

private struct MeasurementActiveDeviceHero: View {
    let device: MeasurementDevice
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ZStack {
                activeAura
                DeviceProductImageView(
                    assetName: device.type.assetName,
                    deviceType: device.type,
                    mode: .hero
                )
                    .frame(height: 260)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 272)

            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(device.name)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(primaryText)
                        HStack(spacing: 8) {
                            DeviceStatusPill(text: device.connectionStatus.label, tint: statusTint)
                            DeviceStatusPill(text: "Active source", tint: tint)
                        }
                    }

                    Spacer(minLength: 8)

                    MeasurementDeviceIconView(type: device.type, size: 26, tint: tint)
                        .frame(width: 42, height: 42)
                        .background(tint.opacity(colorScheme == .dark ? 0.14 : 0.10), in: Circle())
                        .overlay {
                            Circle()
                                .stroke(tint.opacity(colorScheme == .dark ? 0.22 : 0.16), lineWidth: 1)
                        }
                }

                HStack(spacing: 11) {
                    PremiumBatteryStatusView(percentage: device.batteryPercentage, style: .hero, tint: tint)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Last sync")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(secondaryText)
                        Text(lastSyncText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.80)
                    }
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(insetBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(cardBorder, lineWidth: 1)
                    }
                }

                MetricPreviewStrip(metrics: Array(device.supportedMetrics.prefix(5)), tint: tint)
            }
        }
        .padding(18)
        .background(heroBackground, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(heroBorder, lineWidth: 1)
        }
        .shadow(color: tint.opacity(colorScheme == .dark ? 0.18 : 0.10), radius: 28, y: 18)
        .accessibilityElement(children: .contain)
    }

    private var activeAura: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(colorScheme == .dark ? 0.18 : 0.10))
                .frame(width: 250, height: 250)
                .blur(radius: 34)
                .offset(x: 50, y: -8)
            Circle()
                .fill(Color(red: 0.42, green: 0.72, blue: 1.0).opacity(colorScheme == .dark ? 0.12 : 0.07))
                .frame(width: 170, height: 170)
                .blur(radius: 26)
                .offset(x: -70, y: 30)
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
        case .amazfitHelioRing:
            return colorScheme == .dark ? Color(red: 0.34, green: 0.92, blue: 0.80) : Color(red: 0.00, green: 0.48, blue: 0.42)
        }
    }

    private var statusTint: Color {
        switch device.connectionStatus {
        case .connected:
            return colorScheme == .dark ? Color(red: 0.36, green: 0.94, blue: 0.68) : Color(red: 0.00, green: 0.47, blue: 0.30)
        case .available:
            return tint
        case .setupRequired:
            return colorScheme == .dark ? Color(red: 1.0, green: 0.70, blue: 0.38) : Color(red: 0.76, green: 0.34, blue: 0.08)
        case .disconnected:
            return secondaryText
        }
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.97) : Color(red: 0.07, green: 0.10, blue: 0.15)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.64) : Color(red: 0.35, green: 0.39, blue: 0.47)
    }

    private var heroBackground: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color.white.opacity(0.13),
                    Color(red: 0.07, green: 0.09, blue: 0.14).opacity(0.92),
                    tint.opacity(0.10)
                ]
                : [
                    Color.white.opacity(0.94),
                    Color(red: 0.93, green: 0.97, blue: 1.0).opacity(0.82),
                    tint.opacity(0.08)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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

    private var heroBorder: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [.white.opacity(0.24), tint.opacity(0.20), .white.opacity(0.08)]
                : [.white.opacity(0.92), tint.opacity(0.18), Color(red: 0.44, green: 0.56, blue: 0.70).opacity(0.20)],
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

private struct MeasurementDeviceSourceCard: View {
    let device: MeasurementDevice
    let isFocused: Bool
    let onFocus: () -> Void
    let onAction: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DeviceProductImageView(
                assetName: device.type.assetName,
                deviceType: device.type,
                mode: .card
            )
                .frame(height: 160)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(device.name)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(primaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.86)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(device.connectionStatus.label)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(statusTint)
                    }

                    Spacer(minLength: 0)

                    if device.isActiveSource {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                }

                PremiumBatteryStatusView(percentage: device.batteryPercentage, style: .compact, tint: tint)

                Text(metricSummary)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if device.type == .amazfitHelioRing {
                    Text("Integration is not connected yet.")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(statusTint)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Button(action: onAction) {
                Text(device.primaryActionTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(buttonText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(buttonBackground, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(buttonBorder, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .disabled(device.isActiveSource)
        }
        .padding(14)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(isFocused ? tint.opacity(colorScheme == .dark ? 0.42 : 0.28) : cardBorder, lineWidth: isFocused ? 1.4 : 1)
        }
        .shadow(color: tint.opacity(isFocused ? (colorScheme == .dark ? 0.16 : 0.08) : 0.04), radius: isFocused ? 22 : 12, y: isFocused ? 14 : 8)
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onTapGesture(perform: onFocus)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isFocused ? .isSelected : [])
    }

    private var metricSummary: String {
        device.supportedMetrics.prefix(4).map(\.label).joined(separator: " • ")
    }

    private var tint: Color {
        switch device.type {
        case .appleWatch:
            return colorScheme == .dark ? Color(red: 0.72, green: 0.86, blue: 1.0) : Color(red: 0.08, green: 0.34, blue: 0.58)
        case .amazfitHelioRing:
            return colorScheme == .dark ? Color(red: 0.34, green: 0.92, blue: 0.80) : Color(red: 0.00, green: 0.48, blue: 0.42)
        }
    }

    private var statusTint: Color {
        switch device.connectionStatus {
        case .connected:
            return colorScheme == .dark ? Color(red: 0.36, green: 0.94, blue: 0.68) : Color(red: 0.00, green: 0.47, blue: 0.30)
        case .available:
            return tint
        case .setupRequired:
            return colorScheme == .dark ? Color(red: 1.0, green: 0.70, blue: 0.38) : Color(red: 0.76, green: 0.34, blue: 0.08)
        case .disconnected:
            return secondaryText
        }
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
                ? [.white.opacity(isFocused ? 0.13 : 0.10), Color(red: 0.05, green: 0.07, blue: 0.11).opacity(0.90)]
                : [.white.opacity(0.92), Color(red: 0.93, green: 0.97, blue: 1.0).opacity(isFocused ? 0.78 : 0.66)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
            colors: colorScheme == .dark ? [tint.opacity(0.24), tint.opacity(0.11)] : [tint.opacity(0.18), Color.white.opacity(0.58)],
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

private struct MeasurementDeviceDetailPanel: View {
    let device: MeasurementDevice
    let onAction: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Device details")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(primaryText)
                    Text(detailSubtitle)
                        .font(.subheadline.weight(.medium))
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
                        .font(.title3.weight(.bold))
                        .foregroundStyle(primaryText)
                        .lineLimit(2)

                    PremiumBatteryStatusView(percentage: device.batteryPercentage, style: .compact, tint: tint)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Last sync")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(secondaryText)
                        Text(lastSyncText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(primaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 94), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(device.supportedMetrics) { metric in
                    Text(metric.label)
                        .font(.caption2.weight(.bold))
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
                .font(.caption.weight(.medium))
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
                    .font(.subheadline.weight(.bold))
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
            .disabled(device.isActiveSource)
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
        case .amazfitHelioRing:
            return "Amazfit Helio Ring integration is not connected yet."
        }
    }

    private var explanation: String {
        switch device.type {
        case .appleWatch:
            return "Apple Watch data is prioritized for sleep, recovery, strain, stress, and workout metrics when it is the active source."
        case .amazfitHelioRing:
            return "Amazfit Helio Ring integration is not connected yet. Set up support before using it as a measurement source."
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
        case .amazfitHelioRing:
            return colorScheme == .dark ? Color(red: 0.34, green: 0.92, blue: 0.80) : Color(red: 0.00, green: 0.48, blue: 0.42)
        }
    }

    private var statusTint: Color {
        switch device.connectionStatus {
        case .connected:
            return colorScheme == .dark ? Color(red: 0.36, green: 0.94, blue: 0.68) : Color(red: 0.00, green: 0.47, blue: 0.30)
        case .available:
            return tint
        case .setupRequired:
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

    private func chargedView(percentage: Int) -> some View {
        HStack(spacing: style == .hero ? 11 : 8) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(colorScheme == .dark ? 0.16 : 0.12), lineWidth: style == .hero ? 6 : 4)
                Circle()
                    .trim(from: 0, to: animatedLevel)
                    .stroke(
                        batteryTint,
                        style: StrokeStyle(lineWidth: style == .hero ? 6 : 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: batteryTint.opacity(colorScheme == .dark ? 0.34 : 0.16), radius: 8)
                Image(systemName: "bolt.fill")
                    .font(.system(size: style == .hero ? 10 : 7, weight: .bold))
                    .foregroundStyle(batteryTint)
                    .opacity(0.0)
            }
            .frame(width: style == .hero ? 42 : 26, height: style == .hero ? 42 : 26)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(percentage)%")
                    .font(style == .hero ? .subheadline.weight(.bold) : .caption.weight(.bold))
                    .foregroundStyle(primaryText)
                Text("Battery")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(secondaryText)
            }
        }
        .padding(style == .hero ? 13 : 0)
        .frame(maxWidth: style == .hero ? .infinity : nil, alignment: .leading)
        .background {
            if style == .hero {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(insetBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(cardBorder, lineWidth: 1)
                    }
            }
        }
    }

    private var unavailableView: some View {
        HStack(spacing: style == .hero ? 11 : 8) {
            ZStack {
                Circle()
                    .fill(colorScheme == .dark ? .white.opacity(0.065) : Color.white.opacity(0.58))
                Image(systemName: "battery.0")
                    .font(.system(size: style == .hero ? 15 : 11, weight: .semibold))
                    .foregroundStyle(secondaryText)
            }
            .frame(width: style == .hero ? 42 : 26, height: style == .hero ? 42 : 26)

            VStack(alignment: .leading, spacing: 2) {
                Text("Battery unavailable")
                    .font(style == .hero ? .subheadline.weight(.bold) : .caption.weight(.bold))
                    .foregroundStyle(primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                if style == .hero {
                    Text("No real device battery data")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
        }
        .padding(style == .hero ? 13 : 0)
        .frame(maxWidth: style == .hero ? .infinity : nil, alignment: .leading)
        .background {
            if style == .hero {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(insetBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(cardBorder, lineWidth: 1)
                    }
            }
        }
    }

    private var batteryTint: Color {
        guard let percentage else { return secondaryText }
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
                        color: Color.black.opacity(colorScheme == .dark ? 0.36 : 0.16),
                        radius: mode == .hero ? 18 : 10,
                        y: mode == .hero ? 16 : 8
                    )
                    .shadow(
                        color: tint.opacity(colorScheme == .dark ? 0.28 : 0.13),
                        radius: mode == .hero ? 28 : 16,
                        y: mode == .hero ? 18 : 10
                    )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .opacity(hasAppeared ? 1 : 0)
            .scaleEffect(hasAppeared ? 1 : 0.965)
        }
        .onAppear {
            guard !hasAppeared else { return }
            withAnimation(.spring(response: 0.52, dampingFraction: 0.86)) {
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
        case .amazfitHelioRing:
            HelioRingDeviceIllustrationView(tint: tint)
        }
    }

    private func productGlow(in size: CGSize) -> some View {
        ZStack {
            Ellipse()
                .fill(tint.opacity(colorScheme == .dark ? 0.20 : 0.11))
                .frame(width: size.width * glowWidthMultiplier, height: size.height * 0.24)
                .blur(radius: mode == .hero ? 24 : 16)
                .offset(y: size.height * 0.34)

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            tint.opacity(colorScheme == .dark ? 0.15 : 0.08),
                            tint.opacity(colorScheme == .dark ? 0.07 : 0.035),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size.height * 0.48
                    )
                )
                .frame(width: size.height * 0.98, height: size.height * 0.82)
                .blur(radius: mode == .hero ? 18 : 12)
        }
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
        case (.amazfitHelioRing, .hero):
            return 0.92
        case (.amazfitHelioRing, .card):
            return 0.92
        case (.amazfitHelioRing, .detail):
            return 0.93
        }
    }

    private var glowWidthMultiplier: CGFloat {
        switch mode {
        case .hero:
            return deviceType == .appleWatch ? 0.72 : 0.62
        case .card:
            return deviceType == .appleWatch ? 0.70 : 0.60
        case .detail:
            return deviceType == .appleWatch ? 0.76 : 0.64
        }
    }

    private var imageVerticalOffset: CGFloat {
        switch (deviceType, mode) {
        case (.appleWatch, .hero):
            return -4
        case (.amazfitHelioRing, .hero):
            return 2
        default:
            return 0
        }
    }

    private var tint: Color {
        switch deviceType {
        case .appleWatch:
            return colorScheme == .dark ? Color(red: 0.72, green: 0.86, blue: 1.0) : Color(red: 0.08, green: 0.34, blue: 0.58)
        case .amazfitHelioRing:
            return colorScheme == .dark ? Color(red: 0.34, green: 0.92, blue: 0.80) : Color(red: 0.00, green: 0.48, blue: 0.42)
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

private struct HelioRingDeviceIllustrationView: View {
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(metrics) { metric in
                    Text(metric.label)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.74) : Color(red: 0.24, green: 0.30, blue: 0.38))
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(.white.opacity(colorScheme == .dark ? 0.07 : 0.62), in: Capsule(style: .continuous))
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(tint.opacity(colorScheme == .dark ? 0.15 : 0.10), lineWidth: 1)
                        }
                }
            }
        }
    }
}

private struct DeviceStatusPill: View {
    let text: String
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
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

private struct MeasurementSourceBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            PulsarSectionBackground()
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0.05, green: 0.07, blue: 0.10).opacity(0.97),
                        Color(red: 0.08, green: 0.12, blue: 0.18).opacity(0.88),
                        Color(red: 0.02, green: 0.16, blue: 0.15).opacity(0.38)
                    ]
                    : [
                        Color.white.opacity(0.99),
                        Color(red: 0.92, green: 0.97, blue: 1.0).opacity(0.92),
                        Color(red: 0.84, green: 0.96, blue: 0.93).opacity(0.54)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
}

#Preview("Measurement Source") {
    MeasurementSourceSheet(manager: MeasurementSourceManager(), onDismiss: {})
}
