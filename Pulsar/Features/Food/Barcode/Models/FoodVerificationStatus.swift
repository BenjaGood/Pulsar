import Foundation

nonisolated enum FoodVerificationStatus: String, Codable, CaseIterable, Sendable {
    case imported
    case communitySubmitted = "community_submitted"
    case photoVerified = "photo_verified"
    case communityVerified = "community_verified"
    case needsReview = "needs_review"
    case outdated

    var title: String {
        switch self {
        case .imported: "Imported"
        case .communitySubmitted: "Community submitted"
        case .photoVerified: "Photo verified"
        case .communityVerified: "Community verified"
        case .needsReview: "Needs review"
        case .outdated: "Outdated"
        }
    }

    var isTrusted: Bool {
        self == .photoVerified || self == .communityVerified
    }
}
