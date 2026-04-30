import AppKit
import CryptoKit
import Foundation

struct ClipboardImagePayload: Codable, Hashable {
    let filename: String
    let pixelWidth: Int
    let pixelHeight: Int
}

struct ClipboardEntry: Codable, Hashable, Identifiable {
    enum Content: Codable, Hashable {
        case text(String)
        case image(ClipboardImagePayload)
    }

    let id: UUID
    let contentHash: String
    let capturedAt: Date
    var lastUsedAt: Date?
    var pinnedAt: Date?
    let content: Content

    var isPinned: Bool {
        pinnedAt != nil
    }

    var sortDate: Date {
        lastUsedAt ?? capturedAt
    }

    func expirationDate(calendar: Calendar = .current) -> Date? {
        guard isPinned == false else { return nil }

        let defaultExpiry = calendar.date(byAdding: .month, value: 3, to: capturedAt) ?? capturedAt
        guard let lastUsedAt else { return defaultExpiry }

        let extendedExpiry = calendar.date(byAdding: .month, value: 6, to: lastUsedAt) ?? lastUsedAt
        return max(defaultExpiry, extendedExpiry)
    }

    func isExpired(asOf date: Date, calendar: Calendar = .current) -> Bool {
        guard let expirationDate = expirationDate(calendar: calendar) else { return false }
        return expirationDate < date
    }
}

private struct LegacyClipboardEntry: Codable {
    let id: UUID
    let text: String
    let capturedAt: Date
}

private struct CapturedClipboardImage {
    let contentHash: String
    let pngData: Data
    let pixelWidth: Int
    let pixelHeight: Int
}

