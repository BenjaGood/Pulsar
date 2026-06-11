//
//  HomeHeaderView.swift
//  Pulsar
//

import SwiftUI

struct HomeHeaderView: View {
    var profile: UserProfile
    var activeDevice: MeasurementDevice
    var date: Date = .now
    var onTodayTapped: () -> Void
    var onProfileTapped: () -> Void
    var onDeviceTapped: () -> Void

    var body: some View {
        HomeFloatingHeader(
            profile: profile,
            activeDevice: activeDevice,
            date: date,
            onDateTapped: onTodayTapped,
            onProfileTapped: onProfileTapped,
            onDeviceTapped: onDeviceTapped
        )
    }
}

struct HomeFloatingHeader: View {
    var profile: UserProfile
    var activeDevice: MeasurementDevice
    var date: Date = .now
    var onDateTapped: () -> Void
    var onProfileTapped: () -> Void
    var onDeviceTapped: () -> Void

    @Environment(\.homeAdaptiveAppearance) private var appearance

    var body: some View {
        ZStack {
            HStack {
                headerActionButton(
                    accessibilityLabel: "Measurement Source",
                    accessibilityHint: "Choose which device powers your health metrics",
                    action: onDeviceTapped
                ) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(primaryText)
                }

                Spacer(minLength: 0)

                Button(action: onProfileTapped) {
                    AvatarView(profile: profile, size: 30)
                        .padding(7)
                        .background(headerCircleFill)
                        .overlay {
                            Circle()
                                .stroke(appearance.headerBorderColor, lineWidth: 0.55)
                        }
                        .modifier(HeaderGlassCircleEffect(tint: .white, nativeTintOpacity: appearance.nativeGlassTintOpacity))
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .accessibilityLabel("Open Profile")
            }

            Button(action: onDateTapped) {
                HStack(spacing: 7) {
                    Text(title)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(secondaryText)
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(appearance.usesLightText ? 0.045 : 0.135), in: Circle())
                        .overlay {
                            Circle()
                                .stroke(appearance.headerBorderColor.opacity(0.72), lineWidth: 0.5)
                        }
                }
                .padding(.horizontal, 4)
                .frame(minHeight: 44)
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open calendar")
        }
        .frame(height: 50)
        .frame(maxWidth: .infinity)
    }

    private var title: String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private var primaryText: Color {
        appearance.primaryText
    }

    private var secondaryText: Color {
        appearance.secondaryText
    }

    private var headerCircleFill: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: appearance.headerFillColors(),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private func headerActionButton<Icon: View>(
        accessibilityLabel: String,
        accessibilityHint: String,
        action: @escaping () -> Void,
        @ViewBuilder icon: @escaping () -> Icon
    ) -> some View {
        Button(action: action) {
            icon()
                .frame(width: 44, height: 44)
                .background(headerCircleFill)
                .overlay {
                    Circle()
                        .stroke(appearance.headerBorderColor, lineWidth: 0.55)
                }
                .shadow(color: .black.opacity(appearance.headerShadowOpacity), radius: 9, y: 5)
                .modifier(HeaderGlassCircleEffect(tint: .white, nativeTintOpacity: appearance.nativeGlassTintOpacity))
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }
}

private struct HeaderGlassCircleEffect: ViewModifier {
    var tint: Color
    var nativeTintOpacity: Double

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(tint.opacity(nativeTintOpacity * 0.82)).interactive(), in: Circle())
        } else {
            content.background(.ultraThinMaterial, in: Circle())
        }
    }
}

#Preview("Home Header") {
    HomeHeaderView(
        profile: MockHealthData.profile,
        activeDevice: MeasurementSourceManager().activeDevice,
        onTodayTapped: {},
        onProfileTapped: {},
        onDeviceTapped: {}
    )
        .padding()
        .background(PulsarSectionBackground())
}
