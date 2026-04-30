import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var rawQuery: String = "" {
        didSet {
            refreshSearch()
        }
    }
    @Published private(set) var parsedQuery = ParsedSearchQuery(mode: .applications, query: "", clipboardImageOnly: false)
    @Published private(set) var results: [SearchResult] = []
    @Published private(set) var selectedIndex = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var isSearching = false
    @Published private(set) var presentationID = UUID()

    var selectedResultID: UUID? {
        guard results.indices.contains(selectedIndex) else { return nil }
        return results[selectedIndex].id
    }

    var selectedPreviewImageURL: URL? {
        guard let result = results[safe: selectedIndex] else { return nil }
        guard case .imageThumbnail(let url) = result.visual else { return nil }
        return url
    }

    var promptText: String {
        if parsedQuery.mode == .clipboard && parsedQuery.clipboardImageOnly {
            return "Search clipboard images"
        }
        return parsedQuery.mode.hintText
    }

    var badgeTitle: String {
        if parsedQuery.mode == .clipboard && parsedQuery.clipboardImageOnly {
            return "Clipboard Images"
        }
        return parsedQuery.mode.displayName
    }

    var helperText: String {
        switch parsedQuery.mode {
        case .applications:
            return "Default mode. Type `f ` for files, `n ` for Notes, `v ` for clipboard history. Query also shows Google and ChatGPT routes."
        case .files:
            return "Desktop / Downloads / Documents / Pictures / Movies / Dropbox / iCloud / Recent Places"
        case .notes:
            return "Searches Notes titles and bodies."
        case .clipboard:
            if parsedQuery.clipboardImageOnly {
                return "Search saved clipboard images only. Type `v ` for text + image history. Default retention is 3 months, reuse extends 6 months, ⌘P toggles pin, and ⌘D deletes."
            }
            return "Search saved clipboard text and images. Default retention is 3 months, reuse extends 6 months, ⌘P toggles pin, and ⌘D deletes."
        }
    }

    var actionHandler: ((SearchAction) -> Void)?
    var clipboardPinToggleHandler: ((UUID) throws -> Void)?
    var clipboardDeleteHandler: ((UUID) throws -> Void)?

    private let searchEngine: SearchEngine
    private var searchTask: Task<Void, Never>?

    init(searchEngine: SearchEngine) {
        self.searchEngine = searchEngine
        refreshSearch()
    }

    func prepareForPresentation() {
        rawQuery = ""
        errorMessage = nil
        presentationID = UUID()
    }

    func dismiss() {
        searchTask?.cancel()
    }

    func selectNext() {
        guard results.isEmpty == false else { return }
        selectedIndex = min(selectedIndex + 1, results.count - 1)
    }

    func selectPrevious() {
        guard results.isEmpty == false else { return }
        selectedIndex = max(selectedIndex - 1, 0)
    }

    func select(index: Int) {
        guard results.indices.contains(index) else { return }
        selectedIndex = index
    }

    func activateSelectedResult() {
        guard let action = results[safe: selectedIndex]?.action else { return }
        actionHandler?(action)
    }

    func togglePinForSelectedClipboardEntry() {
        guard parsedQuery.mode == .clipboard else { return }
        guard let entryID = selectedClipboardEntryID else { return }

        do {
            try clipboardPinToggleHandler?(entryID)
            errorMessage = nil
            refreshSearch()
        } catch {
            present(error: error)
        }
    }

    func deleteSelectedClipboardEntry() {
        guard parsedQuery.mode == .clipboard else { return }
        guard let entryID = selectedClipboardEntryID else { return }

        do {
            try clipboardDeleteHandler?(entryID)
            errorMessage = nil
            refreshSearch()
        } catch {
            present(error: error)
        }
    }

    func present(error: Error) {
        errorMessage = error.localizedDescription
    }

    private func refreshSearch() {
        searchTask?.cancel()
        let parsedQuery = SearchModeParser.parse(rawQuery)
        self.parsedQuery = parsedQuery
        isSearching = false
        let searchEngine = self.searchEngine

        searchTask = Task { [weak self] in
            do {
                if parsedQuery.query.isEmpty && parsedQuery.mode != .applications && parsedQuery.mode != .clipboard {
                    await MainActor.run {
                        self?.results = []
                        self?.selectedIndex = 0
                        self?.errorMessage = nil
                        self?.isSearching = false
                    }
                    return
                }

                await MainActor.run {
                    self?.isSearching = true
                }
                try await Task.sleep(for: .milliseconds(parsedQuery.mode == .applications ? 40 : 120))
                let results = try await searchEngine.search(for: parsedQuery)

                guard Task.isCancelled == false else { return }

                await MainActor.run {
                        self?.results = results
                        self?.selectedIndex = results.isEmpty ? 0 : min(self?.selectedIndex ?? 0, results.count - 1)
                        self?.errorMessage = nil
                        self?.isSearching = false
                    }
            } catch is CancellationError {
                await MainActor.run {
                    self?.isSearching = false
                }
                return
            } catch {
                await MainActor.run {
                    self?.results = []
                    self?.selectedIndex = 0
                    self?.errorMessage = error.localizedDescription
                    self?.isSearching = false
                }
            }
        }
    }

    private var selectedClipboardEntryID: UUID? {
        guard let action = results[safe: selectedIndex]?.action else { return nil }
        guard case .restoreClipboard(let entryID) = action else { return nil }
        return entryID
    }
}
