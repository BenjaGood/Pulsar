import SwiftUI

extension ProductVisualCategory {
    var tint: Color {
        switch self {
        case .bakery: Color(red: 0.72, green: 0.50, blue: 0.26)
        case .yogurt: Color(red: 0.35, green: 0.53, blue: 0.78)
        case .snack: Color(red: 0.78, green: 0.48, blue: 0.25)
        case .proteinBar: Color(red: 0.48, green: 0.42, blue: 0.66)
        case .drink: Color(red: 0.23, green: 0.58, blue: 0.63)
        case .cereal: Color(red: 0.65, green: 0.46, blue: 0.28)
        case .milk: Color(red: 0.38, green: 0.58, blue: 0.76)
        case .cheese: Color(red: 0.78, green: 0.61, blue: 0.25)
        case .frozen: Color(red: 0.32, green: 0.64, blue: 0.76)
        case .candy: Color(red: 0.72, green: 0.39, blue: 0.51)
        case .unknown: Color(red: 0.43, green: 0.47, blue: 0.54)
        }
    }

    var accessibilityName: String {
        switch self {
        case .bakery: "Bakery"
        case .yogurt: "Yogurt or dairy"
        case .snack: "Snack"
        case .proteinBar: "Protein bar"
        case .drink: "Drink"
        case .cereal: "Cereal"
        case .milk: "Milk"
        case .cheese: "Cheese"
        case .frozen: "Frozen product"
        case .candy: "Candy"
        case .unknown: "Packaged product"
        }
    }
}
