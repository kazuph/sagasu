import Foundation
import UniformTypeIdentifiers

struct FileSearchService: Sendable {
    private let scopes: [URL]

    init(fileManager: FileManager = .default, scopes: [URL]? = nil) {
        self.scopes = scopes ?? Self.resolveScopes(fileManager: fileManager)
    }

    func search(query: String, limit: Int = 40) throws -> [SearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isEmpty == false else {
            return recentFolders(limit: min(limit, 40))
        }

        let commandRunner = ShellCommandRunner()
        let output = try commandRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/mdfind"),
            arguments: buildArguments(for: trimmedQuery)
        )

        var seenPaths = Set<String>()
        var results = output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> SearchResult? in
                let path = String(line)
                guard path.isEmpty == false else { return nil }
                let url = URL(fileURLWithPath: path)
                guard seenPaths.insert(path).inserted else { return nil }
                return makeResult(for: url)
            }

        if results.count < limit {
            let fallbackResults = fallbackSearch(query: trimmedQuery, limit: limit - results.count, excluding: seenPaths)
            results.append(contentsOf: fallbackResults)
        }

        return Array(results.prefix(limit))
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

    private static func resolveScopes(fileManager: FileManager) -> [URL] {
        var result: [URL] = []
        let home = fileManager.homeDirectoryForCurrentUser
        let standardDirectories: [URL] = [
            home.appending(path: "Desktop"),
            home.appending(path: "Downloads"),
            home.appending(path: "Documents"),
            home.appending(path: "Pictures"),
            home.appending(path: "Movies"),
            home.appending(path: "Library/Recent Places")
        ]

        result.append(contentsOf: standardDirectories.filter { fileManager.fileExists(atPath: $0.path) })

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
