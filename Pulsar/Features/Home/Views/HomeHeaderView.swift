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

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            HStack {
                headerActionButton(
                    accessibilityLabel: "Measurement Source",
                    accessibilityHint: "Choose which device powers your health metrics",
                    action: onDeviceTapped
                ) {
                    MeasurementDeviceIconView(type: activeDevice.type, size: 23)
                }

                Spacer(minLength: 0)

                Button(action: onProfileTapped) {
                    AvatarView(profile: profile, size: 30)
                        .padding(4)
                        .background(.white.opacity(colorScheme == .dark ? 0.10 : 0.58), in: Circle())
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(colorScheme == .dark ? 0.14 : 0.72), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .accessibilityLabel("Open Profile")
            }
            .padding(.horizontal, 10)

            Button(action: onDateTapped) {
                HStack(spacing: 7) {
                    Text(title)
                        .pulsarTextStyle(.cardTitle)
                        .foregroundStyle(primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(secondaryText)
                        .padding(.top, 2)
                }
                .frame(maxWidth: 196)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open calendar")
        }
        .frame(height: 56)
        .frame(maxWidth: .infinity)
        .background(headerBackground, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(headerBorder, lineWidth: 1)
        }
        .background(alignment: .bottom) {
            LinearGradient(
                colors: [
                    Color(red: 0.58, green: 0.44, blue: 1.0).opacity(colorScheme == .dark ? 0.18 : 0.12),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 58)
            .offset(y: 30)
            .blur(radius: 10)
        }
        .shadow(color: shadowColor, radius: 16, y: 8)
    }

    private var title: String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white : Color(red: 0.10, green: 0.08, blue: 0.16)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.62) : Color(red: 0.28, green: 0.24, blue: 0.36).opacity(0.70)
    }

    private var headerBackground: some ShapeStyle {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    .white.opacity(0.16),
                    Color(red: 0.56, green: 0.46, blue: 1.0).opacity(0.12),
                    .white.opacity(0.08)
                ]
                : [
                    .white.opacity(0.82),
                    Color(red: 0.95, green: 0.93, blue: 1.0).opacity(0.66),
                    .white.opacity(0.52)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var headerBorder: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [.white.opacity(0.26), .white.opacity(0.08)]
                : [.white.opacity(0.90), Color(red: 0.67, green: 0.60, blue: 0.84).opacity(0.24)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var shadowColor: Color {
        colorScheme == .dark ? .black.opacity(0.22) : Color(red: 0.30, green: 0.22, blue: 0.45).opacity(0.12)
    }

    private func headerActionButton<Icon: View>(
        accessibilityLabel: String,
        accessibilityHint: String,
        action: @escaping () -> Void,
        @ViewBuilder icon: @escaping () -> Icon
    ) -> some View {
        Button(action: action) {
            icon()
                .frame(width: 38, height: 38)
                .background(.white.opacity(colorScheme == .dark ? 0.08 : 0.50), in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(colorScheme == .dark ? 0.11 : 0.64), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
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
