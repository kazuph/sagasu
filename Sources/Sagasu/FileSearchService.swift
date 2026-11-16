import Foundation
import UniformTypeIdentifiers

struct FileSearchService: Sendable {
    static let spotlightCandidateLimit = 400
    static let spotlightCollectLimit = 2_000
    static let spotlightTimeLimit: TimeInterval = 2.5
    private static let mdfindURL = URL(fileURLWithPath: "/usr/bin/mdfind")
    static let recentItemLimit = 10
    static let recentSubtitlePrefix = "最近使った · "
    private static let unmatchedBaseScore = 100

    private let scopes: [URL]
    private let spotlightScopes: [URL]
    private let commonDirectories: [URL]
    private let homeDirectory: URL
    private let spotlightCollectLimit: Int

    init(
        fileManager: FileManager = .default,
        scopes: [URL]? = nil,
        commonDirectories: [URL]? = nil,
        spotlightScopes: [URL]? = nil,
        homeDirectory: URL? = nil,
        spotlightCollectLimit: Int = FileSearchService.spotlightCollectLimit
    ) {
        self.spotlightCollectLimit = spotlightCollectLimit
        let home = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
        let resolvedCommonDirectories = commonDirectories ?? Self.resolveCommonDirectories(fileManager: fileManager)
        self.commonDirectories = resolvedCommonDirectories
        self.scopes = scopes ?? Self.resolveScopes(fileManager: fileManager, commonDirectories: resolvedCommonDirectories)
        // 既定ではホーム全体を Spotlight で探す。scopes を明示した場合（主にテスト）はそれに従う。
        self.spotlightScopes = spotlightScopes ?? scopes ?? [home]
        self.homeDirectory = home
    }

    func search(query: String, limit: Int = 40, usageHistoryStore: UsageHistoryStore? = nil) throws -> [SearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isEmpty == false else {
            var seenPaths = Set<String>()
            var results = recentHistoryResults(
                usageHistoryStore: usageHistoryStore,
                directoriesOnly: false,
                excluding: &seenPaths
            )
            for folder in recentFolders(limit: min(limit, 40)) where seenPaths.insert(folder.detail).inserted {
                results.append(folder)
            }
            return Array(results.prefix(limit))
        }

        let now = Date()
        var seenPaths = Set<String>()
        var results = directorySearch(query: trimmedQuery, limit: min(8, limit), includingRecent: false, excluding: &seenPaths)

        var spotlightURLs: [URL] = []
        var rawLineCount = 0
        var mdfindFailed = false
        do {
            let collected = try collectSpotlightURLs(
                executableURL: Self.mdfindURL,
                arguments: buildArguments(for: trimmedQuery),
                query: trimmedQuery,
                usageHistoryStore: usageHistoryStore,
                now: now,
                excluding: &seenPaths
            )
            spotlightURLs = collected.urls
            rawLineCount = collected.rawLineCount
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            mdfindFailed = true
        }

        let historyURLs = historyCandidates(
            query: trimmedQuery,
            usageHistoryStore: usageHistoryStore,
            directoriesOnly: false,
            excluding: &seenPaths
        )
        let ranked = Self.rank(
            urls: spotlightURLs + historyURLs,
            query: trimmedQuery,
            usageHistoryStore: usageHistoryStore,
            now: now
        )
        results.append(contentsOf: ranked.map { makeResult(for: $0) })

        if Self.shouldFallback(rawLineCount: rawLineCount, mdfindFailed: mdfindFailed), results.count < limit {
            let fallbackResults = fallbackSearch(query: trimmedQuery, limit: limit - results.count, excluding: seenPaths)
            try Task.checkCancellation()
            results.append(contentsOf: fallbackResults)
        }
        try Task.checkCancellation()

        return Array(results.prefix(limit))
    }

