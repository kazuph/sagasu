import AppKit
import Foundation
import Testing
@testable import Sagasu

@Test
func calculatorEvaluatesBasicExpression() {
    let results = CalculatorSearchService().search(query: "1 + 2 * 3")

    #expect(results.count == 1)
    #expect(results[0].title == "7")
    #expect(results[0].subtitle == "1 + 2 * 3 = 7")
    #expect(results[0].detail == "Press Return to copy result")

    guard case .copyText(let text) = results[0].action else {
        Issue.record("Calculator result should copy the computed value")
        return
    }

    #expect(text == "7")
}

@Test
func calculatorSupportsParenthesesAndDecimalResults() {
    let results = CalculatorSearchService().search(query: "(10 - 2.5) / 3")

    #expect(results.map(\.title) == ["2.5"])
}

@Test
func calculatorSupportsRaycastStyleOperators() {
    let results = CalculatorSearchService().search(query: "2 x 3 + 8 ÷ 4")

    #expect(results.map(\.title) == ["8"])
}

@Test
func calculatorIgnoresPlainSearchTextAndInvalidMath() {
    let service = CalculatorSearchService()

    #expect(service.search(query: "safari").isEmpty)
    #expect(service.search(query: "42").isEmpty)
    #expect(service.search(query: "1 / 0").isEmpty)
    #expect(service.search(query: "1 +").isEmpty)
}

@MainActor
@Test
func calculatorResultIsFirstDefaultSearchResult() async throws {
    let fileManager = FileManager.default
    let baseDirectoryURL = fileManager.temporaryDirectory
        .appending(path: "SagasuCalculatorSearchEngineTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
    let clipboardStore = ClipboardHistoryStore(
        fileManager: fileManager,
        pasteboard: NSPasteboard.withUniqueName(),
        baseDirectoryURL: baseDirectoryURL
    )
    let searchEngine = SearchEngine(clipboardStore: clipboardStore)

    let results = try await searchEngine.search(
        for: ParsedSearchQuery(mode: .applications, query: "2 + 2", clipboardImageOnly: false)
    )

    #expect(results.first?.title == "4")
    guard case .copyText("4") = results.first?.action else {
        Issue.record("First result should copy calculator output")
        return
    }
}
