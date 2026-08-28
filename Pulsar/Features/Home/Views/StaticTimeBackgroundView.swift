//
//  StaticTimeBackgroundView.swift
//  Pulsar
//

import Combine
import SwiftUI

enum HomeBackgroundMode: String, CaseIterable, Identifiable, Codable {
    case automatic
    case morning
    case day
    case sunset
    case night
    case minimalDark

    static var allCases: [HomeBackgroundMode] {
        [.automatic, .day, .night]
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Dynamic"
        case .morning, .day: "Light"
        case .sunset, .night, .minimalDark: "Dark"
        }
    }

    var shortTitle: String {
        title
    }

    fileprivate var manualStyle: HomeBackgroundStyle? {
        switch self {
        case .automatic: nil
        case .morning: .sunrise
        case .day: .day
        case .sunset: .sunset
        case .night, .minimalDark: .night
        }
    }

    func resolvedStyle(for date: Date = .now, calendar: Calendar = .current) -> HomeBackgroundStyle {
        manualStyle ?? .timeOfDay(for: date, calendar: calendar)
    }
}

final class HomeBackgroundSettingsStore: ObservableObject {
    @Published private(set) var mode: HomeBackgroundMode

    private let defaults: UserDefaults
    private let storageKey = "pulsar.home.background.mode.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let rawValue = defaults.string(forKey: storageKey),
           let mode = HomeBackgroundMode(rawValue: rawValue) {
            let normalizedMode = Self.normalizedAppearanceMode(mode)
            self.mode = normalizedMode
            if normalizedMode != mode {
                defaults.set(normalizedMode.rawValue, forKey: storageKey)
            }
        } else if let migratedMode = Self.migratedMode(from: defaults.string(forKey: storageKey)) {
            let normalizedMode = Self.normalizedAppearanceMode(migratedMode)
            self.mode = normalizedMode
            defaults.set(normalizedMode.rawValue, forKey: storageKey)
        } else {
            self.mode = .automatic
        }
    }

    func setMode(_ mode: HomeBackgroundMode) {
        self.mode = Self.normalizedAppearanceMode(mode)
        defaults.set(self.mode.rawValue, forKey: storageKey)
    }

    private static func normalizedAppearanceMode(_ mode: HomeBackgroundMode) -> HomeBackgroundMode {
        switch mode {
        case .automatic:
            .automatic
        case .morning, .day:
            .day
        case .sunset, .night, .minimalDark:
            .night
        }
    }

    private static func migratedMode(from rawValue: String?) -> HomeBackgroundMode? {
        switch rawValue {
        case "sunrise": .morning
        case "daylight": .day
        case "cloudy", "rain", "minimalDark": .night
        default: nil
        }
    }
}

struct StaticTimeBackgroundView: View {
    var mode: HomeBackgroundMode
    var fixedStyle: HomeBackgroundStyle?
    var date: Date = .now
    var calendar: Calendar = .current

    init(mode: HomeBackgroundMode, date: Date = .now, calendar: Calendar = .current) {
        self.mode = mode
        self.fixedStyle = nil
        self.date = date
        self.calendar = calendar
    }

    init(style: HomeBackgroundStyle) {
        self.mode = .automatic
        self.fixedStyle = style
    }

    var body: some View {
        Group {
            if let fixedStyle {
                StaticTimeBackgroundImage(style: fixedStyle)
            } else {
                TimelineView(.periodic(from: date, by: 300)) { timeline in
                    StaticTimeBackgroundImage(style: resolvedStyle(for: timeline.date))
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func resolvedStyle(for date: Date) -> HomeBackgroundStyle {
        mode.resolvedStyle(for: date, calendar: calendar)
    }
}

enum HomeBackgroundStyle {
    case sunrise
    case day
    case sunset
    case night

    static func timeOfDay(for date: Date, calendar: Calendar) -> HomeBackgroundStyle {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<11:
            return .sunrise
        case 11..<18:
            return .day
        case 18..<21:
            return .sunset
        default:
            return .night
        }
    }

    var assetName: String {
        switch self {
        case .sunrise: "HomeBackgroundSunrise"
        case .day: "HomeBackgroundDay"
        case .sunset: "HomeBackgroundSunset"
        case .night: "HomeBackgroundNight"
        }
    }
}

private struct StaticTimeBackgroundImage: View {
    var style: HomeBackgroundStyle

    var body: some View {
        GeometryReader { proxy in
            Image(style.assetName)
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .overlay(readabilityOverlay)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var readabilityOverlay: some View {
        ZStack {
            LinearGradient(
                colors: [
                    .black.opacity(style == .day ? 0.02 : 0.045),
                    .clear,
                    .black.opacity(bottomOverlayOpacity)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    .clear,
                    .black.opacity(radialOverlayOpacity)
                ],
                center: .center,
                startRadius: 180,
                endRadius: 620
            )
        }
        .allowsHitTesting(false)
    }

    private var bottomOverlayOpacity: Double {
        switch style {
        case .day: 0.035
        case .sunrise: 0.055
        case .sunset: 0.060
        case .night: 0.105
        }
    }

    private var radialOverlayOpacity: Double {
        switch style {
        case .day: 0.035
        case .sunrise: 0.055
        case .sunset: 0.065
        case .night: 0.12
        }
    }
}

#Preview("Sunset Wallpaper") {
    StaticTimeBackgroundView(mode: .sunset)
}

#Preview("Automatic Wallpaper") {
    StaticTimeBackgroundView(mode: .automatic)
}