    func searchDirectories(query: String, limit: Int = 40, usageHistoryStore: UsageHistoryStore? = nil) -> [SearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var seenPaths = Set<String>()
        guard trimmedQuery.isEmpty == false else {
            var results = recentHistoryResults(
                usageHistoryStore: usageHistoryStore,
                directoriesOnly: true,
                excluding: &seenPaths
            )
            var recentSeen = Set<String>()
            for result in directorySearch(query: "", limit: limit, includingRecent: true, excluding: &recentSeen)
            where seenPaths.insert(URL(fileURLWithPath: result.detail).standardizedFileURL.path).inserted {
                results.append(result)
            }
            return Array(results.prefix(limit))
        }

        let now = Date()
        var results = directorySearch(query: trimmedQuery, limit: min(8, limit), includingRecent: false, excluding: &seenPaths)

        var spotlightURLs: [URL] = []
        var rawLineCount = 0
        var mdfindFailed = false
        do {
            let collected = try collectSpotlightURLs(
                executableURL: Self.mdfindURL,
                arguments: buildDirectoryArguments(for: trimmedQuery),
                query: trimmedQuery,
                usageHistoryStore: usageHistoryStore,
                now: now,
                excluding: &seenPaths
            )
            spotlightURLs = collected.urls
            rawLineCount = collected.rawLineCount
        } catch is CancellationError {
            return []
        } catch {
            mdfindFailed = true
        }

        let historyURLs = historyCandidates(
            query: trimmedQuery,
            usageHistoryStore: usageHistoryStore,
            directoriesOnly: true,
            excluding: &seenPaths
        )
        // mdfind が使えないときは列挙した最近のフォルダの一致も、履歴・加点つきの並べ替えに合流させる。
        var recentFolderURLs: [URL] = []
        if Self.shouldFallback(rawLineCount: rawLineCount, mdfindFailed: mdfindFailed) {
            var fallbackSeen = Set<String>()
            for result in directorySearch(query: trimmedQuery, limit: limit, includingRecent: true, excluding: &fallbackSeen) {
                let url = URL(fileURLWithPath: result.detail).standardizedFileURL
                if seenPaths.insert(url.path).inserted {
                    recentFolderURLs.append(url)
                }
            }
        }
        if Task.isCancelled { return [] }
        let ranked = Self.rank(
            urls: spotlightURLs + historyURLs + recentFolderURLs,
            query: trimmedQuery,
            usageHistoryStore: usageHistoryStore,
            now: now
        )
        for url in ranked {
            if (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true { continue }
            results.append(makeResult(for: url))
        }

        return Array(results.prefix(limit))
    }

    // MARK: - Ranking and filtering

    /// 一致の強さ（ファイル名への SearchMatcher.score、無ければ低い基礎点）に履歴の加点を足して並べる。
    static func rank(urls: [URL], query: String, usageHistoryStore: UsageHistoryStore?, now: Date = Date()) -> [URL] {
        let normalizedQuery = SearchMatcher.normalize(query)
        // 履歴の url: キーのパス集合を1回だけ作り、含まれるときだけキーを作って加点を調べる。
        let usedPaths: Set<String> = Set(
            (usageHistoryStore?.recentKeys(withPrefix: UsageHistoryKey.urlPrefix) ?? [])
                .compactMap { UsageHistoryKey.path(fromKey: $0, prefix: UsageHistoryKey.urlPrefix) }
        )
        let scored: [(URL, Int)] = urls.map { url in
            let name = SearchMatcher.normalize(url.lastPathComponent)
            let match = SearchMatcher.score(query: normalizedQuery, primaryText: name, secondaryText: nil) ?? unmatchedBaseScore
            let boost = usedPaths.contains(url.path)
                ? (usageHistoryStore?.recencyBoost(for: UsageHistoryKey.url(url), now: now) ?? 0)
                : 0
            return (url, match + boost)
        }
        return scored
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.1 != rhs.element.1 { return lhs.element.1 > rhs.element.1 }
                return lhs.offset < rhs.offset
            }
            .map(\.element.0)
    }

