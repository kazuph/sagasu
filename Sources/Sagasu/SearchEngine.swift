import AppKit
import Foundation

struct SearchEngine {
    private let applicationSearchService: ApplicationSearchService
    private let macOSSettingsSearchService: MacOSSettingsSearchService
    private let fileSearchService: FileSearchService
    private let notesSearchService: NotesSearchService
    private let clipboardStore: ClipboardHistoryStore
    private let clipboardImageTextService: ClipboardImageTextService
    private let herdrSearchService: HerdrSearchService?
    private let webRouteSearchService: WebRouteSearchService
    private let calculatorSearchService: CalculatorSearchService
    private let gitHubSearchService: GitHubSearchService
    private let linearSearchService: LinearSearchService
    private let usageHistoryStore: UsageHistoryStore

    init(
        applicationSearchService: ApplicationSearchService = ApplicationSearchService(),
        macOSSettingsSearchService: MacOSSettingsSearchService = MacOSSettingsSearchService(),
        fileSearchService: FileSearchService = FileSearchService(),
        notesSearchService: NotesSearchService = NotesSearchService(),
        webRouteSearchService: WebRouteSearchService = WebRouteSearchService(),
        gitHubSearchService: GitHubSearchService = GitHubSearchService(),
        linearSearchService: LinearSearchService = LinearSearchService(),
        clipboardStore: ClipboardHistoryStore,
        clipboardImageTextService: ClipboardImageTextService = ClipboardImageTextService(),
        herdrSearchService: HerdrSearchService? = try? HerdrSearchService(),
        calculatorSearchService: CalculatorSearchService = CalculatorSearchService(),
        usageHistoryStore: UsageHistoryStore = UsageHistoryStore()
    ) {
        self.applicationSearchService = applicationSearchService
        self.macOSSettingsSearchService = macOSSettingsSearchService
        self.fileSearchService = fileSearchService
        self.notesSearchService = notesSearchService
        self.clipboardStore = clipboardStore
        self.clipboardImageTextService = clipboardImageTextService
        self.herdrSearchService = herdrSearchService
        self.webRouteSearchService = webRouteSearchService
        self.calculatorSearchService = calculatorSearchService
        self.gitHubSearchService = gitHubSearchService
        self.linearSearchService = linearSearchService
        self.usageHistoryStore = usageHistoryStore
    }

    @MainActor
    func search(for parsedQuery: ParsedSearchQuery) async throws -> [SearchResult] {
        switch parsedQuery.mode {
        case .applications:
            let clipboardImageResults = await MainActor.run {
                clipboardImageTextService.searchResults(query: parsedQuery.query)
            }
            let additionalResults = clipboardImageResults
                + (parsedQuery.query.isEmpty ? [] : macOSSettingsSearchService.results())
            let applicationSearchService = self.applicationSearchService
            let usageHistoryStore = self.usageHistoryStore
            let query = parsedQuery.query
            let runningBundleIdentifiers = await MainActor.run {
                Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            }
            let appResults = await Task.detached(priority: .userInitiated) {
                applicationSearchService.search(
                    query: query,
                    usageHistoryStore: usageHistoryStore,
                    additionalResults: additionalResults,
                    runningBundleIdentifiers: runningBundleIdentifiers
                )
            }.value
            if parsedQuery.query.isEmpty {
                let fileSearchService = self.fileSearchService
                let recentFolders = await Task.detached(priority: .userInitiated) {
                    fileSearchService.recentFolders(limit: 10)
                }.value
                return Array(appResults.prefix(3)) + recentFolders + Array(appResults.dropFirst(3))
            }

            let webResults = webRouteSearchService.search(query: parsedQuery.query)
            let calculatorResults = calculatorSearchService.search(query: parsedQuery.query)
            guard webResults.isEmpty == false || calculatorResults.isEmpty == false else { return appResults }

            let prioritizedApplicationCount = min(3, appResults.count)
            var mergedResults = calculatorResults
            mergedResults.append(contentsOf: appResults.prefix(prioritizedApplicationCount))
            mergedResults.append(contentsOf: webResults)
            mergedResults.append(contentsOf: appResults.dropFirst(prioritizedApplicationCount))
            return mergedResults
        case .directories:
            let fileSearchService = self.fileSearchService
            let query = parsedQuery.query
            return await Task.detached(priority: .userInitiated) {
                fileSearchService.searchDirectories(query: query)
            }.value
        case .files:
            let fileSearchService = self.fileSearchService
            let query = parsedQuery.query
            return try await Task.detached(priority: .userInitiated) {
                try fileSearchService.search(query: query)
            }.value
        case .terminals:
            guard let herdrSearchService else { return [] }
            let query = parsedQuery.query
            return try await Task.detached(priority: .userInitiated) {
                try herdrSearchService.search(query: query)
            }.value
        case .notes:
            let notesSearchService = self.notesSearchService
            let query = parsedQuery.query
            return try await Task.detached(priority: .userInitiated) {
                try notesSearchService.search(query: query)
            }.value
        case .clipboard:
            let clipboardStore = self.clipboardStore
            let query = parsedQuery.query
            return await MainActor.run {
                clipboardStore.search(query: query, imageOnly: parsedQuery.clipboardImageOnly)
            }
        case .githubOwnedRepositories:
            let gitHubSearchService = self.gitHubSearchService
            let query = parsedQuery.query
            return try await Task.detached(priority: .userInitiated) {
                return try gitHubSearchService.searchOwnedRepositories(query: query)
            }.value
        case .githubGlobalRepositories:
            let gitHubSearchService = self.gitHubSearchService
            let query = parsedQuery.query
            return try await Task.detached(priority: .userInitiated) {
                guard gitHubSearchService.isGitHubCLIAvailable() else { return [] }
                return try gitHubSearchService.searchGlobalRepositories(query: query)
            }.value
        case .githubIssues:
            let gitHubSearchService = self.gitHubSearchService
            let query = parsedQuery.query
            return try await Task.detached(priority: .userInitiated) {
                guard gitHubSearchService.isGitHubCLIAvailable() else { return [] }
                return try gitHubSearchService.searchIssues(query: query)
            }.value
        case .githubPullRequests:
            let gitHubSearchService = self.gitHubSearchService
            let query = parsedQuery.query
            return try await Task.detached(priority: .userInitiated) {
                guard gitHubSearchService.isGitHubCLIAvailable() else { return [] }
                return try gitHubSearchService.searchPullRequests(query: query)
            }.value
        case .ghqRepositories:
            let gitHubSearchService = self.gitHubSearchService
            let query = parsedQuery.query
            return await Task.detached(priority: .userInitiated) {
                gitHubSearchService.searchGHQRepositories(query: query)
            }.value
        case .linearIssues:
            let linearSearchService = self.linearSearchService
            let query = parsedQuery.query
            return try await linearSearchService.searchIssues(query: query)
        }
    }

    func hasLinearAPIKey() -> Bool {
        linearSearchService.hasAPIKey()
    }

    func markUsed(action: SearchAction) throws {
        switch action {
        case .launchApplication(let url):
            try usageHistoryStore.markUsed(key: UsageHistoryKey.application(url))
        case .openURL(let url):
            try usageHistoryStore.markUsed(key: UsageHistoryKey.url(url))
        case .openURLInPreferredBrowser, .openNote, .restoreClipboard, .saveClipboardImage, .extractTextFromClipboardImage, .focusTerminalPane, .configureLinearAPIKey, .copyText:
            return
        }
    }
}
