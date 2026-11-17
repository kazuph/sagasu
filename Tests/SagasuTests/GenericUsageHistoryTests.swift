import AppKit
import Foundation
import Testing
@testable import Sagasu

private func makeStore() throws -> (UsageHistoryStore, URL) {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "SagasuGenericHistory-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return (UsageHistoryStore(baseDirectoryURL: directory), directory)
}

private func settingResult(_ title: String, id: String) -> SearchResult {
    SearchResult(
        title: title,
        subtitle: "macOS Settings",
        detail: id,
        visual: .symbol("gearshape"),
        action: .openURL(URL(string: "x-apple.systempreferences:\(id)")!)
    )
}

@Test
func historyKeysAreDefinedForEveryAction() {
    let appURL = URL(fileURLWithPath: "/Applications/Safari.app")
    let fileURL = URL(fileURLWithPath: "/Users/tester/doc.txt")
    #expect(UsageHistoryKey.key(for: .launchApplication(appURL)) == "application:/Applications/Safari.app")
    #expect(UsageHistoryKey.key(for: .openURL(fileURL)) == "url:/Users/tester/doc.txt")
    #expect(UsageHistoryKey.key(for: .openURL(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!))
        == "url:com.apple.Displays-Settings.extension")
    #expect(UsageHistoryKey.key(for: .openURLInPreferredBrowser(URL(string: "https://example.com/?q=1")!, bundleIdentifier: "com.google.Chrome"))
        == "browser:https://example.com/?q=1")
    #expect(UsageHistoryKey.key(for: .openNote("note-1")) == "note:note-1")
    #expect(UsageHistoryKey.key(for: .restoreClipboard(UUID())) == nil)
    #expect(UsageHistoryKey.key(for: .saveClipboardImage) == "command:saveClipboardImage")
    #expect(UsageHistoryKey.key(for: .extractTextFromClipboardImage) == "command:extractTextFromClipboardImage")
    #expect(UsageHistoryKey.key(for: .focusTerminalPane("pane-9")) == "pane:pane-9")
    #expect(UsageHistoryKey.key(for: .configureLinearAPIKey) == "command:configureLinearAPIKey")
    #expect(UsageHistoryKey.key(for: .copyText("42")) == "text:42")
    #expect(UsageHistoryKey.key(for: .copyFile(fileURL)) == "copyfile:/Users/tester/doc.txt")
}

@Test
func snapshotIsPersistedAndReloaded() throws {
    let (store, directory) = try makeStore()
    let result = SearchResult(
        title: "Ask ChatGPT in Chrome",
        subtitle: "hello",
        detail: "chatgpt.com",
        visual: .symbol("sparkles"),
        action: .openURLInPreferredBrowser(URL(string: "https://chatgpt.com/?prompt=hello")!, bundleIdentifier: "com.google.Chrome"),
        searchTerms: "ai chat"
    )
    let key = try #require(UsageHistoryKey.key(for: result.action))
    try store.markUsed(key: key, snapshot: UsageHistoryStore.Snapshot(result: result))

    let reloaded = UsageHistoryStore(baseDirectoryURL: directory)
    let snapshot = try #require(reloaded.snapshot(for: key))
    #expect(snapshot == UsageHistoryStore.Snapshot(result: result))
    let restored = snapshot.makeResult(subtitlePrefix: "最近使った · ")
    #expect(restored.title == result.title)
    #expect(restored.subtitle == "最近使った · hello")
    #expect(restored.action == result.action)
    #expect(restored.visual == result.visual)
    #expect(restored.searchTerms == "ai chat")

    // スナップショット無しの記録で、既存の写しを消さない。
    try reloaded.markUsed(key: key)
    #expect(reloaded.snapshot(for: key) != nil)
}

@Test
func oldFormatHistoryFileStillLoads() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "SagasuOldHistory-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let json = #"{"entries":{"url:com.apple.Displays-Settings.extension":784000000.5,"application:/Applications/Safari.app":784000100}}"#
    try json.write(to: directory.appending(path: "usage-history.json"), atomically: true, encoding: .utf8)

    let store = UsageHistoryStore(baseDirectoryURL: directory)
    #expect(store.lastUsedAt(for: "url:com.apple.Displays-Settings.extension") == Date(timeIntervalSinceReferenceDate: 784_000_000.5))
    #expect(store.snapshot(for: "url:com.apple.Displays-Settings.extension") == nil)
    #expect(store.recentEntries().map(\.key) == ["application:/Applications/Safari.app", "url:com.apple.Displays-Settings.extension"])

    // 書き戻しても既存の記録を失わない。
    try store.markUsed(key: "pane:1")
    let reloaded = UsageHistoryStore(baseDirectoryURL: directory)
    #expect(reloaded.lastUsedAt(for: "url:com.apple.Displays-Settings.extension") != nil)
}

