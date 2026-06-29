import Foundation
import Testing
@testable import Sagasu

@Test
func applicationSearchIncludesFinder() {
    let service = ApplicationSearchService()

    let results = service.search(query: "finder", limit: 10)

    #expect(results.contains { result in
        result.title == "Finder" &&
            result.detail == "/System/Library/CoreServices/Finder.app"
    })
}

@Test
func applicationSearchIncludesAppAddedAfterServiceCreation() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appending(path: "SagasuApplicationSearchServiceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
        try? fileManager.removeItem(at: root)
    }

    let service = ApplicationSearchService(fileManager: fileManager, roots: [root])

    #expect(service.search(query: "fresh", limit: 10).isEmpty)

    let appURL = root.appending(path: "Fresh Candidate.app", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: appURL, withIntermediateDirectories: true)

    let results = service.search(query: "fresh", limit: 10)

    #expect(results.contains { result in
        result.title == "Fresh Candidate" &&
            result.detail.hasSuffix("/Fresh Candidate.app")
    })
}
