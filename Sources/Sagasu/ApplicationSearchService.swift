import AppKit
import Foundation

struct ApplicationSearchService: Sendable {
    private struct IndexedApplication: Hashable {
        let url: URL
        let name: String
        let bundleIdentifier: String
        let normalizedName: String
    }

    private let applications: [IndexedApplication]

    init(fileManager: FileManager = .default) {
        applications = Self.loadApplications(fileManager: fileManager)
    }

    func search(
        query: String,
        limit: Int = 40,
        usageHistoryStore: UsageHistoryStore? = nil,
        additionalResults: [SearchResult] = []
    ) -> [SearchResult] {
        let normalizedQuery = SearchMatcher.normalize(query)
        let runningBundleIdentifiers = Set(
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        )
        let now = Date()

        var ranked: [(SearchResult, Int)] = applications.compactMap { application in
            let score: Int
            if normalizedQuery.isEmpty {
                score = runningBundleIdentifiers.contains(application.bundleIdentifier) ? 1_000 : 500
            } else if let matchedScore = SearchMatcher.score(
                query: normalizedQuery,
                primaryText: application.normalizedName,
                secondaryText: SearchMatcher.normalize(application.bundleIdentifier)
            ) {
                score = matchedScore + (runningBundleIdentifiers.contains(application.bundleIdentifier) ? 25 : 0)
            } else {
                return nil
            }

            let usageBoost = usageHistoryStore
                .flatMap { $0.lastUsedAt(for: UsageHistoryKey.application(application.url)) }
                .map { lastUsedAt in
                    max(0, 240 - Int(now.timeIntervalSince(lastUsedAt) / 86_400))
                } ?? 0

            let result = SearchResult(
                title: application.name,
                subtitle: application.bundleIdentifier,
                detail: application.url.path,
                visual: .fileIcon(application.url),
                action: .launchApplication(application.url)
            )
            return (result, score + usageBoost)
        }

        ranked.append(contentsOf: additionalResults.compactMap { result in
            let score: Int
            if normalizedQuery.isEmpty {
                score = 500
            } else if let matchedScore = SearchMatcher.score(
                query: normalizedQuery,
                primaryText: SearchMatcher.normalize(result.title),
                secondaryText: SearchMatcher.normalize([result.subtitle, result.detail].joined(separator: " "))
            ) {
                score = matchedScore
            } else {
                return nil
            }

            return (result, score)
        })

        return ranked
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.title.localizedCaseInsensitiveCompare(rhs.0.title) == .orderedAscending
            }
            .prefix(limit)
            .map(\.0)
    }

    private static func loadApplications(fileManager: FileManager) -> [IndexedApplication] {
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Library/CoreServices"),
            fileManager.homeDirectoryForCurrentUser.appending(path: "Applications")
        ]

        var seenPaths = Set<String>()
        var applications: [IndexedApplication] = []

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            while let item = enumerator.nextObject() as? URL {
                if item.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
                    seenPaths.insert(item.path)
                    applications.append(
                        IndexedApplication(
                            url: item,
                            name: fileManager.displayName(atPath: item.path).replacingOccurrences(of: ".app", with: ""),
                            bundleIdentifier: Bundle(url: item)?.bundleIdentifier ?? "",
                            normalizedName: SearchMatcher.normalize(item.deletingPathExtension().lastPathComponent)
                        )
                    )
                    enumerator.skipDescendants()
                }
            }
        }

        return Array(Set(applications)).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
