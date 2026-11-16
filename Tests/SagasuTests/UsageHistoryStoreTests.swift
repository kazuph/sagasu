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

private func makeTemporaryHistoryStore() throws -> UsageHistoryStore {
    let baseDirectoryURL = FileManager.default.temporaryDirectory
        .appending(path: "SagasuUsageHistoryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
    return UsageHistoryStore(baseDirectoryURL: baseDirectoryURL)
}

@Test
func recencyBoostDecaysTenPointsPerDayAndStopsAtFiftyDays() throws {
    let store = try makeTemporaryHistoryStore()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    try store.markUsed(key: "k-today", at: now)
    try store.markUsed(key: "k-10", at: now.addingTimeInterval(-10 * 86_400))
    try store.markUsed(key: "k-50", at: now.addingTimeInterval(-50 * 86_400))
    try store.markUsed(key: "k-80", at: now.addingTimeInterval(-80 * 86_400))

    #expect(store.recencyBoost(for: "k-today", now: now) == 500)
    #expect(store.recencyBoost(for: "k-10", now: now) == 400)
    #expect(store.recencyBoost(for: "k-50", now: now) == 0)
    #expect(store.recencyBoost(for: "k-80", now: now) == 0)
    #expect(store.recencyBoost(for: "unknown", now: now) == 0)
}

@Test
func recentKeysFiltersByPrefixNewestFirst() throws {
    let store = try makeTemporaryHistoryStore()
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    try store.markUsed(key: "application:/A.app", at: base)
    try store.markUsed(key: "url:/old", at: base.addingTimeInterval(-300))
    try store.markUsed(key: "application:/B.app", at: base.addingTimeInterval(100))
    try store.markUsed(key: "url:/new", at: base.addingTimeInterval(200))

    #expect(store.recentKeys(withPrefix: "application:") == ["application:/B.app", "application:/A.app"])
    #expect(store.recentKeys(withPrefix: "url:") == ["url:/new", "url:/old"])
    #expect(store.recentKeys(withPrefix: "url:", limit: 1) == ["url:/new"])
}
