import AppKit
import Foundation
import Testing
@testable import Sagasu

private func makeTempRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "SagasuPathTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.resolvingSymlinksInPath()
}

@Test
func pathExistingFileReturnsOpenAndCopyRows() throws {
    let root = try makeTempRoot()
    let file = root.appending(path: "note.txt")
    try "x".write(to: file, atomically: true, encoding: .utf8)

    let results = PathSearchService().search(query: file.path)

    #expect(results.count == 2)
    #expect(results[0].title == "note.txt")
    #expect(results[0].subtitle == root.path)
    #expect(results[0].detail == file.path)
    #expect(results[0].action == .openURL(file))
    #expect(results[1].title == "Copy File")
    #expect(results[1].subtitle == "note.txt")
    #expect(results[1].detail == file.path)
    #expect(results[1].action == .copyFile(file))
}

@Test
func pathTrailingSlashDirectoryListsVisibleChildrenSorted() throws {
    let root = try makeTempRoot()
    try "x".write(to: root.appending(path: "b.txt"), atomically: true, encoding: .utf8)
    try "x".write(to: root.appending(path: "a 10.txt"), atomically: true, encoding: .utf8)
    try "x".write(to: root.appending(path: "a 2.txt"), atomically: true, encoding: .utf8)
    try "x".write(to: root.appending(path: ".hidden"), atomically: true, encoding: .utf8)

    let results = PathSearchService().search(query: root.path + "/")

    #expect(results.count == 5)
    #expect(results[1].title == "Copy File")
    #expect(results.dropFirst(2).map(\.title) == ["a 2.txt", "a 10.txt", "b.txt"])
    #expect(results.contains { $0.title == ".hidden" } == false)
}

@Test
func pathDirectoryWithoutTrailingSlashDoesNotListChildren() throws {
    let root = try makeTempRoot()
    try "x".write(to: root.appending(path: "a.txt"), atomically: true, encoding: .utf8)

    let results = PathSearchService().search(query: root.path)

    #expect(results.count == 2)
}

@Test
func pathDirectoryListingIsCappedAtForty() throws {
    let root = try makeTempRoot()
    for index in 0..<50 {
        try "x".write(to: root.appending(path: "f\(index).txt"), atomically: true, encoding: .utf8)
    }

    let results = PathSearchService().search(query: root.path + "/")

    #expect(results.count == 42)
}

@Test
func pathPartialNameMatchesCaseInsensitivelyAndSkipsHidden() throws {
    let root = try makeTempRoot()
    try "x".write(to: root.appending(path: "Report-1.txt"), atomically: true, encoding: .utf8)
    try "x".write(to: root.appending(path: "report-2.txt"), atomically: true, encoding: .utf8)
    try "x".write(to: root.appending(path: "other.txt"), atomically: true, encoding: .utf8)
    try "x".write(to: root.appending(path: ".rc"), atomically: true, encoding: .utf8)

    let results = PathSearchService().search(query: root.path + "/REP")
    #expect(results.map(\.title) == ["Report-1.txt", "report-2.txt"])
    #expect(results.allSatisfy { if case .openURL = $0.action { return true } else { return false } })

    let all = PathSearchService().search(query: root.path + "/r")
    #expect(all.contains { $0.title == ".rc" } == false)

    let hidden = PathSearchService().search(query: root.path + "/.r")
    #expect(hidden.map(\.title) == [".rc"])
}

@Test
func pathBackslashEscapedSpaceIsRestored() throws {
    let root = try makeTempRoot()
    let file = root.appending(path: "my file.txt")
    try "x".write(to: file, atomically: true, encoding: .utf8)

    let results = PathSearchService().search(query: root.path + "/my\\ file.txt")

    #expect(results.first?.action == .openURL(file))
    #expect(results.count == 2)
}

@Test
func pathQuotedInputIsUnquoted() throws {
    let root = try makeTempRoot()
    let file = root.appending(path: "my file.txt")
    try "x".write(to: file, atomically: true, encoding: .utf8)

    #expect(PathSearchService().search(query: "\"\(file.path)\"").first?.action == .openURL(file))
    #expect(PathSearchService().search(query: "'\(file.path)'").first?.action == .openURL(file))
}

@Test
func pathFileURLIsPercentDecoded() throws {
    let root = try makeTempRoot()
    let file = root.appending(path: "a b.txt")
    try "x".write(to: file, atomically: true, encoding: .utf8)

    let results = PathSearchService().search(query: "file://" + root.path + "/a%20b.txt")

    #expect(results.first?.action == .openURL(file))
    #expect(results.first?.detail == file.path)
}

@Test
func pathTildeExpandsToHome() {
    let results = PathSearchService().search(query: "~")

    #expect(results.count == 2)
    #expect(results.first?.detail == (("~" as NSString).expandingTildeInPath))
}

@Test
func pathWithMissingParentReturnsEmpty() throws {
    let root = try makeTempRoot()

    #expect(PathSearchService().search(query: root.path + "/nope/deeper/file.txt").isEmpty)
}

@Test
@MainActor
func copyFileWritesFileURLToPasteboard() throws {
    let root = try makeTempRoot()
    let file = root.appending(path: "copy-me.txt")
    try "x".write(to: file, atomically: true, encoding: .utf8)
    let pasteboard = NSPasteboard(name: .init("sagasu-test-\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }

    try AppCoordinator.copyFile(file, to: pasteboard)

    let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]
    #expect(urls == [file])
    #expect(pasteboard.types?.contains(.fileURL) == true)
}

@Test
@MainActor
func mainMenuProvidesEditShortcuts() throws {
    let menu = AppCoordinator.makeMainMenu()
    let edit = try #require(menu.items.compactMap(\.submenu).first { $0.title == "Edit" })

    func item(_ action: String) throws -> NSMenuItem {
        try #require(edit.items.first { $0.action.map(NSStringFromSelector) == action })
    }

    let expectations: [(String, String, NSEvent.ModifierFlags)] = [
        ("undo:", "z", [.command]),
        ("redo:", "z", [.command, .shift]),
        ("cut:", "x", [.command]),
        ("copy:", "c", [.command]),
        ("paste:", "v", [.command]),
        ("selectAll:", "a", [.command])
    ]
    for (action, key, modifiers) in expectations {
        let found = try item(action)
        #expect(found.keyEquivalent == key)
        #expect(found.keyEquivalentModifierMask == modifiers)
        #expect(found.target == nil)
    }
}
