import Foundation

final class UsageHistoryStore: @unchecked Sendable {
    /// 「最近使った」の項目に付ける subtitle の接頭辞。アプリ・ファイル・フォルダで共通。
    static let recentSubtitlePrefix = "最近使った · "
    /// 保存する履歴の上限。超えた分は古い順に entries と snapshots の両方から消す。
    static let maximumEntryCount = 500

    /// 「最近使った」から選んだ項目の subtitle に付いた接頭辞を外す（保存のたびに重なるのを防ぐ）。
    static func strippingRecentPrefix(_ subtitle: String) -> String {
        var value = subtitle
        while value.hasPrefix(recentSubtitlePrefix) {
            value = String(value.dropFirst(recentSubtitlePrefix.count))
        }
        return value
    }

    /// 選んだ項目の表示内容の写し。検索を経由せずに「最近使った」へ出すために保存する。
    struct Snapshot: Codable, Equatable, Sendable {
        var title: String
        var subtitle: String
        var detail: String
        var visual: SearchResultVisual
        var action: SearchAction
        var searchTerms: String

        init(result: SearchResult) {
            title = result.title
            subtitle = UsageHistoryStore.strippingRecentPrefix(result.subtitle)
            detail = result.detail
            visual = result.visual
            action = result.action
            searchTerms = result.searchTerms
        }

        func makeResult(subtitlePrefix: String = "") -> SearchResult {
            SearchResult(
                title: title,
                subtitle: subtitlePrefix + subtitle,
                detail: detail,
                visual: visual,
                action: action,
                searchTerms: searchTerms
            )
        }
    }

    private struct State: Codable {
        var entries: [String: Date]
        // 古い usage-history.json には無い。optional にして後方互換にする。
        var snapshots: [String: Snapshot]?

        init(entries: [String: Date], snapshots: [String: Snapshot]?) {
            self.entries = entries
            self.snapshots = snapshots
        }

        // 写しが1件壊れていても、履歴の時刻（entries）と他の写しは読めるようにする。
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            entries = try container.decode([String: Date].self, forKey: .entries)
            let rawSnapshots = (try? container.decodeIfPresent([String: LossySnapshot].self, forKey: .snapshots)) ?? nil
            snapshots = rawSnapshots?.compactMapValues(\.value)
        }
    }

    private struct LossySnapshot: Decodable {
        let value: Snapshot?
        init(from decoder: Decoder) throws {
            value = try? Snapshot(from: decoder)
        }
    }

    private let lock = NSLock()
    private let fileManager: FileManager
    private let storageURL: URL
    private var entries: [String: Date]
    private var snapshots: [String: Snapshot]

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
        let loaded = try? Self.load(from: storageURL)
        entries = loaded?.entries ?? [:]
        snapshots = loaded?.snapshots ?? [:]
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

    func snapshot(for key: String) -> Snapshot? {
        lock.lock()
        defer { lock.unlock() }
        return snapshots[key]
    }

    /// 全キーを最終利用が新しい順に返す。
    func recentEntries() -> [(key: String, date: Date)] {
        lock.lock()
        let snapshot = entries
        lock.unlock()
        return snapshot
            .map { (key: $0.key, date: $0.value) }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                return lhs.key < rhs.key
            }
    }

    func markUsed(key: String, at date: Date = Date(), snapshot: Snapshot? = nil) throws {
        lock.lock()
        entries[key] = date
        // アプリはアプリ一覧から表示を作り直すので、写しは保存しない。
        if let snapshot, key.hasPrefix(UsageHistoryKey.applicationPrefix) == false {
            snapshots[key] = snapshot
        }
        if entries.count > Self.maximumEntryCount {
            let overflow = entries
                .sorted { lhs, rhs in
                    if lhs.value != rhs.value { return lhs.value < rhs.value }
                    return lhs.key < rhs.key
                }
                .prefix(entries.count - Self.maximumEntryCount)
            for (oldKey, _) in overflow {
                entries[oldKey] = nil
                snapshots[oldKey] = nil
            }
        }
        let state = State(entries: entries, snapshots: snapshots.isEmpty ? nil : snapshots)
        lock.unlock()

        try fileManager.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(state)
        try data.write(to: storageURL, options: [.atomic])
    }

    private static func load(from url: URL) throws -> State {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(State.self, from: data)
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

    /// 選んだ action に対する履歴キー。restoreClipboard は ClipboardHistoryStore が自前で持つので nil。
    /// application: と url: は既存の usage-history.json の記録をそのまま生かす。
    static func key(for action: SearchAction) -> String? {
        switch action {
        case .launchApplication(let url):
            return application(url)
        case .openURL(let url):
            return Self.url(url)
        case .openURLInPreferredBrowser(let url, _):
            return "browser:\(url.absoluteString)"
        case .openNote(let id):
            return "note:\(id)"
        case .restoreClipboard:
            return nil
        case .saveClipboardImage:
            return "command:saveClipboardImage"
        case .extractTextFromClipboardImage:
            return "command:extractTextFromClipboardImage"
        case .focusTerminalPane(let id):
            return "pane:\(id)"
        case .configureLinearAPIKey:
            return "command:configureLinearAPIKey"
        case .copyText(let text):
            return "text:\(text)"
        case .copyFile(let url):
            return "copyfile:\(url.standardizedFileURL.path)"
        }
    }

    static func path(fromKey key: String, prefix: String) -> String? {
        guard key.hasPrefix(prefix) else { return nil }
        return String(key.dropFirst(prefix.count))
    }
}
