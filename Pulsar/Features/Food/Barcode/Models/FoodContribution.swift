import Foundation

nonisolated enum FoodContributionType: String, Codable, CaseIterable, Sendable {
    case newProduct = "new_product"
    case nutritionUpdate = "nutrition_update"
    case productUpdate = "product_update"
    case labelChanged = "label_changed"
}

nonisolated enum FoodContributionStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case approved
    case rejected
    case needsReview = "needs_review"
}

nonisolated struct FoodContribution: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var productID: UUID?
    var barcode: String
    var submittedBy: UUID?
    var contributionType: FoodContributionType
    var proposedProduct: FoodProduct
    var frontImagePath: String?
    var nutritionImagePath: String?
    var ingredientsImagePath: String?
    var status: FoodContributionStatus
    var createdAt: Date?
}
