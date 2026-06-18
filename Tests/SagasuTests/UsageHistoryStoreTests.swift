import Foundation
import Testing
@testable import Sagasu

@Test
func usageHistoryPersistsLastUsedDate() throws {
    let fileManager = FileManager.default
    let baseDirectoryURL = fileManager.temporaryDirectory
        .appending(path: "SagasuUsageHistoryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)

    let key = "application:/Applications/Safari.app"
    let date = Date(timeIntervalSince1970: 1_700_000_000)

    let writer = UsageHistoryStore(fileManager: fileManager, baseDirectoryURL: baseDirectoryURL)
    try writer.markUsed(key: key, at: date)

    let reader = UsageHistoryStore(fileManager: fileManager, baseDirectoryURL: baseDirectoryURL)
    #expect(reader.lastUsedAt(for: key) == date)
}
