import Foundation
import UniformTypeIdentifiers

struct FileSearchService: Sendable {
    private let scopes: [URL]
    private let commonDirectories: [URL]

    init(fileManager: FileManager = .default, scopes: [URL]? = nil, commonDirectories: [URL]? = nil) {
        let resolvedCommonDirectories = commonDirectories ?? Self.resolveCommonDirectories(fileManager: fileManager)
        self.commonDirectories = resolvedCommonDirectories
        self.scopes = scopes ?? Self.resolveScopes(fileManager: fileManager, commonDirectories: resolvedCommonDirectories)
    }

    func search(query: String, limit: Int = 40) throws -> [SearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isEmpty == false else {
            return recentFolders(limit: min(limit, 40))
        }

        var seenPaths = Set<String>()
        var results = directorySearch(query: trimmedQuery, limit: min(8, limit), includingRecent: false, excluding: &seenPaths)

        let commandRunner = ShellCommandRunner()
        let output = try commandRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/mdfind"),
            arguments: buildArguments(for: trimmedQuery)
        )

        let spotlightResults = output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> SearchResult? in
                let path = String(line)
                guard path.isEmpty == false else { return nil }
                let url = URL(fileURLWithPath: path)
                guard seenPaths.insert(path).inserted else { return nil }
                return makeResult(for: url)
            }
        results.append(contentsOf: spotlightResults)

        if results.count < limit {
            let fallbackResults = fallbackSearch(query: trimmedQuery, limit: limit - results.count, excluding: seenPaths)
            results.append(contentsOf: fallbackResults)
        }

        return Array(results.prefix(limit))
    }

    func searchDirectories(query: String, limit: Int = 40) -> [SearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var seenPaths = Set<String>()
        guard trimmedQuery.isEmpty == false else {
            return directorySearch(query: "", limit: limit, includingRecent: true, excluding: &seenPaths)
        }

        return directorySearch(query: trimmedQuery, limit: limit, includingRecent: true, excluding: &seenPaths)
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

        guard includingRecent || normalizedQuery.isEmpty == false else { return results }
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
        for scope in scopes {
            arguments.append(contentsOf: ["-onlyin", scope.path])
        }
        arguments.append(metadataQuery(for: query))
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
                let escaped = term.replacingOccurrences(of: "\"", with: "\\\"")
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

    private func makeResult(for url: URL) -> SearchResult {
        SearchResult(
            title: url.lastPathComponent,
            subtitle: url.deletingLastPathComponent().path,
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
