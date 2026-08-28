import Foundation

nonisolated struct NutritionLabelParser: Sendable {
    func parse(lines: [(text: String, confidence: Double)]) -> NutritionLabelOCRResult {
        let combined = lines.map(\.text).joined(separator: "\n")
        let normalizedCombined = normalize(combined)
        let basis: FoodNutrientBasis = normalizedCombined.contains("100 g") || normalizedCombined.contains("100g")
            ? .per100Grams
            : normalizedCombined.contains("100 ml") || normalizedCombined.contains("100ml")
                ? .per100Milliliters
                : .perServing

        let mappings: [(FoodNutrientKey, [String])] = [
            (.energyKcal, ["contenido energetico", "calorias", "calories", "energy"]),
            (.protein, ["proteinas", "proteina", "protein"]),
            (.carbohydrates, ["carbohidratos totales", "carbohidratos", "total carbohydrate", "carbohydrate"]),
            (.fat, ["grasas totales", "grasa total", "total fat"]),
            (.saturatedFat, ["grasas saturadas", "grasa saturada", "saturated fat"]),
            (.transFat, ["grasas trans", "grasa trans", "trans fat"]),
            (.fiber, ["fibra dietetica", "fibra", "dietary fiber", "fiber"]),
            (.addedSugars, ["azucares anadidos", "azucar anadida", "added sugars", "added sugar"]),
            (.sugars, ["azucares totales", "azucares", "total sugars", "sugars"]),
            (.sodium, ["sodio", "sodium"]),
            (.cholesterol, ["colesterol", "cholesterol"]),
            (.calcium, ["calcio", "calcium"]),
            (.iron, ["hierro", "iron"]),
            (.potassium, ["potasio", "potassium"]),
            (.vitaminD, ["vitamina d", "vitamin d"])
        ]

        var nutrients: [FoodNutrient] = []
        var uncertain: Set<String> = []
        for (key, terms) in mappings {
            guard let match = bestNutrientMatch(key: key, terms: terms, lines: lines, basis: basis) else { continue }
            nutrients.removeAll { $0.key == key }
            nutrients.append(match)
            if (match.confidence ?? 0) < 0.7 { uncertain.insert(key.rawValue) }
        }

        let servingLine = lines.first { line in
            let text = normalize(line.text)
            return text.contains("tamano de porcion") || text.contains("serving size")
        }
        let servingMeasurement = servingLine.flatMap { measurement(in: $0.text) }
        let serving = servingMeasurement.map { measurement in
            FoodServing(
                quantity: measurement.amount,
                unit: "serving",
                gramWeight: measurement.unit == "g" ? measurement.amount : nil,
                milliliterVolume: measurement.unit == "ml" ? measurement.amount : nil
            )
        }
        let containerLine = lines.first { line in
            let text = normalize(line.text)
            return text.contains("porciones por envase") || text.contains("servings per container")
        }
        let servingsPerContainer = containerLine.flatMap { firstNumber(in: $0.text) }
        if servingLine != nil && serving == nil { uncertain.insert("serving") }

        return NutritionLabelOCRResult(
            recognizedText: combined,
            serving: serving,
            servingsPerContainer: servingsPerContainer,
            basis: basis,
            nutrients: nutrients,
            uncertainFields: uncertain
        )
    }

    private func bestNutrientMatch(
        key: FoodNutrientKey,
        terms: [String],
        lines: [(text: String, confidence: Double)],
        basis: FoodNutrientBasis
    ) -> FoodNutrient? {
        for line in lines {
            let normalized = normalize(line.text)
            guard terms.contains(where: normalized.contains),
                  let measurement = measurement(in: line.text, calories: key == .energyKcal) else { continue }
            let amount = convert(measurement.amount, unit: measurement.unit, for: key)
            return FoodNutrient(
                key: key,
                amount: amount,
                unit: key.canonicalUnit,
                basis: basis,
                confidence: line.confidence
            )
        }
        return nil
    }

    private func measurement(in text: String, calories: Bool = false) -> (amount: Double, unit: String)? {
        let pattern = calories
            ? #"([0-9]+(?:[.,][0-9]+)?)\s*(kcal|calorias|calories|kj)?"#
            : #"([0-9]+(?:[.,][0-9]+)?)\s*(mcg|ug|µg|μg|mg|g|ml)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let amountRange = Range(match.range(at: 1), in: text),
              let amount = Double(text[amountRange].replacing(",", with: ".")) else { return nil }
        let unit: String
        if match.range(at: 2).location != NSNotFound, let unitRange = Range(match.range(at: 2), in: text) {
            unit = text[unitRange].lowercased()
        } else {
            unit = calories ? "kcal" : "g"
        }
        return (amount, unit)
    }

    private func firstNumber(in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"[0-9]+(?:[.,][0-9]+)?"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return Double(text[range].replacing(",", with: "."))
    }

    private func convert(_ amount: Double, unit: String, for key: FoodNutrientKey) -> Double {
        let normalizedUnit = unit.replacing("µ", with: "u").replacing("μ", with: "u")
        return switch (normalizedUnit, key.canonicalUnit) {
        case ("g", "mg"): amount * 1_000
        case ("mg", "g"): amount / 1_000
        case ("mg", "mcg"): amount * 1_000
        case ("ug", "mg"), ("mcg", "mg"): amount / 1_000
        case ("kj", "kcal"): amount / 4.184
        default: amount
        }
    }

    private func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }
}