    /// mdfind が1件以上返したときは fallback しない。0件または失敗のときだけ fallback する。
    static func shouldFallback(rawLineCount: Int, mdfindFailed: Bool) -> Bool {
        mdfindFailed || rawLineCount == 0
    }

    /// 全候補を採点（一致の強さ＋履歴加点）してから上位 limit 件だけ残す。
    static func topRanked(urls: [URL], query: String, usageHistoryStore: UsageHistoryStore?, now: Date = Date(), limit: Int) -> [URL] {
        Array(rank(urls: urls, query: query, usageHistoryStore: usageHistoryStore, now: now).prefix(limit))
    }

    /// mdfind のクエリ文字列用に `\` と `"` をエスケープする。
    static func escapeMetadataLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// 隠しパス（`.` で始まる要素を含む）、~/Library 配下（クラウド保存先などを除く）、node_modules を除外する。
    static func isExcludedSpotlightPath(_ path: String, home: String) -> Bool {
        let normalizedHome = home.hasSuffix("/") ? String(home.dropLast()) : home
        let relative: String
        if path.hasPrefix(normalizedHome + "/") {
            relative = String(path.dropFirst(normalizedHome.count + 1))
        } else {
            relative = path
        }
        let components = relative.split(separator: "/").map(String.init)

        if components.contains(where: { $0.hasPrefix(".") }) { return true }
        if components.contains("node_modules") { return true }
        // パッケージ（.app/.bundle/.framework/.xcodeproj など）の内部は除外。パッケージ自体は残す。
        for parent in components.dropLast() {
            let ext = (parent as NSString).pathExtension
            if ext.isEmpty == false, isPackageExtension(ext) { return true }
        }

        if relative.hasPrefix("Library/") || relative == "Library" {
            let allowedPrefixes = [
                "Library/CloudStorage/",
                "Library/Mobile Documents/com~apple~CloudDocs/",
                "Library/Recent Places/"
            ]
            let allowedExact = [
                "Library/CloudStorage",
                "Library/Mobile Documents/com~apple~CloudDocs",
                "Library/Recent Places"
            ]
            if allowedExact.contains(relative) { return false }
            return allowedPrefixes.contains(where: { relative.hasPrefix($0) }) == false
        }
        return false
    }

    /// .app/.bundle/.framework/.xcodeproj/.photoslibrary など、パッケージまたはバンドルとして宣言された拡張子か。
    static func isPackageExtension(_ ext: String) -> Bool {
        let key = ext.lowercased()
        if let cached = PackageExtensionCache.shared.value(for: key) { return cached }
        let result = [UTType.package, UTType.bundle].contains { base in
            UTType.types(tag: key, tagClass: .filenameExtension, conformingTo: base).contains { $0.isDynamic == false }
        }
        PackageExtensionCache.shared.set(result, for: key)
        return result
    }

    func collectSpotlightURLs(
        executableURL: URL,
        arguments: [String],
        query: String,
        usageHistoryStore: UsageHistoryStore?,
        now: Date,
        excluding seenPaths: inout Set<String>
    ) throws -> (urls: [URL], rawLineCount: Int) {
        var urls: [URL] = []
        var rawLineCount = 0
        let home = homeDirectory.path
        let collectLimit = spotlightCollectLimit
        var seen = seenPaths
        _ = try ShellCommandRunner().streamLines(
            executableURL: executableURL,
            arguments: arguments,
            timeLimit: Self.spotlightTimeLimit
        ) { path in
            guard path.isEmpty == false else { return true }
            rawLineCount += 1
            guard Self.isExcludedSpotlightPath(path, home: home) == false else { return true }
            guard seen.insert(path).inserted else { return true }
            urls.append(URL(fileURLWithPath: path))
            return urls.count < collectLimit
        }
        seenPaths = seen
        let top = Self.topRanked(
            urls: urls,
            query: query,
            usageHistoryStore: usageHistoryStore,
            now: now,
            limit: Self.spotlightCandidateLimit
        )
        return (top, rawLineCount)
    }

