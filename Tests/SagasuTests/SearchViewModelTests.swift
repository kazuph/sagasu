import AppKit
import Foundation
import Testing
@testable import Sagasu

@MainActor
@Test
func presentationAlwaysStartsAtTopResult() async throws {
    let viewModel = try makeSearchViewModel()

    viewModel.rawQuery = "sagasu-focus-reset"
    try await waitForSearchToFinish(viewModel)
    #expect(viewModel.results.count >= 2)

    viewModel.select(index: 1)
    #expect(viewModel.selectedIndex == 1)

    viewModel.prepareForPresentation()

    #expect(viewModel.rawQuery.isEmpty)
    #expect(viewModel.selectedIndex == 0)
}

@MainActor
@Test
func newSearchResultsDoNotKeepPreviousCursorPosition() async throws {
    let viewModel = try makeSearchViewModel()

    viewModel.rawQuery = "sagasu-first-query"
    try await waitForSearchToFinish(viewModel)
    #expect(viewModel.results.count >= 2)

    viewModel.select(index: 1)
    #expect(viewModel.selectedIndex == 1)

    viewModel.rawQuery = "sagasu-second-query"
    try await waitForSearchToFinish(viewModel)

    #expect(viewModel.selectedIndex == 0)
}

@MainActor
private func makeSearchViewModel() throws -> SearchViewModel {
    let fileManager = FileManager.default
    let baseDirectoryURL = fileManager.temporaryDirectory
        .appending(path: "SagasuViewModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
    let clipboardStore = ClipboardHistoryStore(
        fileManager: fileManager,
        pasteboard: NSPasteboard.withUniqueName(),
        baseDirectoryURL: baseDirectoryURL
    )
    return SearchViewModel(searchEngine: SearchEngine(clipboardStore: clipboardStore))
}

@MainActor
private func waitForSearchToFinish(_ viewModel: SearchViewModel) async throws {
    for _ in 0..<20 {
        if viewModel.isSearching == false && viewModel.results.isEmpty == false {
            return
        }
        try await Task.sleep(for: .milliseconds(50))
    }
    Issue.record("Search did not finish with results")
}
