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

@Test
func applicationSearchFindsLocalizedAppNameWithoutLosingFileNameOrBundleIDMatches() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appending(path: "SagasuLocalizedApplicationSearch-\(UUID().uuidString)", directoryHint: .isDirectory)
    let appURL = root.appending(path: "FindMy.app", directoryHint: .isDirectory)
    let contentsURL = appURL.appending(path: "Contents", directoryHint: .isDirectory)
    let resourcesURL = contentsURL.appending(path: "Resources", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
    defer {
        try? fileManager.removeItem(at: root)
    }

    let infoPlist: NSDictionary = [
        "CFBundleIdentifier": "com.apple.findmy",
        "CFBundleName": "FindMy",
        "CFBundleDisplayName": "FindMy",
        "CFBundleExecutable": "FindMy",
        "CFBundlePackageType": "APPL"
    ]
    infoPlist.write(to: contentsURL.appending(path: "Info.plist"), atomically: true)

    let localizationTable: NSDictionary = [
        "ja": [
            "CFBundleDisplayName": "探す",
            "CFBundleName": "探す",
            "APP_NAME_SYNONYM_1": "iPhoneを探す",
            "kMDItemKeywords": "Find My, iPhoneを探す, 友達を探す"
        ]
    ]
    localizationTable.write(to: resourcesURL.appending(path: "InfoPlist.loctable"), atomically: true)

    let service = ApplicationSearchService(fileManager: fileManager, roots: [root], preferredLanguages: ["ja"])

    let localizedResults = service.search(query: "探す", limit: 10)
    #expect(localizedResults.contains { result in
        result.title == "探す" &&
            result.subtitle == "com.apple.findmy" &&
            result.detail.hasSuffix("/FindMy.app")
    })

    let fileNameResults = service.search(query: "FindMy", limit: 10)
    #expect(fileNameResults.contains { result in
        result.title == "探す" &&
            result.subtitle == "com.apple.findmy" &&
            result.detail.hasSuffix("/FindMy.app")
    })

    let bundleIDResults = service.search(query: "com.apple.findmy", limit: 10)
    #expect(bundleIDResults.contains { result in
        result.title == "探す" &&
            result.subtitle == "com.apple.findmy" &&
            result.detail.hasSuffix("/FindMy.app")
    })
}

private func makeFakeApplication(named name: String, in root: URL) throws -> URL {
    let appURL = root.appending(path: "\(name).app", directoryHint: .isDirectory)
    let contentsURL = appURL.appending(path: "Contents", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
    let infoPlist: NSDictionary = [
        "CFBundleIdentifier": "test.\(name.lowercased())",
        "CFBundleName": name,
        "CFBundleDisplayName": name,
        "CFBundleExecutable": name,
        "CFBundlePackageType": "APPL"
    ]
    infoPlist.write(to: contentsURL.appending(path: "Info.plist"), atomically: true)
    return appURL
}

@Test
func emptyApplicationSearchPutsRecentlyUsedApplicationsFirst() throws {
    let fileManager = FileManager.default
    let root = canonicalTemporaryRoot()
        .appending(path: "SagasuRecentApps-\(UUID().uuidString)", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    let alpha = try makeFakeApplication(named: "Alpha", in: root)
    _ = try makeFakeApplication(named: "Bravo", in: root)
    let charlie = try makeFakeApplication(named: "Charlie", in: root)

    let store = UsageHistoryStore(baseDirectoryURL: root.appending(path: "store", directoryHint: .isDirectory))
    let now = Date()
    try store.markUsed(key: UsageHistoryKey.application(alpha), at: now.addingTimeInterval(-100))
    try store.markUsed(key: UsageHistoryKey.application(charlie), at: now)

    let service = ApplicationSearchService(fileManager: fileManager, roots: [root])
    let results = service.search(query: "", limit: 10, usageHistoryStore: store, runningBundleIdentifiers: ["test.bravo"])

    #expect(results.map(\.title).prefix(3) == ["Charlie", "Alpha", "Bravo"])
    #expect(results[0].subtitle == "最近使った · test.charlie")
    #expect(results.filter { $0.title == "Alpha" }.count == 1)
    #expect(results[2].subtitle == "test.bravo")
}

@Test
func applicationSearchRanksUsedApplicationAboveEquallyMatchingOne() throws {
    let fileManager = FileManager.default
    let root = canonicalTemporaryRoot()
        .appending(path: "SagasuUsedAppRanking-\(UUID().uuidString)", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    _ = try makeFakeApplication(named: "Editor A", in: root)
    let used = try makeFakeApplication(named: "Editor Z", in: root)

    let store = UsageHistoryStore(baseDirectoryURL: root.appending(path: "store", directoryHint: .isDirectory))
    try store.markUsed(key: UsageHistoryKey.application(used))

    let service = ApplicationSearchService(fileManager: fileManager, roots: [root])
    let results = service.search(query: "editor", limit: 10, usageHistoryStore: store, runningBundleIdentifiers: [])

    #expect(results.map(\.title).prefix(2) == ["Editor Z", "Editor A"])
}

/// FileManager の列挙は /private/var 形式のパスを返すため、キーと一致するよう揃える。
private func canonicalTemporaryRoot() -> URL {
    let base = FileManager.default.temporaryDirectory
    if base.path.hasPrefix("/var/") {
        return URL(fileURLWithPath: "/private" + base.path, isDirectory: true)
    }
    return base
}
