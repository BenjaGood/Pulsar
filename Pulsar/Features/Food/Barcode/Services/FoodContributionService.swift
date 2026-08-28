import Foundation

nonisolated protocol FoodContributionServing: Sendable {
    func submit(
        submissionID: UUID,
        product: FoodProduct,
        type: FoodContributionType
    ) async throws -> FoodContribution
}

actor FoodContributionService: FoodContributionServing {
    private let client: SupabaseFoodRESTClient

    init(client: SupabaseFoodRESTClient) {
        self.client = client
    }

    func submit(
        submissionID: UUID = UUID(),
        product: FoodProduct,
        type: FoodContributionType
    ) async throws -> FoodContribution {
        guard let barcode = product.barcode, !barcode.isEmpty else {
            throw FoodCommunityServiceError.invalidResponse
        }
        let auth = try await client.currentSession()
        let sanitized = sanitized(product)
        let initial = ContributionInsert(
            id: submissionID,
            productID: type == .newProduct || product.source == .openNutrition ? nil : product.id,
            barcode: barcode,
            sourceProvider: product.source == .openNutrition ? product.source.rawValue : nil,
            sourceProductID: product.sourceProductID,
            sourceDatasetVersion: product.sourceDatasetVersion,
            submittedBy: auth.userID,
            contributionType: type,
            proposedProductData: ProductPayload(product: sanitized),
            proposedNutrients: sanitized.nutrients.map(NutrientPayload.init),
            status: .pending
        )
        let body = try JSONEncoder.supabase.encode(initial)
        _ = try await client.request(
            path: "/rest/v1/food_product_contributions",
            method: "POST",
            body: body,
            authenticated: true,
            headers: ["Prefer": "resolution=merge-duplicates,return=minimal"]
        )

        let publishBody = try JSONEncoder.supabase.encode(["p_contribution_id": submissionID.uuidString])
        let (publishData, _) = try await client.request(
            path: "/rest/v1/rpc/publish_food_contribution",
            method: "POST",
            body: publishBody,
            authenticated: true
        )
        let publishedID = (try? JSONDecoder.supabase.decode(UUID.self, from: publishData))
            ?? (try? JSONDecoder.supabase.decode([UUID].self, from: publishData))?.first
        guard let publishedID else {
            throw FoodCommunityServiceError.decodingFailed
        }

        return FoodContribution(
            id: submissionID,
            productID: publishedID,
            barcode: barcode,
            submittedBy: auth.userID,
            contributionType: type,
            proposedProduct: sanitized,
            frontImagePath: nil,
            nutritionImagePath: nil,
            ingredientsImagePath: nil,
            status: .pending,
            createdAt: .now
        )
    }

    private func sanitized(_ product: FoodProduct) -> FoodProduct {
        var copy = product
        copy.name = sanitize(product.name, limit: 180)
        copy.genericName = product.genericName.map { sanitize($0, limit: 300) }
        copy.brand = product.brand.map { sanitize($0, limit: 180) }
        copy.ingredients = product.ingredients.map { sanitize($0, limit: 8_000) }
        copy.allergens = product.allergens.prefix(100).map { sanitize($0, limit: 120) }
        return copy
    }

    private func sanitize(_ value: String, limit: Int) -> String {
        String(value.components(separatedBy: .controlCharacters).joined().prefix(limit))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated private struct ContributionInsert: Encodable {
    var id: UUID
    var productID: UUID?
    var barcode: String
    var sourceProvider: String?
    var sourceProductID: String?
    var sourceDatasetVersion: String?
    var submittedBy: UUID
    var contributionType: FoodContributionType
    var proposedProductData: ProductPayload
    var proposedNutrients: [NutrientPayload]
    var status: FoodContributionStatus
}

extension FoodContributionService {
    nonisolated static func live(configuration: FoodCommunityConfiguration = .current()) -> FoodContributionService {
        let authentication = SupabaseFoodAuthService(configuration: configuration)
        let client = SupabaseFoodRESTClient(configuration: configuration, authentication: authentication)
        return FoodContributionService(client: client)
    }
}