@Test
func usedSettingRanksAboveEquallyMatchingSettingWithQuery() throws {
    let (store, directory) = try makeStore()
    let emptyRoot = directory.appending(path: "apps", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: emptyRoot, withIntermediateDirectories: true)
    let first = settingResult("Xa Settings", id: "xa")
    let second = settingResult("Xb Settings", id: "xb")
    let service = ApplicationSearchService(roots: [emptyRoot])

    let before = service.search(query: "settings", limit: 10, usageHistoryStore: store, additionalResults: [first, second], runningBundleIdentifiers: [])
    #expect(before.map(\.title) == ["Xa Settings", "Xb Settings"])

    try store.markUsed(key: try #require(UsageHistoryKey.key(for: second.action)))
    let after = service.search(query: "settings", limit: 10, usageHistoryStore: store, additionalResults: [first, second], runningBundleIdentifiers: [])
    #expect(after.map(\.title) == ["Xb Settings", "Xa Settings"])
}

@Test
func emptyQueryRecentSectionShowsSettingsFromSnapshotAndFromLegacyRecord() throws {
    let (store, directory) = try makeStore()
    let emptyRoot = directory.appending(path: "apps", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: emptyRoot, withIntermediateDirectories: true)
    let displays = settingResult("Displays", id: "com.apple.Displays-Settings.extension")
    let sound = settingResult("Sound", id: "com.apple.Sound-Settings.extension")
    let other = settingResult("Other", id: "com.apple.Other-Settings.extension")
    let now = Date()
    // 写しのある記録（新しい）と、写しの無い古い形式の記録。
    try store.markUsed(key: try #require(UsageHistoryKey.key(for: sound.action)), at: now, snapshot: UsageHistoryStore.Snapshot(result: sound))
    try store.markUsed(key: try #require(UsageHistoryKey.key(for: displays.action)), at: now.addingTimeInterval(-60))
    let command = SearchResult(title: "Image: Save Clipboard Image", subtitle: "Save PNG", detail: "~/Downloads", visual: .symbol("x"), action: .saveClipboardImage)
    try store.markUsed(key: "command:saveClipboardImage", at: now.addingTimeInterval(-120), snapshot: UsageHistoryStore.Snapshot(result: command))

    let service = ApplicationSearchService(roots: [emptyRoot])
    let results = service.search(
        query: "",
        limit: 20,
        usageHistoryStore: store,
        additionalResults: [command],
        legacyLookupResults: [displays, sound, other],
        runningBundleIdentifiers: []
    )

    #expect(results.map(\.title) == ["Sound", "Displays", "Image: Save Clipboard Image"])
    #expect(results[0].subtitle == "最近使った · macOS Settings")
    #expect(results[1].subtitle == "最近使った · macOS Settings")
    #expect(results[2].subtitle == "最近使った · Save PNG")
    #expect(results.filter { $0.title == "Image: Save Clipboard Image" }.count == 1)
}

@Test
func emptyQueryRecentSectionSkipsMissingFilesButKeepsExistingOnes() throws {
    let (store, directory) = try makeStore()
    let emptyRoot = directory.appending(path: "apps", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: emptyRoot, withIntermediateDirectories: true)
    let existing = directory.appending(path: "exists.txt")
    try "x".write(to: existing, atomically: true, encoding: .utf8)
    let missing = directory.appending(path: "missing.txt")
    let now = Date()
    for (url, offset) in [(existing, 0.0), (missing, 10.0)] {
        let result = SearchResult(title: url.lastPathComponent, subtitle: "dir", detail: url.path, visual: .fileIcon(url), action: .openURL(url))
        try store.markUsed(key: UsageHistoryKey.url(url), at: now.addingTimeInterval(offset), snapshot: UsageHistoryStore.Snapshot(result: result))
    }

    let results = ApplicationSearchService(roots: [emptyRoot])
        .search(query: "", limit: 10, usageHistoryStore: store, runningBundleIdentifiers: [])
    #expect(results.map(\.title) == ["exists.txt"])
}

@Test
func promoteUsedMovesUsedItemsFirstAndKeepsOtherOrderStable() throws {
    let (store, _) = try makeStore()
    let items = (1...5).map { index in
        SearchResult(title: "Item \(index)", subtitle: "", detail: "", visual: .symbol("x"), action: .openNote("n\(index)"))
    }
    let now = Date()
    try store.markUsed(key: "note:n4", at: now)
    try store.markUsed(key: "note:n2", at: now.addingTimeInterval(-10))

    let promoted = SearchEngine.promoteUsed(items, usageHistoryStore: store)
    #expect(promoted.map(\.title) == ["Item 4", "Item 2", "Item 1", "Item 3", "Item 5"])

    let untouched = SearchEngine.promoteUsed(items, usageHistoryStore: try makeStore().0)
    #expect(untouched.map(\.title) == items.map(\.title))
}

@MainActor
@Test
func markUsedStoresSnapshotButNeverRecordsRestoreClipboard() throws {
    let (store, directory) = try makeStore()
    let clipboardStore = ClipboardHistoryStore(
        fileManager: .default,
        pasteboard: NSPasteboard.withUniqueName(),
        baseDirectoryURL: directory.appending(path: "clip", directoryHint: .isDirectory)
    )
    let engine = SearchEngine(clipboardStore: clipboardStore, usageHistoryStore: store)

    let restore = SearchResult(title: "clip", subtitle: "", detail: "", visual: .symbol("x"), action: .restoreClipboard(UUID()))
    try engine.markUsed(result: restore)
    #expect(store.recentEntries().isEmpty)

    let pane = SearchResult(title: "Pane", subtitle: "agent", detail: "d", visual: .symbol("terminal"), action: .focusTerminalPane("p1"))
    try engine.markUsed(result: pane)
    #expect(store.recentEntries().map(\.key) == ["pane:p1"])
    #expect(store.snapshot(for: "pane:p1")?.title == "Pane")
}

@Test
func recentPrefixDoesNotStackWhenRecentItemIsSelectedAgain() throws {
    let (store, directory) = try makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    let base = settingResult("ディスプレイ", id: "com.apple.Displays-Settings.extension")
    let shownAsRecent = SearchResult(
        title: base.title,
        subtitle: UsageHistoryStore.recentSubtitlePrefix + UsageHistoryStore.recentSubtitlePrefix + base.subtitle,
        detail: base.detail,
        visual: base.visual,
        action: base.action
    )
    let key = try #require(UsageHistoryKey.key(for: shownAsRecent.action))
    try store.markUsed(key: key, snapshot: UsageHistoryStore.Snapshot(result: shownAsRecent))
    let reloaded = UsageHistoryStore(baseDirectoryURL: directory)
    #expect(reloaded.snapshot(for: key)?.subtitle == "macOS Settings")
    #expect(reloaded.snapshot(for: key)?.makeResult(subtitlePrefix: UsageHistoryStore.recentSubtitlePrefix).subtitle
        == "最近使った · macOS Settings")
}

@Test
func historyIsCappedAndApplicationSnapshotsAreNotStored() throws {
    let (store, directory) = try makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    let start = Date(timeIntervalSince1970: 1_000_000)
    for index in 0..<(UsageHistoryStore.maximumEntryCount + 5) {
        let result = settingResult("item\(index)", id: "id\(index)")
        let key = try #require(UsageHistoryKey.key(for: result.action))
        try store.markUsed(key: key, at: start.addingTimeInterval(Double(index)), snapshot: UsageHistoryStore.Snapshot(result: result))
    }
    let reloaded = UsageHistoryStore(baseDirectoryURL: directory)
    #expect(reloaded.recentEntries().count == UsageHistoryStore.maximumEntryCount)
    #expect(reloaded.lastUsedAt(for: "url:id0") == nil)
    #expect(reloaded.snapshot(for: "url:id0") == nil)
    #expect(reloaded.snapshot(for: "url:id\(UsageHistoryStore.maximumEntryCount + 4)") != nil)

    let appURL = URL(fileURLWithPath: "/Applications/Safari.app")
    let app = SearchResult(title: "Safari", subtitle: "com.apple.Safari", detail: appURL.path, visual: .fileIcon(appURL), action: .launchApplication(appURL))
    try store.markUsed(key: UsageHistoryKey.application(appURL), snapshot: UsageHistoryStore.Snapshot(result: app))
    #expect(store.snapshot(for: UsageHistoryKey.application(appURL)) == nil)
    #expect(store.lastUsedAt(for: UsageHistoryKey.application(appURL)) != nil)
}

@Test
func brokenSnapshotDoesNotDropHistoryEntries() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "SagasuGenericHistory-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let json = """
    {"entries":{"url:a":800000000,"url:b":800000001},
     "snapshots":{"url:a":{"title":"A","subtitle":"s","detail":"d","visual":{"futureCase":{}},"action":{"futureCase":{}},"searchTerms":""},
                  "url:b":{"title":"B","subtitle":"s","detail":"d","visual":{"symbol":{"_0":"gearshape"}},"action":{"openNote":{"_0":"n"}},"searchTerms":""}}}
    """
    try Data(json.utf8).write(to: directory.appending(path: "usage-history.json"))
    let store = UsageHistoryStore(baseDirectoryURL: directory)
    #expect(store.lastUsedAt(for: "url:a") != nil)
    #expect(store.snapshot(for: "url:a") == nil)
    #expect(store.snapshot(for: "url:b")?.title == "B")
}
