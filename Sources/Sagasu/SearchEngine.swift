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
    private let pathSearchService: PathSearchService
    private let usageHistoryStore: UsageHistoryStore

    init(
        applicationSearchService: ApplicationSearchService = ApplicationSearchService(),
        macOSSettingsSearchService: MacOSSettingsSearchService = MacOSSettingsSearchService(),
        fileSearchService: FileSearchService = FileSearchService(),
        notesSearchService: NotesSearchService = NotesSearchService(),
        webRouteSearchService: WebRouteSearchService = WebRouteSearchService(),
        gitHubSearchService: GitHubSearchService = GitHubSearchService(),
        linearSearchService: LinearSearchService = LinearSearchService(),
        pathSearchService: PathSearchService = PathSearchService(),
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
        self.pathSearchService = pathSearchService
        self.usageHistoryStore = usageHistoryStore
    }

    @MainActor
    func search(for parsedQuery: ParsedSearchQuery) async throws -> [SearchResult] {
        let results = try await rawSearch(for: parsedQuery)
        switch parsedQuery.mode {
        case .githubOwnedRepositories, .githubGlobalRepositories, .githubIssues, .githubPullRequests,
             .ghqRepositories, .linearIssues, .notes, .terminals, .path:
            return Self.promoteUsed(results, usageHistoryStore: usageHistoryStore)
        case .applications, .directories, .files, .clipboard:
            return results
        }
    }

    /// 履歴のある項目を最終利用が新しい順に先頭へ寄せる。履歴の無い項目は元の順を保つ。
    static func promoteUsed(_ results: [SearchResult], usageHistoryStore: UsageHistoryStore) -> [SearchResult] {
        let dated: [(index: Int, result: SearchResult, date: Date?)] = results.enumerated().map { index, result in
            let date = UsageHistoryKey.key(for: result.action).flatMap { usageHistoryStore.lastUsedAt(for: $0) }
            return (index, result, date)
        }
        let used = dated
            .filter { $0.date != nil }
            .sorted { lhs, rhs in
                if lhs.date! != rhs.date! { return lhs.date! > rhs.date! }
                return lhs.index < rhs.index
            }
        let unused = dated.filter { $0.date == nil }
        return (used + unused).map(\.result)
    }

    @MainActor
    private func rawSearch(for parsedQuery: ParsedSearchQuery) async throws -> [SearchResult] {
        switch parsedQuery.mode {
        case .applications:
            let clipboardImageResults = await MainActor.run {
                clipboardImageTextService.searchResults(query: parsedQuery.query)
            }
            let additionalResults = clipboardImageResults
                + (parsedQuery.query.isEmpty ? [] : macOSSettingsSearchService.results())
            let applicationSearchService = self.applicationSearchService
            let usageHistoryStore = self.usageHistoryStore
            let legacyLookupResults = parsedQuery.query.isEmpty ? macOSSettingsSearchService.results() : []
            let query = parsedQuery.query
            let runningBundleIdentifiers = await MainActor.run {
                Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            }
            let appResults = await Task.detached(priority: .userInitiated) {
                applicationSearchService.search(
                    query: query,
                    usageHistoryStore: usageHistoryStore,
                    additionalResults: additionalResults,
                    legacyLookupResults: legacyLookupResults,
                    runningBundleIdentifiers: runningBundleIdentifiers
                )
            }.value
            if parsedQuery.query.isEmpty { return appResults }

            // Web ルートは差し込み位置を変えず、その中だけ最近使った順に寄せる。
            let webResults = Self.promoteUsed(
                webRouteSearchService.search(query: parsedQuery.query),
                usageHistoryStore: usageHistoryStore
            )
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
            let usageHistoryStore = self.usageHistoryStore
            let query = parsedQuery.query
            let task = Task.detached(priority: .userInitiated) {
                fileSearchService.searchDirectories(query: query, usageHistoryStore: usageHistoryStore)
            }
            return await withTaskCancellationHandler {
                await task.value
            } onCancel: {
                task.cancel()
            }
        case .files:
            let fileSearchService = self.fileSearchService
            let usageHistoryStore = self.usageHistoryStore
            let query = parsedQuery.query
            let task = Task.detached(priority: .userInitiated) {
                try fileSearchService.search(query: query, usageHistoryStore: usageHistoryStore)
            }
            return try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
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
        case .path:
            let pathSearchService = self.pathSearchService
            let query = parsedQuery.query
            return await Task.detached(priority: .userInitiated) {
                pathSearchService.search(query: query)
            }.value
        }
    }

    func hasLinearAPIKey() -> Bool {
        linearSearchService.hasAPIKey()
    }

    /// 選んだ項目を履歴に記録する。表示内容の写しも一緒に保存する。restoreClipboard は記録しない。
    func markUsed(result: SearchResult) throws {
        guard let key = UsageHistoryKey.key(for: result.action) else { return }
        try usageHistoryStore.markUsed(key: key, snapshot: UsageHistoryStore.Snapshot(result: result))
    }

    func markUsed(action: SearchAction) throws {
        guard let key = UsageHistoryKey.key(for: action) else { return }
        try usageHistoryStore.markUsed(key: key)
    }
}
