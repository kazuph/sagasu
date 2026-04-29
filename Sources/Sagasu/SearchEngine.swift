import Foundation

struct SearchEngine {
    private let applicationSearchService: ApplicationSearchService
    private let fileSearchService: FileSearchService
    private let notesSearchService: NotesSearchService
    private let clipboardStore: ClipboardHistoryStore
    private let webRouteSearchService: WebRouteSearchService

    init(
        applicationSearchService: ApplicationSearchService = ApplicationSearchService(),
        fileSearchService: FileSearchService = FileSearchService(),
        notesSearchService: NotesSearchService = NotesSearchService(),
        webRouteSearchService: WebRouteSearchService = WebRouteSearchService(),
        clipboardStore: ClipboardHistoryStore
    ) {
        self.applicationSearchService = applicationSearchService
        self.fileSearchService = fileSearchService
        self.notesSearchService = notesSearchService
        self.clipboardStore = clipboardStore
        self.webRouteSearchService = webRouteSearchService
    }

    func search(for parsedQuery: ParsedSearchQuery) async throws -> [SearchResult] {
        switch parsedQuery.mode {
        case .applications:
            let appResults = applicationSearchService.search(query: parsedQuery.query)
            let webResults = webRouteSearchService.search(query: parsedQuery.query)
            guard webResults.isEmpty == false else { return appResults }

            let prioritizedApplicationCount = min(3, appResults.count)
            var mergedResults = Array(appResults.prefix(prioritizedApplicationCount))
            mergedResults.append(contentsOf: webResults)
            mergedResults.append(contentsOf: appResults.dropFirst(prioritizedApplicationCount))
            return mergedResults
        case .files:
            let fileSearchService = self.fileSearchService
            let query = parsedQuery.query
            return try await Task.detached(priority: .userInitiated) {
                try fileSearchService.search(query: query)
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
}
