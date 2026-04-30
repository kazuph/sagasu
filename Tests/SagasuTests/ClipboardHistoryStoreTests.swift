import AppKit
import Foundation
import Testing
@testable import Sagasu

@MainActor
@Test
func deleteClipboardEntryRemovesStoredTextEntry() throws {
    let fileManager = FileManager.default
    let baseDirectoryURL = try makeTemporaryClipboardStoreDirectory(fileManager: fileManager)
    defer { try? fileManager.removeItem(at: baseDirectoryURL) }

    let entry = ClipboardEntry(
        id: UUID(),
        contentHash: "text-hash",
        capturedAt: Date(),
        lastUsedAt: nil,
        pinnedAt: nil,
        content: .text("hello")
    )
    try seedClipboardStore(entries: [entry], at: baseDirectoryURL, fileManager: fileManager)

    let store = ClipboardHistoryStore(
        fileManager: fileManager,
        pasteboard: NSPasteboard.withUniqueName(),
        baseDirectoryURL: baseDirectoryURL
    )

    try store.delete(entryID: entry.id)

    #expect(store.entries.isEmpty)

    let persistedEntries = try loadPersistedEntries(at: baseDirectoryURL)
    #expect(persistedEntries.isEmpty)
}

@MainActor
@Test
func deleteClipboardEntryRemovesStoredImageFile() throws {
    let fileManager = FileManager.default
    let baseDirectoryURL = try makeTemporaryClipboardStoreDirectory(fileManager: fileManager)
    defer { try? fileManager.removeItem(at: baseDirectoryURL) }

    let payload = ClipboardImagePayload(
        filename: "image-entry.png",
        pixelWidth: 120,
        pixelHeight: 80
    )
    let entry = ClipboardEntry(
        id: UUID(),
        contentHash: "image-hash",
        capturedAt: Date(),
        lastUsedAt: nil,
        pinnedAt: nil,
        content: .image(payload)
    )
    try seedClipboardStore(entries: [entry], at: baseDirectoryURL, fileManager: fileManager)
    let imageDirectoryURL = baseDirectoryURL.appending(path: "clipboard-images", directoryHint: .isDirectory)
    let imageURL = imageDirectoryURL.appending(path: payload.filename)
    try Data("fake-image".utf8).write(to: imageURL, options: .atomic)

    let store = ClipboardHistoryStore(
        fileManager: fileManager,
        pasteboard: NSPasteboard.withUniqueName(),
        baseDirectoryURL: baseDirectoryURL
    )

    try store.delete(entryID: entry.id)

    #expect(store.entries.isEmpty)
    #expect(fileManager.fileExists(atPath: imageURL.path) == false)
}

private func makeTemporaryClipboardStoreDirectory(fileManager: FileManager) throws -> URL {
    let directoryURL = fileManager.temporaryDirectory
        .appending(path: "SagasuTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL
}

private func seedClipboardStore(entries: [ClipboardEntry], at baseDirectoryURL: URL, fileManager: FileManager) throws {
    try fileManager.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
    try fileManager.createDirectory(
        at: baseDirectoryURL.appending(path: "clipboard-images", directoryHint: .isDirectory),
        withIntermediateDirectories: true
    )

    let data = try JSONEncoder().encode(entries)
    try data.write(
        to: baseDirectoryURL.appending(path: "clipboard-history.json"),
        options: .atomic
    )
}

private func loadPersistedEntries(at baseDirectoryURL: URL) throws -> [ClipboardEntry] {
    let data = try Data(contentsOf: baseDirectoryURL.appending(path: "clipboard-history.json"))
    return try JSONDecoder().decode([ClipboardEntry].self, from: data)
}
