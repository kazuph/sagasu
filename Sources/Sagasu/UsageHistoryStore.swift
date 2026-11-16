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

    /// 最終利用からの経過日数 d に対し max(0, 500 - d*10)（当日500、50日で0）。
    static func recencyBoost(lastUsedAt: Date, now: Date = Date()) -> Int {
        let days = Int(now.timeIntervalSince(lastUsedAt) / 86_400)
        return max(0, 500 - max(0, days) * 10)
    }

    func recencyBoost(for key: String, now: Date = Date()) -> Int {
        guard let lastUsedAt = lastUsedAt(for: key) else { return 0 }
        return Self.recencyBoost(lastUsedAt: lastUsedAt, now: now)
    }

    /// 接頭辞で絞った、最終利用が新しい順のキー。
    func recentKeys(withPrefix prefix: String, limit: Int? = nil) -> [String] {
        lock.lock()
        let snapshot = entries
        lock.unlock()

        let sorted = snapshot
            .filter { $0.key.hasPrefix(prefix) }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .map(\.key)
        guard let limit else { return sorted }
        return Array(sorted.prefix(limit))
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

    static let applicationPrefix = "application:"
    static let urlPrefix = "url:"

    static func url(_ url: URL) -> String {
        "url:\(url.standardizedFileURL.path)"
    }

    static func path(fromKey key: String, prefix: String) -> String? {
        guard key.hasPrefix(prefix) else { return nil }
        return String(key.dropFirst(prefix.count))
    }
}
