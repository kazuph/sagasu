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
