import XCTest
@testable import Pulsar

final class ProductVisualTests: XCTestCase {
    func testCategoryResolutionUsesSpecificProductKeywords() {
        XCTAssertEqual(ProductVisualCategory.resolve(name: "Yoplait Cocoa Puffs"), .cereal)
        XCTAssertEqual(ProductVisualCategory.resolve(name: "Bimbo White Bread"), .bakery)
        XCTAssertEqual(ProductVisualCategory.resolve(name: "Chocolate Protein Bar"), .proteinBar)
        XCTAssertEqual(ProductVisualCategory.resolve(name: "Frozen Strawberry Yogurt"), .frozen)
        XCTAssertEqual(ProductVisualCategory.resolve(name: "Sabritas Potato Chips"), .snack)
    }

    func testBrandMonogramIsNeutralSingleCharacterMetadata() {
        XCTAssertEqual(ProductVisualDescriptor(name: "Yogurt", brand: "Yoplait").brandMonogram, "Y")
        XCTAssertEqual(ProductVisualDescriptor(name: "Bread", brand: " Bimbo ").brandMonogram, "B")
        XCTAssertNil(ProductVisualDescriptor(name: "Unknown", brand: nil).brandMonogram)
    }

    func testSearchDisplayItemPrecomputesPlaceholderMetadata() {
        let product = FoodProduct(
            name: "Original Yogurt",
            brand: "Yoplait",
            source: .openNutrition,
            verificationStatus: .imported,
            nutrients: []
        )

        let item = ProductSearchDisplayItem(product: product)

        XCTAssertEqual(item.visualDescriptor.category, .yogurt)
        XCTAssertEqual(item.visualDescriptor.brandMonogram, "Y")
    }
}
