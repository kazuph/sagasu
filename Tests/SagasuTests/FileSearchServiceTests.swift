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

@Test
func fileRankingPutsHistoryURLAboveEquallyMatchingFile() throws {
    let baseDirectoryURL = FileManager.default.temporaryDirectory
        .appending(path: "SagasuFileRankingHistory-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
    let store = UsageHistoryStore(baseDirectoryURL: baseDirectoryURL)

    let plain = URL(fileURLWithPath: "/tmp/report-a.txt")
    let used = URL(fileURLWithPath: "/tmp/report-b.txt")
    try store.markUsed(key: UsageHistoryKey.url(used))

    let ranked = FileSearchService.rank(urls: [plain, used], query: "report", usageHistoryStore: store)
    #expect(ranked == [used, plain])

    let withoutHistory = FileSearchService.rank(urls: [plain, used], query: "report", usageHistoryStore: nil)
    #expect(withoutHistory == [plain, used])
}

@Test
func spotlightPathExclusionRules() {
    let home = "/Users/tester"
    func excluded(_ relative: String) -> Bool {
        FileSearchService.isExcludedSpotlightPath("\(home)/\(relative)", home: home)
    }

    #expect(excluded("src/project/main.swift") == false)
    #expect(excluded("Downloads/mathgirl-video") == false)
    #expect(excluded(".config/foo") == true)
    #expect(excluded("src/repo/.git/config") == true)
    #expect(excluded("src/.worktree/feat/x") == true)
    #expect(excluded("Library/Preferences/foo.plist") == true)
    #expect(excluded("Library/Application Support/x") == true)
    #expect(excluded("Library/CloudStorage/Dropbox/file.txt") == false)
    #expect(excluded("Library/Mobile Documents/com~apple~CloudDocs/doc.pdf") == false)
    #expect(excluded("Library/Mobile Documents/com~apple~Notes/doc") == true)
    #expect(excluded("Library/Recent Places/Foo") == false)
    #expect(excluded("src/app/node_modules/pkg/index.js") == true)
    #expect(excluded("src/app/node_modules") == true)
    #expect(FileSearchService.isExcludedSpotlightPath("/Volumes/X/.Trashes/a", home: home) == true)
}

@Test
func emptyFileSearchPutsRecentHistoryFirstAndDirectoryModeOnlyFolders() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appending(path: "SagasuRecentHistory-\(UUID().uuidString)", directoryHint: .isDirectory)
    let folder = root.appending(path: "Used Folder", directoryHint: .isDirectory)
    let other = root.appending(path: "Other Folder", directoryHint: .isDirectory)
    let file = root.appending(path: "used-file.txt")
    try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: other, withIntermediateDirectories: true)
    try "x".write(to: file, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_900_000_000)], ofItemAtPath: other.path)

    let storeDirectory = root.appending(path: "store", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    let store = UsageHistoryStore(baseDirectoryURL: storeDirectory)
    let now = Date()
    try store.markUsed(key: UsageHistoryKey.url(file), at: now)
    try store.markUsed(key: UsageHistoryKey.url(folder), at: now.addingTimeInterval(-60))
    try store.markUsed(key: UsageHistoryKey.url(root.appending(path: "gone.txt")), at: now.addingTimeInterval(-5))

    let service = FileSearchService(fileManager: fileManager, scopes: [root], commonDirectories: [])

    let files = try service.search(query: "", limit: 10, usageHistoryStore: store)
    #expect(files.prefix(2).map(\.title) == ["used-file.txt", "Used Folder"])
    #expect(files[0].subtitle.hasPrefix("最近使った · "))

    let directories = service.searchDirectories(query: "", limit: 10, usageHistoryStore: store)
    #expect(directories.first?.title == "Used Folder")
    #expect(directories.contains { $0.title == "used-file.txt" } == false)
}

