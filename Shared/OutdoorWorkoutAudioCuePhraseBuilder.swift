//
//  OutdoorWorkoutAudioCuePhraseBuilder.swift
//  Pulsar
//

import Foundation

/// Builds localized spoken phrases for outdoor distance milestones.
enum OutdoorWorkoutAudioCuePhraseBuilder {
    /// Example: "Kilometer 1. Pace: 3 minutes 42 seconds per kilometer."
    static func kilometerSplitPhrase(
        kilometer: Int,
        paceSecondsPerKilometer: Double?,
        locale: Locale = .autoupdatingCurrent
    ) -> String? {
        guard kilometer > 0 else { return nil }
        guard let paceSecondsPerKilometer,
              let paceText = paceDescription(secondsPerKilometer: paceSecondsPerKilometer, locale: locale) else {
            return nil
        }

        let kilometerText = String(localized: "Kilometer \(kilometer)", locale: locale)
        return String(
            localized: "\(kilometerText). Pace: \(paceText).",
            locale: locale
        )
    }

    static func paceDescription(
        secondsPerKilometer: Double,
        locale: Locale = .autoupdatingCurrent
    ) -> String? {
        guard secondsPerKilometer.isFinite, secondsPerKilometer > 0 else { return nil }

        let totalSeconds = Int(secondsPerKilometer.rounded())
        if totalSeconds <= 0 { return nil }

        var minutes = totalSeconds / 60
        var seconds = totalSeconds % 60
        if seconds == 60 {
            minutes += 1
            seconds = 0
        }

        let minutesText = minutes == 1
            ? String(localized: "1 minute", locale: locale)
            : String(localized: "\(minutes) minutes", locale: locale)
        let secondsText = seconds == 1
            ? String(localized: "1 second", locale: locale)
            : String(localized: "\(seconds) seconds", locale: locale)

        return String(
            localized: "\(minutesText) \(secondsText) per kilometer",
            locale: locale
        )
    }
}
