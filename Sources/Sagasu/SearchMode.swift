import Foundation

enum SearchMode: String, CaseIterable {
    case applications
    case files
    case notes
    case clipboard

    var displayName: String {
        switch self {
        case .applications:
            return "Applications"
        case .files:
            return "Files"
        case .notes:
            return "Notes"
        case .clipboard:
            return "Clipboard"
        }
    }

    var hintText: String {
        switch self {
        case .applications:
            return "Search applications, Google, or ChatGPT"
        case .files:
            return "Search files in Desktop, Downloads, Documents, Photos, Movies, Dropbox, iCloud"
        case .notes:
            return "Search Apple Notes"
        case .clipboard:
            return "Search clipboard history"
        }
    }
}

struct ParsedSearchQuery: Equatable {
    let mode: SearchMode
    let query: String
    let clipboardImageOnly: Bool
}

enum SearchModeParser {
    static func parse(_ rawValue: String) -> ParsedSearchQuery {
        let lowercased = rawValue.lowercased()

        if lowercased == "vi" {
            return ParsedSearchQuery(mode: .clipboard, query: "", clipboardImageOnly: true)
        }

        if lowercased.hasPrefix("vi ") {
            return ParsedSearchQuery(mode: .clipboard, query: String(rawValue.dropFirst(3)).condensedWhitespace(), clipboardImageOnly: true)
        }

        if lowercased.hasPrefix("f ") {
            return ParsedSearchQuery(mode: .files, query: String(rawValue.dropFirst(2)).condensedWhitespace(), clipboardImageOnly: false)
        }

        if lowercased.hasPrefix("n ") {
            return ParsedSearchQuery(mode: .notes, query: String(rawValue.dropFirst(2)).condensedWhitespace(), clipboardImageOnly: false)
        }

        if lowercased.hasPrefix("v ") {
            return ParsedSearchQuery(mode: .clipboard, query: String(rawValue.dropFirst(2)).condensedWhitespace(), clipboardImageOnly: false)
        }

        return ParsedSearchQuery(mode: .applications, query: rawValue.condensedWhitespace(), clipboardImageOnly: false)
    }
}