    // MARK: - History

    /// 新しい順に、条件を満たし実在する履歴 URL を返す。名前の絞り込みを先に行い、必要件数で止める。
    private func existingHistoryURLs(
        usageHistoryStore: UsageHistoryStore?,
        directoriesOnly: Bool,
        nameTerms: [String] = [],
        limit: Int? = nil
    ) -> [URL] {
        guard let usageHistoryStore else { return [] }
        let fileManager = FileManager.default
        var urls: [URL] = []
        for key in usageHistoryStore.recentKeys(withPrefix: UsageHistoryKey.urlPrefix) {
            guard let path = UsageHistoryKey.path(fromKey: key, prefix: UsageHistoryKey.urlPrefix) else { continue }
            if nameTerms.isEmpty == false {
                let name = SearchMatcher.normalize((path as NSString).lastPathComponent)
                guard nameTerms.allSatisfy({ name.contains($0) }) else { continue }
            }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else { continue }
            if directoriesOnly && isDirectory.boolValue == false { continue }
            urls.append(URL(fileURLWithPath: path, isDirectory: isDirectory.boolValue))
            if let limit, urls.count >= limit { break }
        }
        return urls
    }

    private func recentHistoryResults(
        usageHistoryStore: UsageHistoryStore?,
        directoriesOnly: Bool,
        excluding seenPaths: inout Set<String>
    ) -> [SearchResult] {
        var results: [SearchResult] = []
        for url in existingHistoryURLs(usageHistoryStore: usageHistoryStore, directoriesOnly: directoriesOnly, limit: Self.recentItemLimit * 3) {
            guard seenPaths.insert(url.standardizedFileURL.path).inserted else { continue }
            results.append(makeResult(for: url, recent: true))
            if results.count >= Self.recentItemLimit { break }
        }
        return results
    }

    private func historyCandidates(
        query: String,
        usageHistoryStore: UsageHistoryStore?,
        directoriesOnly: Bool,
        excluding seenPaths: inout Set<String>
    ) -> [URL] {
        let terms = query
            .split(whereSeparator: \.isWhitespace)
            .map { SearchMatcher.normalize(String($0)) }
            .filter { $0.isEmpty == false }
        guard terms.isEmpty == false else { return [] }

        var urls: [URL] = []
        for url in existingHistoryURLs(usageHistoryStore: usageHistoryStore, directoriesOnly: directoriesOnly, nameTerms: terms) {
            guard seenPaths.insert(url.path).inserted else { continue }
            urls.append(url)
        }
        return urls
    }

    func recentFolders(limit: Int = 12) -> [SearchResult] {
        let fileManager = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .contentModificationDateKey,
            .isPackageKey
        ]
        var seenPaths = Set<String>()
        var folders: [(URL, Date)] = []

