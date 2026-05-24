//
//  DailyRewindModels.swift
//  Pulsar
//

import Foundation
import SwiftUI

enum DailyRewindDataState: String, Equatable {
    case ready
    case placeholder
}

enum DailyRewindAvailability: String, Equatable {
    case ready
    case partial
    case noData
}

enum DailyRewindTint: String, Equatable {
    case blue
    case teal
    case green
    case orange
    case pink
    case purple
    case indigo
    case gray

    var color: Color {
        switch self {
        case .blue: Color(red: 0.34, green: 0.72, blue: 1.00)
        case .teal: Color(red: 0.36, green: 0.80, blue: 0.76)
        case .green: Color(red: 0.52, green: 0.82, blue: 0.62)
        case .orange: Color(red: 1.00, green: 0.68, blue: 0.38)
        case .pink: Color(red: 1.00, green: 0.52, blue: 0.66)
        case .purple: Color(red: 0.72, green: 0.62, blue: 1.00)
        case .indigo: Color(red: 0.55, green: 0.62, blue: 0.98)
        case .gray: Color.secondary
        }
    }
}

enum DailyRewindCardKind: String, CaseIterable, Identifiable, Equatable {
    case movement
    case recovery
    case mindfulness
    case stress
    case energy
    case reflection

    var id: String { rawValue }
}

struct DailyRewindHighlight: Identifiable, Equatable {
    var id: String
    var title: String
    var value: String
    var caption: String
    var symbolName: String
    var tint: DailyRewindTint
    var state: DailyRewindDataState
}

struct DailyRewindCard: Identifiable, Equatable {
    var id: DailyRewindCardKind { kind }
    var kind: DailyRewindCardKind
    var title: String
    var value: String
    var subtitle: String
    var symbolName: String
    var tint: DailyRewindTint
    var state: DailyRewindDataState
}

struct DailyRewindInsight: Equatable {
    var title: String
    var body: String
    var evidence: String
    var symbolName: String
    var tint: DailyRewindTint
}

struct PulsarDailyRewind: Identifiable, Equatable {
    var id: String { dateKey }
    var date: Date
    var dateKey: String
    var availability: DailyRewindAvailability
    var headline: String
    var subtitle: String
    var highlights: [DailyRewindHighlight]
    var cards: [DailyRewindCard]
    var insight: DailyRewindInsight
    var generatedAt: Date
}

enum DailyRewindDateKey {
    static func string(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func date(from key: String?, calendar: Calendar = .current) -> Date? {
        guard let key else { return nil }
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return calendar.date(from: components)
    }
}
