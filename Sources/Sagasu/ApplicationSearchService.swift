import AppKit
import Foundation

struct ApplicationSearchService: @unchecked Sendable {
    private struct IndexedApplication: Hashable {
        let url: URL
        let name: String
        let bundleIdentifier: String
        let normalizedName: String
        let normalizedSearchTerms: String
    }

    private let fileManager: FileManager
    private let roots: [URL]
    private let preferredLanguages: [String]

    init(fileManager: FileManager = .default, roots: [URL]? = nil, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.fileManager = fileManager
        self.roots = roots ?? Self.defaultRoots(fileManager: fileManager)
        self.preferredLanguages = preferredLanguages
    }

    func search(
        query: String,
        limit: Int = 40,
        usageHistoryStore: UsageHistoryStore? = nil,
        additionalResults: [SearchResult] = [],
        runningBundleIdentifiers providedRunningBundleIdentifiers: Set<String>? = nil
    ) -> [SearchResult] {
        let applications = Self.loadApplications(fileManager: fileManager, roots: roots, preferredLanguages: preferredLanguages)
        let normalizedQuery = SearchMatcher.normalize(query)
        let runningBundleIdentifiers = providedRunningBundleIdentifiers ?? Set(
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
                secondaryText: application.normalizedSearchTerms
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
                secondaryText: SearchMatcher.normalize([result.subtitle, result.detail, result.searchTerms].joined(separator: " "))
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

    private static func defaultRoots(fileManager: FileManager) -> [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Library/CoreServices"),
            fileManager.homeDirectoryForCurrentUser.appending(path: "Applications")
        ]
    }

    private static func loadApplications(fileManager: FileManager, roots: [URL], preferredLanguages: [String]) -> [IndexedApplication] {
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
                    let metadata = applicationMetadata(for: item, preferredLanguages: preferredLanguages)
                    seenPaths.insert(item.path)
                    applications.append(
                        IndexedApplication(
                            url: item,
                            name: metadata.name,
                            bundleIdentifier: metadata.bundleIdentifier,
                            normalizedName: SearchMatcher.normalize(metadata.name),
                            normalizedSearchTerms: SearchMatcher.normalize(metadata.searchTerms.joined(separator: " "))
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

    private static func applicationMetadata(
        for url: URL,
        preferredLanguages: [String]
    ) -> (name: String, bundleIdentifier: String, searchTerms: [String]) {
        let fileName = url.deletingPathExtension().lastPathComponent
        guard let bundle = Bundle(url: url) else {
            return (fileName, "", [fileName])
        }

        let bundleIdentifier = bundle.bundleIdentifier ?? ""
        let localizedInfo = localizedInfoDictionaries(for: bundle, preferredLanguages: preferredLanguages)
        let localizedNames = localizedInfo
            .compactMap { info in
                (info["CFBundleDisplayName"] ?? info["CFBundleName"] ?? info["CFBundleSpokenName"]) as? String
            }
            .filter { $0.isEmpty == false }
        let infoName = (bundle.infoDictionary?["CFBundleDisplayName"] ?? bundle.infoDictionary?["CFBundleName"]) as? String
        let name = localizedNames.first ?? infoName ?? fileName
        var terms = [fileName, name, bundleIdentifier]

        for info in localizedInfo {
            terms.append(contentsOf: applicationNameSearchTerms(from: info))
        }
        if let infoName {
            terms.append(infoName)
        }

        return (name, bundleIdentifier, orderedUnique(terms.filter { $0.isEmpty == false }))
    }

    private static func localizedInfoDictionaries(for bundle: Bundle, preferredLanguages: [String]) -> [[String: Any]] {
        var dictionaries: [[String: Any]] = []
        let localizationCandidates = preferredLanguages.flatMap { language in
            let normalized = language.replacingOccurrences(of: "-", with: "_")
            let baseLanguage = normalized.split(separator: "_").first.map(String.init)
            return [normalized, baseLanguage].compactMap(\.self)
        }

        for localization in orderedUnique(localizationCandidates + ["Base", "en"]) {
            if let dictionary = bundle.localizedInfoDictionary(forLocalization: localization) {
                dictionaries.append(dictionary)
            }
        }

        if let dictionary = bundle.infoDictionary {
            dictionaries.append(dictionary)
        }

        return dictionaries
    }

    private static func applicationNameSearchTerms(from info: [String: Any]) -> [String] {
        var terms: [String] = []
        for (key, value) in info {
            guard let stringValue = value as? String else { continue }
            if key == "CFBundleDisplayName" ||
                key == "CFBundleName" ||
                key == "CFBundleSpokenName" ||
                key.hasPrefix("APP_NAME_SYNONYM") {
                terms.append(stringValue)
            } else if key == "kMDItemKeywords" {
                terms.append(contentsOf: stringValue.split(separator: ",").map {
                    String($0).trimmingCharacters(in: .whitespacesAndNewlines)
                })
            }
        }
        return terms
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }
}

private extension Bundle {
    func localizedInfoDictionary(forLocalization localization: String) -> [String: Any]? {
        if let stringsURL = url(
            forResource: "InfoPlist",
            withExtension: "strings",
            subdirectory: nil,
            localization: localization
        ),
            let dictionary = NSDictionary(contentsOf: stringsURL) as? [String: Any] {
            return dictionary
        }

        guard let resourceURL,
              let localizationTable = NSDictionary(contentsOf: resourceURL.appending(path: "InfoPlist.loctable")) as? [String: Any],
              let dictionary = localizationTable[localization] as? [String: Any] else {
            return nil
        }
        return dictionary
    }
}
