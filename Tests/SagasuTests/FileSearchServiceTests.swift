import Foundation
import Testing
@testable import Sagasu

@Test
func emptyFileSearchReturnsRecentlyModifiedFolders() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appending(path: "SagasuFileSearchTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let older = root.appending(path: "Older Folder", directoryHint: .isDirectory)
    let newer = root.appending(path: "Newer Folder", directoryHint: .isDirectory)
    let file = root.appending(path: "not-a-folder.txt")

    try fileManager.createDirectory(at: older, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: newer, withIntermediateDirectories: true)
    try "file".write(to: file, atomically: true, encoding: .utf8)

    let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
    let newDate = Date(timeIntervalSince1970: 1_800_000_000)
    try fileManager.setAttributes([.modificationDate: oldDate], ofItemAtPath: older.path)
    try fileManager.setAttributes([.modificationDate: newDate], ofItemAtPath: newer.path)

    let service = FileSearchService(fileManager: fileManager, scopes: [root])
    let results = try service.search(query: "", limit: 10)

    #expect(results.map(\.title).prefix(2) == ["Newer Folder", "Older Folder"])
    #expect(results.contains { $0.title == "not-a-folder.txt" } == false)
}

@Test
func fileSearchPrioritizesCommonDirectories() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appending(path: "SagasuCommonDirectoryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let downloads = root.appending(path: "Downloads", directoryHint: .isDirectory)
    let documents = root.appending(path: "Documents", directoryHint: .isDirectory)
    let decoyFile = root.appending(path: "download-notes.txt")

    try fileManager.createDirectory(at: downloads, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: documents, withIntermediateDirectories: true)
    try "file".write(to: decoyFile, atomically: true, encoding: .utf8)

    let service = FileSearchService(
        fileManager: fileManager,
        scopes: [root],
        commonDirectories: [downloads, documents]
    )

    let results = try service.search(query: "d", limit: 10)

    #expect(results.prefix(2).map(\.title) == ["Downloads", "Documents"])
}

@Test
func directorySearchOnlyReturnsDirectories() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appending(path: "SagasuDirectoryOnlyTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let downloads = root.appending(path: "Downloads", directoryHint: .isDirectory)
    let decoyFile = root.appending(path: "Downloads.txt")

    try fileManager.createDirectory(at: downloads, withIntermediateDirectories: true)
    try "file".write(to: decoyFile, atomically: true, encoding: .utf8)

    let service = FileSearchService(
        fileManager: fileManager,
        scopes: [root],
        commonDirectories: [downloads]
    )

    let results = service.searchDirectories(query: "down", limit: 10)

    #expect(results.map(\.title) == ["Downloads"])
}
