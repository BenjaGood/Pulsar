//
//  MealScanCalibrationStore.swift
//  Pulsar
//

import Foundation
import Observation

/// Food form categories mirroring the backend COOKED_FOOD_DENSITY_TABLE keys.
/// Each key identifies a class of food for per-category calibration.
enum MealScanFoodForm: String, CaseIterable, Sendable {
    case looseGrains  = "loose_grains"
    case pasta        = "pasta"
    case solidProtein = "solid_protein"
    case choppedVeg   = "chopped_veg"
    case denseVeg     = "dense_veg"
    case legumes      = "legumes"
    case soupLiquid   = "soup_liquid"
    case mixed        = "mixed"
    case breadStarch  = "bread_starch"
    case dairySauce   = "dairy_sauce"

    var displayName: String {
        switch self {
        case .looseGrains:  "Grains (rice, quinoa)"
        case .pasta:        "Pasta & Noodles"
        case .solidProtein: "Protein (meat, fish, egg, tofu)"
        case .choppedVeg:   "Leafy Salad & Greens"
        case .denseVeg:     "Cooked Vegetables"
        case .legumes:      "Beans & Legumes"
        case .soupLiquid:   "Soups & Liquids"
        case .mixed:        "Mixed Dishes"
        case .breadStarch:  "Bread & Starch"
        case .dairySauce:   "Dairy & Sauce"
        }
    }

    /// Maps an ingredient name to the closest food form using the same keyword logic as the backend.
    static func classify(from name: String) -> MealScanFoodForm {
        let n = name.lowercased()
        if matches(n, patterns: #"\b(rice|quinoa|couscous|millet|barley|grain|farro|bulgur|oat|porridge)\b"#) { return .looseGrains }
        if matches(n, patterns: #"\b(pasta|spaghetti|penne|fettuccine|noodle|macaroni|linguine|rigatoni|lasagna|ramen|udon|soba|orzo)\b"#) { return .pasta }
        if matches(n, patterns: #"\b(chicken|beef|steak|pork|turkey|fish|salmon|tuna|shrimp|prawn|seafood|egg|tofu|tempeh|meat|lamb|duck|venison)\b"#) { return .solidProtein }
        if matches(n, patterns: #"\b(salad|lettuce|spinach|arugula|greens|kale|cabbage|slaw|mesclun|chard|watercress)\b"#) { return .choppedVeg }
        if matches(n, patterns: #"\b(broccoli|carrot|cauliflower|roasted|sweet.?potato|yam|corn|zucchini|eggplant|squash|asparagus|green.?bean|brussels|mushroom|beet)\b"#) { return .denseVeg }
        if matches(n, patterns: #"\b(bean|lentil|chickpea|hummus|edamame|soybean|legume)\b"#) { return .legumes }
        if matches(n, patterns: #"\b(soup|stew|broth|bisque|chowder|curry|sauce|gravy|liquid|congee)\b"#) { return .soupLiquid }
        if matches(n, patterns: #"\b(bread|toast|roll|bun|pancake|waffle|tortilla|wrap|pita|bagel|muffin|cracker|naan|flatbread)\b"#) { return .breadStarch }
        if matches(n, patterns: #"\b(yogurt|cheese|cream|milk|dairy|butter|queso|ricotta|cottage)\b"#) { return .dairySauce }
        return .mixed
    }

    private static func matches(_ text: String, patterns: String) -> Bool {
        (try? NSRegularExpression(pattern: patterns, options: []))
            .map { $0.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil }
            ?? false
    }
}

/// Stores per-food-form correction factors learned from user-confirmed gram measurements.
///
/// Factors are bounded to [0.6, 1.7] and smoothed via exponential moving average so a single
/// outlier measurement cannot radically change future estimates. Only non-neutral factors are
/// included in the scan payload, keeping the data anonymized and compact.
@Observable
final class MealScanCalibrationStore: Sendable {
    static let shared = MealScanCalibrationStore()

    /// Lower bound: prevents estimates shrinking below 60 % of the model result.
    static let factorMin: Double = 0.60
    /// Upper bound: prevents estimates growing beyond 170 % of the model result.
    static let factorMax: Double = 1.70
    /// Smoothing coefficient: 0 = always replace, 1 = never change. 0.65 ≈ 3-scan convergence.
    static let smoothingAlpha: Double = 0.65
    /// Factors within this distance of 1.0 are treated as neutral and excluded from the payload.
    static let neutralThreshold: Double = 0.03

    private static let defaultsKey = "pulsar.mealScanner.calibration.v1"

    private(set) var factors: [String: Double] = [:] {
        didSet { persist() }
    }

    init() {
        factors = Self.load()
    }

    /// Records a calibration observation from a user-confirmed actual gram weight.
    /// Safe to call with either estimated or measured being 0 — call is silently ignored.
    func record(estimatedGrams: Double, measuredGrams: Double, foodForm: MealScanFoodForm) {
        guard estimatedGrams > 1, measuredGrams > 1 else { return }
        let ratio = (measuredGrams / estimatedGrams).clamped(Self.factorMin, Self.factorMax)
        let existing = factors[foodForm.rawValue] ?? 1.0
        let updated = Self.smoothingAlpha * existing + (1.0 - Self.smoothingAlpha) * ratio
        factors[foodForm.rawValue] = updated.clamped(Self.factorMin, Self.factorMax)
    }

    /// Resets the factor for a single food form back to neutral.
    func reset(for foodForm: MealScanFoodForm) {
        factors[foodForm.rawValue] = nil
    }

    /// Resets all stored factors.
    func reset() {
        factors = [:]
    }

    /// Returns only factors that differ meaningfully from 1.0.
    /// This is the value sent in the scan payload — never leaks neutral or near-neutral entries.
    var nonNeutralFactors: [String: Double] {
        factors.filter { abs($0.value - 1.0) > Self.neutralThreshold }
    }

    // MARK: - Persistence

    private func persist() {
        UserDefaults.standard.set(factors, forKey: Self.defaultsKey)
    }

    private static func load() -> [String: Double] {
        guard let dict = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Double] else {
            return [:]
        }
        return dict.mapValues { $0.clamped(factorMin, factorMax) }
    }
}

private extension Double {
    func clamped(_ minimum: Double, _ maximum: Double) -> Double {
        min(max(self, minimum), maximum)
    }
}
