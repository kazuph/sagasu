import Foundation

struct SearchEngine {
    private let applicationSearchService: ApplicationSearchService
    private let fileSearchService: FileSearchService
    private let notesSearchService: NotesSearchService
    private let clipboardStore: ClipboardHistoryStore
    private let clipboardImageTextService: ClipboardImageTextService
    private let herdrSearchService: HerdrSearchService?
    private let webRouteSearchService: WebRouteSearchService
    private let usageHistoryStore: UsageHistoryStore

    init(
        applicationSearchService: ApplicationSearchService = ApplicationSearchService(),
        fileSearchService: FileSearchService = FileSearchService(),
        notesSearchService: NotesSearchService = NotesSearchService(),
        webRouteSearchService: WebRouteSearchService = WebRouteSearchService(),
        clipboardStore: ClipboardHistoryStore,
        clipboardImageTextService: ClipboardImageTextService = ClipboardImageTextService(),
        herdrSearchService: HerdrSearchService? = try? HerdrSearchService(),
        usageHistoryStore: UsageHistoryStore = UsageHistoryStore()
    ) {
        self.applicationSearchService = applicationSearchService
        self.fileSearchService = fileSearchService
        self.notesSearchService = notesSearchService
        self.clipboardStore = clipboardStore
        self.clipboardImageTextService = clipboardImageTextService
        self.herdrSearchService = herdrSearchService
        self.webRouteSearchService = webRouteSearchService
        self.usageHistoryStore = usageHistoryStore
    }

    @MainActor
    func search(for parsedQuery: ParsedSearchQuery) async throws -> [SearchResult] {
        switch parsedQuery.mode {
        case .applications:
            let additionalResults = clipboardImageTextService.searchResults(query: parsedQuery.query)
            let appResults = applicationSearchService.search(
                query: parsedQuery.query,
                usageHistoryStore: usageHistoryStore,
                additionalResults: additionalResults
            )
            if parsedQuery.query.isEmpty {
                let fileSearchService = self.fileSearchService
                let recentFolders = await Task.detached(priority: .userInitiated) {
                    fileSearchService.recentFolders(limit: 10)
                }.value
                return Array(appResults.prefix(3)) + recentFolders + Array(appResults.dropFirst(3))
            }

            let webResults = webRouteSearchService.search(query: parsedQuery.query)
            guard webResults.isEmpty == false else { return appResults }

            let prioritizedApplicationCount = min(3, appResults.count)
            var mergedResults = Array(appResults.prefix(prioritizedApplicationCount))
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
        }
    }

    func markUsed(action: SearchAction) throws {
        switch action {
        case .launchApplication(let url):
            try usageHistoryStore.markUsed(key: UsageHistoryKey.application(url))
        case .openURL(let url):
            try usageHistoryStore.markUsed(key: UsageHistoryKey.url(url))
        case .openURLInPreferredBrowser, .openNote, .restoreClipboard, .saveClipboardImage, .extractTextFromClipboardImage, .focusTerminalPane:
            return
        }
    }
}
