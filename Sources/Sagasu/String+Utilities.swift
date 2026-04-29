import Foundation

extension String {
    func condensedWhitespace() -> String {
        split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    func truncated(limit: Int) -> String {
        guard count > limit else { return self }
        let index = self.index(startIndex, offsetBy: limit)
        return String(self[..<index]) + "…"
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension DateFormatter {
    static let clipboardTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
