import Foundation

struct StrainDetailsPreviewProvider: StrainSummaryProviding {
    var summary: StrainSummary

    func strainSummary(
        profile: UserProfile,
        date: Date,
        calendar: Calendar,
        refreshedAt: Date
    ) async throws -> StrainSummary {
        var copy = summary
        copy.lastUpdated = refreshedAt
        return copy
    }
}
