import Foundation

nonisolated struct FoodPackageTextParser: Sendable {
    func frontProposal(from text: String) -> (name: String?, brand: String?) {
        let lines = usableLines(from: text)
        guard !lines.isEmpty else { return (nil, nil) }
        let name = lines.first
        let brand = lines.dropFirst().first
        return (name, brand)
    }

    func ingredientsText(from text: String) -> String? {
        let normalized = text.replacing("\r\n", with: "\n").replacing("\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let aliases = ["ingredients", "ingredient", "ingredientes", "ingrediente"]
        guard let headingIndex = lines.firstIndex(where: { line in
            let value = line.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            return aliases.contains { value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix($0) }
        }) else { return nil }

        let heading = lines[headingIndex]
        let headingRange = heading.range(of: ":")
        let inline = headingRange.map { String(heading[$0.upperBound...]) } ?? ""
        let following = lines.dropFirst(headingIndex + 1).joined(separator: " ")
        let result = ([inline, following].joined(separator: " "))
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private func usableLines(from text: String) -> [String] {
        text.replacing("\r\n", with: "\n")
            .replacing("\r", with: "\n")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { (2...90).contains($0.count) }
    }
}
