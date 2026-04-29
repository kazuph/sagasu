import Foundation

enum SearchMatcher {
    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .condensedWhitespace()
    }

    static func score(query: String, primaryText: String, secondaryText: String?) -> Int? {
        guard query.isEmpty == false else { return 0 }

        if primaryText == query {
            return 1_000
        }

        if primaryText.hasPrefix(query) {
            return 900 - max(0, primaryText.count - query.count)
        }

        if let range = primaryText.range(of: query) {
            return 750 - primaryText.distance(from: primaryText.startIndex, to: range.lowerBound)
        }

        let queryParts = query.split(separator: " ").map(String.init)
        if queryParts.isEmpty == false, queryParts.allSatisfy({ primaryText.contains($0) }) {
            return 650
        }

        if let secondaryText, secondaryText.contains(query) {
            return 500
        }

        return nil
    }
}
