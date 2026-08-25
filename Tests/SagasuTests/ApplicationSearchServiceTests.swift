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
