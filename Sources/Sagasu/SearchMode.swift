import Foundation

enum SearchMode: String, CaseIterable {
    case applications
    case directories
    case files
    case terminals
    case notes
    case clipboard
    case githubOwnedRepositories
    case githubGlobalRepositories
    case githubIssues
    case githubPullRequests
    case ghqRepositories
    case linearIssues

    var displayName: String {
        switch self {
        case .applications:
            return "Applications"
        case .directories:
            return "Directories"
        case .files:
            return "Files"
        case .terminals:
            return "Terminals"
        case .notes:
            return "Notes"
        case .clipboard:
            return "Clipboard"
        case .githubOwnedRepositories:
            return "GitHub"
        case .githubGlobalRepositories:
            return "GitHub Global"
        case .githubIssues:
            return "GitHub Issues"
        case .githubPullRequests:
            return "GitHub PRs"
        case .ghqRepositories:
            return "ghq"
        case .linearIssues:
            return "Linear"
        }
    }

    var hintText: String {
        switch self {
        case .applications:
            return "Search applications, Google, or ChatGPT"
        case .directories:
            return "Search directories"
        case .files:
            return "Search files in Desktop, Downloads, Documents, Photos, Movies, Dropbox, iCloud"
        case .terminals:
            return "Search Herdr panes"
        case .notes:
            return "Search Apple Notes"
        case .clipboard:
            return "Search clipboard history"
        case .githubOwnedRepositories:
            return "Search your GitHub and ghq repositories"
        case .githubGlobalRepositories:
            return "Search all GitHub repositories"
        case .githubIssues:
            return "Search GitHub issues in your repositories"
        case .githubPullRequests:
            return "Search GitHub pull requests in your repositories"
        case .ghqRepositories:
            return "Search ghq repositories"
        case .linearIssues:
            return "Search Linear issues"
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

        if lowercased.hasPrefix("ghq ") {
            return ParsedSearchQuery(mode: .ghqRepositories, query: String(rawValue.dropFirst(4)).condensedWhitespace(), clipboardImageOnly: false)
        }

        if lowercased.hasPrefix("l ") {
            return ParsedSearchQuery(mode: .linearIssues, query: String(rawValue.dropFirst(2)).condensedWhitespace(), clipboardImageOnly: false)
        }

        if lowercased.hasPrefix("gh ") {
            return ParsedSearchQuery(mode: .githubGlobalRepositories, query: String(rawValue.dropFirst(3)).condensedWhitespace(), clipboardImageOnly: false)
        }

        if lowercased.hasPrefix("gi ") {
            return ParsedSearchQuery(mode: .githubIssues, query: String(rawValue.dropFirst(3)).condensedWhitespace(), clipboardImageOnly: false)
        }

        if lowercased.hasPrefix("gp ") {
            return ParsedSearchQuery(mode: .githubPullRequests, query: String(rawValue.dropFirst(3)).condensedWhitespace(), clipboardImageOnly: false)
        }

        if lowercased.hasPrefix("g ") {
            return ParsedSearchQuery(mode: .githubOwnedRepositories, query: String(rawValue.dropFirst(2)).condensedWhitespace(), clipboardImageOnly: false)
        }

        if lowercased.hasPrefix("f ") {
            return ParsedSearchQuery(mode: .files, query: String(rawValue.dropFirst(2)).condensedWhitespace(), clipboardImageOnly: false)
        }

        if lowercased.hasPrefix("d ") {
            return ParsedSearchQuery(mode: .directories, query: String(rawValue.dropFirst(2)).condensedWhitespace(), clipboardImageOnly: false)
        }

        if lowercased.hasPrefix("t ") {
            return ParsedSearchQuery(mode: .terminals, query: String(rawValue.dropFirst(2)).condensedWhitespace(), clipboardImageOnly: false)
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
