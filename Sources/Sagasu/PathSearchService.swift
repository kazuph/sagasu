import Foundation
import UniformTypeIdentifiers

struct PathSearchService: @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func search(query: String, limit: Int = 40) -> [SearchResult] {
        guard let (path, listsContents) = resolve(query) else { return [] }

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: path, isDirectory: &isDirectory) {
            let url = URL(fileURLWithPath: path, isDirectory: isDirectory.boolValue)
            var results = [openResult(for: url), copyResult(for: url)]
            if listsContents, isDirectory.boolValue {
                let children = (try? fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )) ?? []
                results.append(contentsOf: sorted(children).prefix(limit).map(openResult(for:)))
            }
            return results
        }

        let candidate = URL(fileURLWithPath: path)
        let parent = candidate.deletingLastPathComponent()
        var parentIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: parent.path, isDirectory: &parentIsDirectory),
              parentIsDirectory.boolValue else { return [] }

        let prefix = candidate.lastPathComponent
        let options: FileManager.DirectoryEnumerationOptions = prefix.hasPrefix(".") ? [] : [.skipsHiddenFiles]
        let children = (try? fileManager.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: nil,
            options: options
        )) ?? []
        let matches = children.filter { $0.lastPathComponent.lowercased().hasPrefix(prefix.lowercased()) }
        return sorted(matches).prefix(limit).map(openResult(for:))
    }

    /// Returns the resolved filesystem path and whether the input ended with `/`.
    private func resolve(_ query: String) -> (path: String, listsContents: Bool)? {
        var text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count >= 2, let first = text.first, first == "\"" || first == "'", text.last == first {
            text = String(text.dropFirst().dropLast())
        }
        guard text.isEmpty == false else { return nil }

        var path: String
        if text.lowercased().hasPrefix("file://") {
            guard let url = URL(string: text), url.isFileURL else { return nil }
            path = url.path
        } else {
            path = text.replacingOccurrences(of: "\\ ", with: " ")
            if path == "~" || path.hasPrefix("~/") {
                path = (path as NSString).expandingTildeInPath
            }
        }
        guard path.isEmpty == false else { return nil }
        return (path, text.hasSuffix("/"))
    }

    private func sorted(_ urls: [URL]) -> [URL] {
        urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func openResult(for url: URL) -> SearchResult {
        SearchResult(
            title: url.lastPathComponent,
            subtitle: url.deletingLastPathComponent().path,
            detail: url.path,
            visual: isImageFile(url) ? .imageThumbnail(url) : .fileIcon(url),
            action: .openURL(url)
        )
    }

    private func copyResult(for url: URL) -> SearchResult {
        SearchResult(
            title: "Copy File",
            subtitle: url.lastPathComponent,
            detail: url.path,
            visual: .symbol("doc.on.doc"),
            action: .copyFile(url)
        )
    }

    private func isImageFile(_ url: URL) -> Bool {
        guard url.hasDirectoryPath == false else { return false }
        guard let contentType = UTType(filenameExtension: url.pathExtension) else { return false }
        return contentType.conforms(to: .image)
    }
}
