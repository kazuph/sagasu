import AppKit
import Foundation
import Testing
@testable import Sagasu

@Test
func macOSSettingsSearchReadsInstalledDisplaysExtension() {
    let settingsResults = MacOSSettingsSearchService(
        preferredLocalizations: ["ja"]
    ).results()
    let results = ApplicationSearchService(fileManager: .default, roots: []).search(
        query: "画面",
        additionalResults: settingsResults
    )
    let displaysResults = results.filter { result in
        guard case .openURL(let url) = result.action else { return false }
        return url.absoluteString == "x-apple.systempreferences:com.apple.Displays-Settings.extension"
    }

    #expect(displaysResults.count == 1)
    #expect(displaysResults[0].title == "ディスプレイ")
    #expect(displaysResults[0].searchTerms.contains("画面"))
}

@MainActor
@Test
func defaultSearchIncludesInstalledDisplaysExtension() async throws {
    let fileManager = FileManager.default
    let baseDirectoryURL = fileManager.temporaryDirectory
        .appending(path: "SagasuMacOSSettingsSearchIntegration-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? fileManager.removeItem(at: baseDirectoryURL) }

    let searchEngine = SearchEngine(
        clipboardStore: ClipboardHistoryStore(
            fileManager: fileManager,
            pasteboard: NSPasteboard.withUniqueName(),
            baseDirectoryURL: baseDirectoryURL
        ),
        herdrSearchService: nil
    )

    let results = try await searchEngine.search(
        for: ParsedSearchQuery(mode: .applications, query: "画面", clipboardImageOnly: false)
    )

    #expect(results.contains { result in
        guard case .openURL(let url) = result.action else { return false }
        return result.title == "ディスプレイ"
            && url.absoluteString == "x-apple.systempreferences:com.apple.Displays-Settings.extension"
    })
}
