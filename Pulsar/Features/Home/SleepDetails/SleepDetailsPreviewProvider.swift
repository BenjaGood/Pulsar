import Foundation

struct SleepDetailsPreviewProvider: SleepSummaryProviding {
    var summary: SleepSummary

    func sleepSummary(
        profile: UserProfile,
        wakeUpDate: Date,
        calendar: Calendar,
        refreshedAt: Date
    ) async throws -> SleepSummary {
        var copy = summary
        copy.lastUpdated = refreshedAt
        return copy
    }
}