@Test
func recentFolderCandidatesAreRankedWithHistory() throws {
    let baseDirectoryURL = FileManager.default.temporaryDirectory
        .appending(path: "SagasuRecentFolderRank-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
    let store = UsageHistoryStore(baseDirectoryURL: baseDirectoryURL)
    let plain = URL(fileURLWithPath: "/tmp/proj-a", isDirectory: true)
    let used = URL(fileURLWithPath: "/tmp/proj-b", isDirectory: true)
    try store.markUsed(key: UsageHistoryKey.url(used))

    let ranked = FileSearchService.rank(urls: [plain, used], query: "proj", usageHistoryStore: store)
    #expect(ranked.first == used)
}

@Test
func topRankedScoresEverythingBeforeApplyingLimit() throws {
    let baseDirectoryURL = FileManager.default.temporaryDirectory
        .appending(path: "SagasuTopRanked-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
    let store = UsageHistoryStore(baseDirectoryURL: baseDirectoryURL)
    var urls = (0..<50).map { URL(fileURLWithPath: "/tmp/dir\($0)/xx-notes-\($0).txt") }
    let exact = URL(fileURLWithPath: "/tmp/last/sagasu")
    urls.append(exact)

    let top = FileSearchService.topRanked(urls: urls, query: "sagasu", usageHistoryStore: store, limit: 3)
    #expect(top.count == 3)
    #expect(top.first == exact)
}

@Test
func fallbackRunsOnlyWhenMdfindReturnedNothingOrFailed() {
    #expect(FileSearchService.shouldFallback(rawLineCount: 0, mdfindFailed: false) == true)
    #expect(FileSearchService.shouldFallback(rawLineCount: 0, mdfindFailed: true) == true)
    #expect(FileSearchService.shouldFallback(rawLineCount: 1, mdfindFailed: false) == false)
    #expect(FileSearchService.shouldFallback(rawLineCount: 500, mdfindFailed: false) == false)
}

@Test
func metadataLiteralEscapesBackslashBeforeQuote() {
    #expect(FileSearchService.escapeMetadataLiteral(#"a"b"#) == #"a\"b"#)
    #expect(FileSearchService.escapeMetadataLiteral(#"a\b"#) == #"a\\b"#)
    #expect(FileSearchService.escapeMetadataLiteral(#"a\"b"#) == #"a\\\"b"#)
    #expect(FileSearchService.escapeMetadataLiteral("plain") == "plain")
}

@Test
func spotlightExclusionSkipsPackageInternals() {
    let home = "/Users/tester"
    func excluded(_ relative: String) -> Bool {
        FileSearchService.isExcludedSpotlightPath("\(home)/\(relative)", home: home)
    }

    #expect(excluded("Applications/Foo.app/Contents/Resources") == true)
    #expect(excluded("src/Some.framework/Versions/A") == true)
    #expect(excluded("src/Plugin.bundle/Contents") == true)
    #expect(excluded("src/Proj.xcodeproj/project.xcworkspace") == true)
    #expect(excluded("Pictures/Photos Library.photoslibrary/originals") == true)
    #expect(excluded("Applications/Foo.app") == false)
    #expect(excluded("src/folder.with.dots/file.txt") == false)
}

@Test
func searchWithQueryDoesNotPutUnrankedRecentFoldersAtTheTop() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appending(path: "SagasuNoUnrankedRecent-\(UUID().uuidString)", directoryHint: .isDirectory)
    let matchA = root.appending(path: "proj-old-a", directoryHint: .isDirectory)
    let matchB = root.appending(path: "proj-used-b", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: matchA, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: matchB, withIntermediateDirectories: true)
    // 履歴の無いほうを新しく更新し、recentFolders の並びでは A が先になる状態にする。
    try fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: matchA.path)
    try fileManager.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)], ofItemAtPath: matchB.path)

    let store = UsageHistoryStore(baseDirectoryURL: root.appending(path: "store", directoryHint: .isDirectory))
    try store.markUsed(key: UsageHistoryKey.url(matchB))

    // spotlightScopes は存在しないパス（mdfind は0件）なので、fallback 経路を通る。
    let missing = root.appending(path: "does-not-exist", directoryHint: .isDirectory)
    let service = FileSearchService(
        fileManager: fileManager,
        scopes: [root],
        commonDirectories: [],
        spotlightScopes: [missing]
    )

    let directories = service.searchDirectories(query: "proj", limit: 10, usageHistoryStore: store)
    #expect(directories.prefix(2).map(\.title) == ["proj-used-b", "proj-old-a"])
}

@Test
func fileSearchWithQueryKeepsOnlyCommonDirectoriesFixedAtTheTop() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appending(path: "SagasuFixedCommonTop-\(UUID().uuidString)", directoryHint: .isDirectory)
    let common = root.appending(path: "proj-common", directoryHint: .isDirectory)
    let recent = root.appending(path: "proj-recent", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: common, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: recent, withIntermediateDirectories: true)

    let store = UsageHistoryStore(baseDirectoryURL: root.appending(path: "store", directoryHint: .isDirectory))
    let missing = root.appending(path: "does-not-exist", directoryHint: .isDirectory)
    let service = FileSearchService(
        fileManager: fileManager,
        scopes: [root],
        commonDirectories: [common],
        spotlightScopes: [missing]
    )

    let results = try service.search(query: "proj", limit: 10, usageHistoryStore: store)
    #expect(results.first?.title == "proj-common")
    #expect(results.filter { $0.title == "proj-common" }.count == 1)
}
