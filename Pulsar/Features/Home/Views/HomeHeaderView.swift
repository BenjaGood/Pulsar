//
//  HomeHeaderView.swift
//  Pulsar
//

import SwiftUI

struct HomeHeaderView: View {
    var profile: UserProfile
    var date: Date = .now
    var onTodayTapped: () -> Void
    var onProfileTapped: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Button(action: onTodayTapped) {
                HStack(spacing: 7) {
                    Text(title)
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.down")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open calendar")

            Spacer(minLength: 12)

            Button(action: onProfileTapped) {
                AvatarView(profile: profile, size: 44)
                    .padding(5)
                    .pulsarLiquidGlass(cornerRadius: 28)
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .accessibilityLabel("Open Profile")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
    }

    private var title: String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

#Preview("Home Header") {
    HomeHeaderView(profile: MockHealthData.profile) { } onProfileTapped: { }
        .padding()
        .background(PulsarSectionBackground())
}
