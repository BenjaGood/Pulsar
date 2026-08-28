//
//  HomeHeaderView.swift
//  Pulsar
//

import SwiftUI

enum HomeDateLabel {
    static func title(for date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

struct HomeHeaderView: View {
    var profile: UserProfile
    var activeDevice: MeasurementDevice
    var date: Date = .now
    var canGoPrevious: Bool = true
    var canGoNext: Bool = false
    var onPreviousDay: () -> Void = {}
    var onNextDay: () -> Void = {}
    var onTodayTapped: () -> Void
    var onProfileTapped: () -> Void
    var onDeviceTapped: () -> Void

    var body: some View {
        HomeFloatingHeader(
            profile: profile,
            activeDevice: activeDevice,
            date: date,
            canGoPrevious: canGoPrevious,
            canGoNext: canGoNext,
            onPreviousDay: onPreviousDay,
            onNextDay: onNextDay,
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
    var canGoPrevious: Bool
    var canGoNext: Bool
    var onPreviousDay: () -> Void
    var onNextDay: () -> Void
    var onDateTapped: () -> Void
    var onProfileTapped: () -> Void
    var onDeviceTapped: () -> Void

    var body: some View {
        VStack(spacing: HomePremiumDesign.Layout.identityToDateSpacing) {
            HomeIdentityHeaderRow(
                profile: profile,
                onProfileTapped: onProfileTapped,
                onDeviceTapped: onDeviceTapped
            )

            HomeCenteredDateNavigator(
                date: date,
                canGoPrevious: canGoPrevious,
                canGoNext: canGoNext,
                onPreviousDay: onPreviousDay,
                onNextDay: onNextDay,
                onDateTapped: onDateTapped
            )
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.top, 2)
        .padding(.bottom, HomePremiumDesign.Layout.dateNavigatorBottomInset)
    }
}

private struct HomeIdentityHeaderRow: View {
    var profile: UserProfile
    var onProfileTapped: () -> Void
    var onDeviceTapped: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            identityText
                .padding(.horizontal, HomePremiumDesign.Layout.identitySideInset)
                .frame(maxWidth: .infinity)

            HStack(spacing: 0) {
                measurementSourceButton
                Spacer(minLength: 0)
                profileButton
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var identityText: some View {
        VStack(spacing: 1) {
            Text(greeting)
                .font(.subheadline.weight(.regular))
                .foregroundStyle(HomePremiumDesign.secondaryText)

            if let displayName {
                Text(displayName)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(HomePremiumDesign.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var measurementSourceButton: some View {
        Button("Measurement source", systemImage: "line.3.horizontal", action: onDeviceTapped)
            .labelStyle(.iconOnly)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(HomePremiumDesign.primaryText)
            .frame(width: 44, height: 44)
            .modifier(HomeHeaderControlEffect(reduceTransparency: reduceTransparency, shape: Circle()))
            .accessibilityHint("Choose which device powers your health metrics")
    }

    private var profileButton: some View {
        Button(action: onProfileTapped) {
            AvatarView(profile: profile, size: 38)
                .padding(3)
                .modifier(HomeHeaderControlEffect(reduceTransparency: reduceTransparency, shape: Circle()))
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel("Open profile")
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12:
            return "Good morning,"
        case 12..<18:
            return "Good afternoon,"
        default:
            return "Good evening,"
        }
    }

    private var displayName: String? {
        profile.name.split(separator: " ").first.map(String.init)
    }
}

private struct HomeCenteredDateNavigator: View {
    var date: Date
    var canGoPrevious: Bool
    var canGoNext: Bool
    var onPreviousDay: () -> Void
    var onNextDay: () -> Void
    var onDateTapped: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var labelOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            HomeDateNavigatorChevron(
                title: "Previous day",
                systemImage: "chevron.left",
                isEnabled: canGoPrevious,
                action: onPreviousDay
            )

            centerDateButton
                .frame(maxWidth: .infinity)

            HomeDateNavigatorChevron(
                title: "Next day",
                systemImage: "chevron.right",
                isEnabled: canGoNext,
                action: onNextDay
            )
        }
        .frame(minWidth: HomePremiumDesign.Layout.dateNavigatorMinWidth)
        .frame(maxWidth: HomePremiumDesign.Layout.dateNavigatorMaxWidth)
        .modifier(HomeHeaderControlEffect(reduceTransparency: reduceTransparency, shape: Capsule(), shadowRadius: 10, shadowY: 5))
        .frame(maxWidth: .infinity)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .animation(dateAnimation, value: title)
        .sensoryFeedback(.selection, trigger: date)
        .onChange(of: date) { oldValue, newValue in
            shiftDateLabel(from: oldValue, to: newValue)
        }
        .accessibilityElement(children: .contain)
    }

    private var centerDateButton: some View {
        Button(action: onDateTapped) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(HomePremiumDesign.primaryText)

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(HomePremiumDesign.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .contentTransition(.opacity)
                    .offset(x: reduceMotion ? 0 : labelOffset)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.white.opacity(reduceTransparency ? 0.92 : 0.62), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(HomePremiumDesign.border, lineWidth: 0.6)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open calendar, \(title)")
    }

    private var title: String {
        HomeDateLabel.title(for: date)
    }

    private var dateAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.16)
            : .smooth(duration: 0.22)
    }

    private func shiftDateLabel(from oldValue: Date, to newValue: Date) {
        guard !reduceMotion else {
            labelOffset = 0
            return
        }

        let direction: CGFloat = newValue > oldValue ? 1 : -1
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            labelOffset = direction * 3
        }
        withAnimation(dateAnimation) {
            labelOffset = 0
        }
    }
}

private struct HomeDateNavigatorChevron: View {
    var title: String
    var systemImage: String
    var isEnabled: Bool
    var action: () -> Void

    var body: some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(HomePremiumDesign.primaryText)
            .frame(
                width: HomePremiumDesign.Layout.dateNavigatorChevronWidth,
                height: HomePremiumDesign.Layout.dateNavigatorChevronWidth
            )
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.32)
    }
}

private struct HomeHeaderControlEffect<ChromeShape: Shape>: ViewModifier {
    var reduceTransparency: Bool
    var shape: ChromeShape
    var shadowRadius: CGFloat = 12
    var shadowY: CGFloat = 6

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content
                .background(Color.white.opacity(0.54), in: shape)
                .overlay { shape.stroke(HomePremiumDesign.border, lineWidth: 0.75) }
                .glassEffect(.regular.tint(Color.white.opacity(0.12)).interactive(), in: shape)
                .shadow(color: HomePremiumDesign.shadow, radius: shadowRadius, y: shadowY)
        } else {
            content
                .background(
                    reduceTransparency ? Color(.systemBackground) : Color.white.opacity(0.88),
                    in: shape
                )
                .overlay { shape.stroke(HomePremiumDesign.border, lineWidth: 0.8) }
                .shadow(color: HomePremiumDesign.shadow, radius: shadowRadius, y: shadowY)
        }
    }
}

#Preview("Home Header") {
    HomeHeaderView(
        profile: MockHealthData.profile,
        activeDevice: MeasurementSourceManager().activeDevice,
        canGoPrevious: true,
        canGoNext: false,
        onTodayTapped: {},
        onProfileTapped: {},
        onDeviceTapped: {}
    )
    .padding()
    .background(HomePremiumDesign.background)
    .environment(\.homeAdaptiveAppearance, .premium)
}

#Preview("Home Header Yesterday") {
    HomeHeaderView(
        profile: MockHealthData.profile,
        activeDevice: MeasurementSourceManager().activeDevice,
        date: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now,
        canGoPrevious: true,
        canGoNext: true,
        onTodayTapped: {},
        onProfileTapped: {},
        onDeviceTapped: {}
    )
    .padding()
    .background(HomePremiumDesign.background)
    .environment(\.homeAdaptiveAppearance, .premium)
}

#Preview("Home Header Weekday") {
    HomeHeaderView(
        profile: MockHealthData.profile,
        activeDevice: MeasurementSourceManager().activeDevice,
        date: Calendar.current.date(byAdding: .day, value: -3, to: .now) ?? .now,
        canGoPrevious: true,
        canGoNext: true,
        onTodayTapped: {},
        onProfileTapped: {},
        onDeviceTapped: {}
    )
    .padding()
    .background(HomePremiumDesign.background)
    .environment(\.homeAdaptiveAppearance, .premium)
}