        for scope in scopes {
            guard let enumerator = fileManager.enumerator(
                at: scope,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            while let url = enumerator.nextObject() as? URL {
                if Task.isCancelled { break }
                guard seenPaths.insert(url.path).inserted else { continue }
                guard let values = try? url.resourceValues(forKeys: resourceKeys),
                      values.isDirectory == true,
                      values.isPackage != true else {
                    continue
                }

                folders.append((url, values.contentModificationDate ?? .distantPast))
                if folders.count >= max(limit * 12, 80) {
                    break
                }
            }
        }

        return folders
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.lastPathComponent.localizedCaseInsensitiveCompare(rhs.0.lastPathComponent) == .orderedAscending
            }
            .prefix(limit)
            .map { makeResult(for: $0.0) }
    }

    private func directorySearch(
        query: String,
        limit: Int,
        includingRecent: Bool,
        excluding seenPaths: inout Set<String>
    ) -> [SearchResult] {
        guard limit > 0 else { return [] }
        let normalizedQuery = SearchMatcher.normalize(query)
        var results: [SearchResult] = []

        for directory in commonDirectories {
            guard seenPaths.insert(directory.standardizedFileURL.path).inserted else { continue }
            let primary = SearchMatcher.normalize(directory.lastPathComponent)
            let secondary = SearchMatcher.normalize(directory.path)
            if normalizedQuery.isEmpty || SearchMatcher.score(query: normalizedQuery, primaryText: primary, secondaryText: secondary) != nil {
                results.append(makeResult(for: directory))
            }
            if results.count >= limit { return results }
        }

        guard includingRecent else { return results }
        for result in recentFolders(limit: limit * 2) {
            let standardizedPath = URL(fileURLWithPath: result.detail).standardizedFileURL.path
            guard seenPaths.insert(standardizedPath).inserted else { continue }
            let primary = SearchMatcher.normalize(result.title)
            let secondary = SearchMatcher.normalize(result.detail)
            if normalizedQuery.isEmpty || SearchMatcher.score(query: normalizedQuery, primaryText: primary, secondaryText: secondary) != nil {
                results.append(result)
            }
            if results.count >= limit { break }
        }

        return results
    }

    private func buildArguments(for query: String) -> [String] {
        var arguments: [String] = []
        for scope in spotlightScopes {
            arguments.append(contentsOf: ["-onlyin", scope.path])
        }
        arguments.append(metadataQuery(for: query))
        return arguments
    }

    private func buildDirectoryArguments(for query: String) -> [String] {
        var arguments: [String] = []
        for scope in spotlightScopes {
            arguments.append(contentsOf: ["-onlyin", scope.path])
        }
        let terms = query
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { $0.isEmpty == false }
        let nameClauses = terms.map { term -> String in
            let escaped = Self.escapeMetadataLiteral(term)
            return "kMDItemFSName == \"*\(escaped)*\"cdw"
        }
        arguments.append((["kMDItemContentType == \"public.folder\""] + nameClauses).joined(separator: " && "))
        return arguments
    }

    private func metadataQuery(for query: String) -> String {
        let terms = query
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { $0.isEmpty == false }

        guard terms.isEmpty == false else {
            return "kMDItemFSName == \"*\"cdw"
        }

        return terms
            .map { term in
                let escaped = Self.escapeMetadataLiteral(term)
                var clauses = [
                    "kMDItemFSName == \"*\(escaped)*\"cdw",
                    "kMDItemDisplayName == \"*\(escaped)*\"cdw"
                ]

                if term.contains(".") == false {
                    clauses.append("kMDItemFSName == \"*.\(escaped)\"cdw")
                }

                if let contentType = UTType(filenameExtension: term)?.identifier {
                    let escapedType = contentType.replacingOccurrences(of: "\"", with: "\\\"")
                    clauses.append("kMDItemContentType == \"\(escapedType)\"")
                    clauses.append("kMDItemContentTypeTree == \"\(escapedType)\"")
                }

                return "(" + clauses.joined(separator: " || ") + ")"
            }
            .joined(separator: " && ")
    }

    private func visual(for url: URL) -> SearchResultVisual {
        if isImageFile(url) {
            return .imageThumbnail(url)
        }

        return .fileIcon(url)
    }

    private func makeResult(for url: URL, recent: Bool = false) -> SearchResult {
        SearchResult(
            title: url.lastPathComponent,
            subtitle: (recent ? Self.recentSubtitlePrefix : "") + url.deletingLastPathComponent().path,
            detail: url.path,
            visual: visual(for: url),
            action: .openURL(url)
        )
    }

    private func isImageFile(_ url: URL) -> Bool {
        guard url.hasDirectoryPath == false else { return false }
        guard let contentType = UTType(filenameExtension: url.pathExtension) else { return false }
        return contentType.conforms(to: .image)
    }

    private func fallbackSearch(query: String, limit: Int, excluding: Set<String>) -> [SearchResult] {
        guard limit > 0 else { return [] }
        let fileManager = FileManager.default

        let normalizedTerms = query
            .split(whereSeparator: \.isWhitespace)
            .map { SearchMatcher.normalize(String($0)) }
            .filter { $0.isEmpty == false }

        guard normalizedTerms.isEmpty == false else { return [] }

        var matches: [(URL, Date)] = []
        var seenPaths = excluding
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .contentTypeKey,
            .contentModificationDateKey
        ]

        for scope in scopes {
            guard let enumerator = fileManager.enumerator(
                at: scope,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            while let url = enumerator.nextObject() as? URL {
                if Task.isCancelled { break }
                let values = try? url.resourceValues(forKeys: resourceKeys)
                if values?.isDirectory == true { continue }
                if seenPaths.contains(url.path) { continue }

                let filename = SearchMatcher.normalize(url.lastPathComponent)
                let extensionName = SearchMatcher.normalize(url.pathExtension)

                let isMatch = normalizedTerms.allSatisfy { term in
                    filename.contains(term) || extensionName == term
                }

                guard isMatch else { continue }
                seenPaths.insert(url.path)
                matches.append((url, values?.contentModificationDate ?? .distantPast))

                if matches.count >= limit * 3 {
                    break
                }
            }
        }

        return matches
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.lastPathComponent.localizedCaseInsensitiveCompare(rhs.0.lastPathComponent) == .orderedAscending
            }
            .prefix(limit)
            .map { makeResult(for: $0.0) }
    }

    private static func resolveCommonDirectories(fileManager: FileManager) -> [URL] {
        let home = fileManager.homeDirectoryForCurrentUser
        let directories: [URL] = [
            home.appending(path: "Desktop"),
            home.appending(path: "Downloads"),
            home.appending(path: "Documents"),
            home.appending(path: "Music"),
            home.appending(path: "Pictures"),
            home.appending(path: "Movies"),
            home.appending(path: "Library/Recent Places")
        ]

        return directories.filter { fileManager.fileExists(atPath: $0.path) }
    }

    private static func resolveScopes(fileManager: FileManager, commonDirectories: [URL]) -> [URL] {
        var result: [URL] = []
        let home = fileManager.homeDirectoryForCurrentUser

        result.append(contentsOf: commonDirectories)

        let dropboxCandidates = [
            home.appending(path: "Dropbox"),
            home.appending(path: "Dropbox (Personal)"),
            home.appending(path: "Library/CloudStorage/Dropbox"),
            home.appending(path: "Library/CloudStorage/Dropbox (Personal)")
        ]
        result.append(contentsOf: dropboxCandidates.filter { fileManager.fileExists(atPath: $0.path) })

        let iCloudDrive = home.appending(path: "Library/Mobile Documents/com~apple~CloudDocs")
        if fileManager.fileExists(atPath: iCloudDrive.path) {
            result.append(iCloudDrive)
        }

        let cloudStorageRoot = home.appending(path: "Library/CloudStorage")
        if let contents = try? fileManager.contentsOfDirectory(at: cloudStorageRoot, includingPropertiesForKeys: nil) {
            result.append(contentsOf:
                contents.filter { url in
                    let lastComponent = url.lastPathComponent.lowercased()
                    return lastComponent.contains("dropbox") || lastComponent.contains("icloud")
                }
            )
        }

        return Array(Set(result))
            .sorted { lhs, rhs in
                lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
            }
    }
}

private final class PackageExtensionCache: @unchecked Sendable {
    static let shared = PackageExtensionCache()
    private let lock = NSLock()
    private var values: [String: Bool] = [:]

    func value(for key: String) -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func set(_ value: Bool, for key: String) {
        lock.lock()
        values[key] = value
        lock.unlock()
    }
}
