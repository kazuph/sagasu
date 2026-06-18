import Foundation

final class UsageHistoryStore: @unchecked Sendable {
    private struct State: Codable {
        var entries: [String: Date]
    }

    private let lock = NSLock()
    private let fileManager: FileManager
    private let storageURL: URL
    private var entries: [String: Date]

    init(fileManager: FileManager = .default, baseDirectoryURL: URL? = nil) {
        self.fileManager = fileManager

        let resolvedBaseDirectoryURL: URL
        if let baseDirectoryURL {
            resolvedBaseDirectoryURL = baseDirectoryURL
        } else {
            let appSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            resolvedBaseDirectoryURL = appSupportDirectory
                .appending(path: "Sagasu", directoryHint: .isDirectory)
        }

        storageURL = resolvedBaseDirectoryURL.appending(path: "usage-history.json")
        entries = (try? Self.load(from: storageURL)) ?? [:]
    }

    func lastUsedAt(for key: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return entries[key]
    }

    func markUsed(key: String, at date: Date = Date()) throws {
        lock.lock()
        entries[key] = date
        let state = State(entries: entries)
        lock.unlock()

        try fileManager.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(state)
        try data.write(to: storageURL, options: [.atomic])
    }

    private static func load(from url: URL) throws -> [String: Date] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(State.self, from: data).entries
    }
}

enum UsageHistoryKey {
    static func application(_ url: URL) -> String {
        "application:\(url.path)"
    }

    static func url(_ url: URL) -> String {
        "url:\(url.standardizedFileURL.path)"
    }
}