@MainActor
final class ClipboardHistoryStore: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry] = []
    @Published private(set) var lastErrorMessage: String?

    private let pasteboard: NSPasteboard
    private let fileManager: FileManager
    private let maxEntries = 500
    private let baseDirectoryURL: URL
    private let storageURL: URL
    private let imageDirectoryURL: URL
    private var monitorTask: Task<Void, Never>?
    private var lastObservedChangeCount: Int

    init(
        fileManager: FileManager = .default,
        pasteboard: NSPasteboard = .general,
        baseDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.pasteboard = pasteboard

        let resolvedBaseDirectoryURL: URL
        if let baseDirectoryURL {
            resolvedBaseDirectoryURL = baseDirectoryURL
        } else {
            let appSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            resolvedBaseDirectoryURL = appSupportDirectory
                .appending(path: "Sagasu", directoryHint: .isDirectory)
        }

        self.baseDirectoryURL = resolvedBaseDirectoryURL
        storageURL = resolvedBaseDirectoryURL.appending(path: "clipboard-history.json")
        imageDirectoryURL = resolvedBaseDirectoryURL.appending(path: "clipboard-images", directoryHint: .isDirectory)
        lastObservedChangeCount = pasteboard.changeCount

        do {
            try load()
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        monitorTask = Task { @MainActor [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(for: .milliseconds(800))
                guard let self else { return }
                self.captureIfNeeded()
            }
        }
    }

    func search(query: String, imageOnly: Bool = false, limit: Int = 60) -> [SearchResult] {
        do {
            try persistState()
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        let normalizedQuery = SearchMatcher.normalize(query)

        return entries
            .sorted(by: sortEntries)
            .compactMap { entry in
                if imageOnly, entry.isImage == false {
                    return nil
                }

                let primary = SearchMatcher.normalize(displayTitle(for: entry))
                let secondary = SearchMatcher.normalize(searchMetadata(for: entry))

                if normalizedQuery.isEmpty == false,
                   SearchMatcher.score(
                    query: normalizedQuery,
                    primaryText: primary,
                    secondaryText: secondary
                   ) == nil {
                    return nil
                }

                return makeSearchResult(for: entry)
            }
            .prefix(limit)
            .map { $0 }
    }

    func restore(entryID: UUID) throws {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else {
            throw LauncherError.clipboardEntryUnavailable
        }

        switch entries[index].content {
        case .text(let text):
            pasteboard.clearContents()
            guard pasteboard.setString(text, forType: .string) else {
                throw LauncherError.clipboardWriteFailed
            }

        case .image(let payload):
            let imageURL = imageDirectoryURL.appending(path: payload.filename)
            guard fileManager.fileExists(atPath: imageURL.path),
                  let image = NSImage(contentsOf: imageURL) else {
                throw LauncherError.clipboardImageMissing
            }

            pasteboard.clearContents()
            guard pasteboard.writeObjects([image]) else {
                throw LauncherError.clipboardWriteFailed
            }
        }

        entries[index].lastUsedAt = Date()
        lastObservedChangeCount = pasteboard.changeCount
        try persistState()
    }

    func togglePin(entryID: UUID) throws {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else {
            throw LauncherError.clipboardEntryUnavailable
        }

        entries[index].pinnedAt = entries[index].isPinned ? nil : Date()
        try persistState()
    }

    func delete(entryID: UUID) throws {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else {
            throw LauncherError.clipboardEntryUnavailable
        }

        entries.remove(at: index)
        try persistState()
    }

    private func captureIfNeeded() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastObservedChangeCount else { return }
        lastObservedChangeCount = changeCount

        do {
            if let capturedImage = readImageFromPasteboard() {
                try insert(image: capturedImage)
                return
            }

            if let capturedText = readTextFromPasteboard() {
                try insert(text: capturedText)
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            fputs("Sagasu clipboard persistence error: \(error.localizedDescription)\n", stderr)
        }
    }

    private func readTextFromPasteboard() -> String? {
        guard let content = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              content.isEmpty == false else {
            return nil
        }

        return content
    }

    private func readImageFromPasteboard() -> CapturedClipboardImage? {
        guard let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage,
              let pngData = image.pngData(),
              let bitmap = NSBitmapImageRep(data: pngData) else {
            return nil
        }

        return CapturedClipboardImage(
            contentHash: Self.hash(for: pngData),
            pngData: pngData,
            pixelWidth: bitmap.pixelsWide,
            pixelHeight: bitmap.pixelsHigh
        )
    }

    private func insert(text: String) throws {
        let contentHash = Self.hash(for: Data(text.utf8))
        let existingEntry = removeExistingEntry(withContentHash: contentHash)
        let entry = ClipboardEntry(
            id: existingEntry?.id ?? UUID(),
            contentHash: contentHash,
            capturedAt: Date(),
            lastUsedAt: existingEntry?.lastUsedAt,
            pinnedAt: existingEntry?.pinnedAt,
            content: .text(text)
        )

        entries.insert(entry, at: 0)
        try persistState()
    }

    private func insert(image: CapturedClipboardImage) throws {
        let existingEntry = removeExistingEntry(withContentHash: image.contentHash)
        let entryID = existingEntry?.id ?? UUID()
        let filename: String

        if case .image(let existingPayload) = existingEntry?.content {
            filename = existingPayload.filename
        } else {
            filename = "\(entryID.uuidString).png"
        }

        try fileManager.createDirectory(at: imageDirectoryURL, withIntermediateDirectories: true)
        let fileURL = imageDirectoryURL.appending(path: filename)
        try image.pngData.write(to: fileURL, options: [.atomic])

        let payload = ClipboardImagePayload(
            filename: filename,
            pixelWidth: image.pixelWidth,
            pixelHeight: image.pixelHeight
        )

        let entry = ClipboardEntry(
            id: entryID,
            contentHash: image.contentHash,
            capturedAt: Date(),
            lastUsedAt: existingEntry?.lastUsedAt,
            pinnedAt: existingEntry?.pinnedAt,
            content: .image(payload)
        )

        entries.insert(entry, at: 0)
        try persistState()
    }

    private func removeExistingEntry(withContentHash contentHash: String) -> ClipboardEntry? {
        guard let existingIndex = entries.firstIndex(where: { $0.contentHash == contentHash }) else {
            return nil
        }

        return entries.remove(at: existingIndex)
    }

    private func makeSearchResult(for entry: ClipboardEntry) -> SearchResult {
        switch entry.content {
        case .text(let text):
            let preview = text.replacingOccurrences(of: "\n", with: " ")
            return SearchResult(
                title: preview.truncated(limit: 80),
                subtitle: statusText(for: entry),
                detail: preview,
                visual: .symbol(entry.isPinned ? "pin.fill" : "doc.on.clipboard"),
                action: .restoreClipboard(entry.id)
            )

        case .image(let payload):
            let imageURL = imageDirectoryURL.appending(path: payload.filename)
            return SearchResult(
                title: "Clipboard Image \(payload.pixelWidth)×\(payload.pixelHeight)",
                subtitle: statusText(for: entry),
                detail: "PNG image",
                visual: .imageThumbnail(imageURL),
                action: .restoreClipboard(entry.id)
            )
        }
    }

    private func displayTitle(for entry: ClipboardEntry) -> String {
        switch entry.content {
        case .text(let text):
            return text
        case .image(let payload):
            return "clipboard image \(payload.pixelWidth)x\(payload.pixelHeight)"
        }
    }

    private func searchMetadata(for entry: ClipboardEntry) -> String {
        var parts: [String] = []

        if entry.isPinned {
            parts.append("pinned")
        }

        switch entry.content {
        case .text:
            parts.append("text")
        case .image(let payload):
            parts.append("image png \(payload.pixelWidth)x\(payload.pixelHeight)")
            parts.append(payload.filename)
        }

        if let lastUsedAt = entry.lastUsedAt {
            parts.append(DateFormatter.clipboardTimestamp.string(from: lastUsedAt))
        }

        parts.append(DateFormatter.clipboardTimestamp.string(from: entry.capturedAt))
        return parts.joined(separator: " ")
    }

    private func statusText(for entry: ClipboardEntry) -> String {
        var parts: [String] = []

        if entry.isPinned {
            parts.append("Pinned")
        }

        if let lastUsedAt = entry.lastUsedAt {
            parts.append("Used \(DateFormatter.clipboardTimestamp.string(from: lastUsedAt))")
        }

        parts.append(DateFormatter.clipboardTimestamp.string(from: entry.capturedAt))
        return parts.joined(separator: "  ·  ")
    }

    private func sortEntries(lhs: ClipboardEntry, rhs: ClipboardEntry) -> Bool {
        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned && rhs.isPinned == false
        }

        if lhs.sortDate != rhs.sortDate {
            return lhs.sortDate > rhs.sortDate
        }

        return lhs.capturedAt > rhs.capturedAt
    }

    private func load() throws {
        try fileManager.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: imageDirectoryURL, withIntermediateDirectories: true)

        guard fileManager.fileExists(atPath: storageURL.path) else {
            entries = []
            return
        }

        let data = try Data(contentsOf: storageURL)

        do {
            entries = try JSONDecoder().decode([ClipboardEntry].self, from: data)
        } catch {
            let legacyEntries = try JSONDecoder().decode([LegacyClipboardEntry].self, from: data)
            entries = legacyEntries.map {
                ClipboardEntry(
                    id: $0.id,
                    contentHash: Self.hash(for: Data($0.text.utf8)),
                    capturedAt: $0.capturedAt,
                    lastUsedAt: nil,
                    pinnedAt: nil,
                    content: .text($0.text)
                )
            }
        }

        try persistState()
    }

    private func persistState() throws {
        pruneExpiredEntries(referenceDate: Date())
        pruneEntriesWithMissingImages()
        trimUnpinnedEntriesIfNeeded()

        let data = try JSONEncoder().encode(entries)
        try data.write(to: storageURL, options: [.atomic])
        try reconcileImageFiles()
        lastErrorMessage = nil
    }

    private func pruneExpiredEntries(referenceDate: Date) {
        entries.removeAll { $0.isExpired(asOf: referenceDate) }
    }

    private func trimUnpinnedEntriesIfNeeded() {
        guard entries.count > maxEntries else { return }

        var retainedEntries = entries.filter(\.isPinned)
        let unpinnedEntries = entries.filter { $0.isPinned == false }

        if retainedEntries.count >= maxEntries {
            entries = retainedEntries
            return
        }

        let remainingCapacity = maxEntries - retainedEntries.count
        retainedEntries.append(contentsOf: unpinnedEntries.prefix(remainingCapacity))
        entries = retainedEntries.sorted(by: sortEntries)
    }

    private func pruneEntriesWithMissingImages() {
        entries.removeAll { entry in
            guard case .image(let payload) = entry.content else { return false }
            let fileURL = imageDirectoryURL.appending(path: payload.filename)
            return fileManager.fileExists(atPath: fileURL.path) == false
        }
    }

    private func reconcileImageFiles() throws {
        let activeFilenames = Set(
            entries.compactMap { entry -> String? in
                guard case .image(let payload) = entry.content else { return nil }
                return payload.filename
            }
        )

        let imageFiles = try fileManager.contentsOfDirectory(at: imageDirectoryURL, includingPropertiesForKeys: nil)
        for fileURL in imageFiles where activeFilenames.contains(fileURL.lastPathComponent) == false {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    private static func hash(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private extension NSImage {
    func pngData() -> Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }
}

private extension ClipboardEntry {
    var isImage: Bool {
        if case .image = content {
            return true
        }
        return false
    }
}
