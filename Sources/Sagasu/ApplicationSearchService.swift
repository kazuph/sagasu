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

    static let recentApplicationLimit = 8
    static let recentSubtitlePrefix = UsageHistoryStore.recentSubtitlePrefix

    /// 実在を確かめるべき履歴キー（ファイル・フォルダ）のパス。それ以外は nil。
    private static func filePath(forKey key: String) -> String? {
        if let path = UsageHistoryKey.path(fromKey: key, prefix: UsageHistoryKey.urlPrefix), path.hasPrefix("/") {
            return path
        }
        return UsageHistoryKey.path(fromKey: key, prefix: "copyfile:")
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
        legacyLookupResults: [SearchResult] = [],
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

            let usageBoost = usageHistoryStore?
                .recencyBoost(for: UsageHistoryKey.application(application.url), now: now) ?? 0

            let result = SearchResult(
                title: application.name,
                subtitle: application.bundleIdentifier,
                detail: application.url.path,
                visual: .fileIcon(application.url),
                action: .launchApplication(application.url)
            )
            return (result, score + usageBoost)
        }

        var shownRecentKeys = Set<String>()
        if normalizedQuery.isEmpty, let usageHistoryStore {
            let applicationsByPath = Dictionary(applications.map { ($0.url.path, $0) }, uniquingKeysWith: { first, _ in first })
            // 写しの無い古い記録（設定など）は、設定の一覧と url: キーで照合する。
            let legacyByKey: [String: SearchResult] = Dictionary(
                legacyLookupResults.compactMap { result in
                    UsageHistoryKey.key(for: result.action).map { ($0, result) }
                },
                uniquingKeysWith: { first, _ in first }
            )
            var recentApplicationPaths = Set<String>()
            var shownRecentDetails = Set<String>()
            var recentResults: [SearchResult] = []
            for entry in usageHistoryStore.recentEntries() {
                if recentResults.count >= Self.recentApplicationLimit { break }
                let key = entry.key
                if let path = UsageHistoryKey.path(fromKey: key, prefix: UsageHistoryKey.applicationPrefix) {
                    // f で .app を開いた記録（url:）と同じアプリを2回出さない。
                    guard let application = applicationsByPath[path],
                          shownRecentDetails.insert(application.url.path).inserted else { continue }
                    recentApplicationPaths.insert(path)
                    recentResults.append(
                        SearchResult(
                            title: application.name,
                            subtitle: Self.recentSubtitlePrefix + application.bundleIdentifier,
                            detail: application.url.path,
                            visual: .fileIcon(application.url),
                            action: .launchApplication(application.url)
                        )
                    )
                } else if let snapshot = usageHistoryStore.snapshot(for: key) {
                    if let filePath = Self.filePath(forKey: key), fileManager.fileExists(atPath: filePath) == false { continue }
                    if Self.filePath(forKey: key) != nil,
                       shownRecentDetails.insert(snapshot.detail).inserted == false { continue }
                    recentResults.append(snapshot.makeResult(subtitlePrefix: Self.recentSubtitlePrefix))
                } else if let legacy = legacyByKey[key] {
                    recentResults.append(
                        SearchResult(
                            title: legacy.title,
                            subtitle: Self.recentSubtitlePrefix + legacy.subtitle,
                            detail: legacy.detail,
                            visual: legacy.visual,
                            action: legacy.action,
                            searchTerms: legacy.searchTerms
                        )
                    )
                } else {
                    continue
                }
                shownRecentKeys.insert(key)
            }
            ranked.removeAll { entry in
                if case .launchApplication(let url) = entry.0.action { return recentApplicationPaths.contains(url.path) }
                return false
            }
            ranked.append(contentsOf: recentResults.enumerated().map { ($0.element, 1_000_000 - $0.offset) })
        }

        ranked.append(contentsOf: additionalResults.compactMap { result in
            let historyKey = UsageHistoryKey.key(for: result.action)
            if let historyKey, shownRecentKeys.contains(historyKey) { return nil }
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

            let usageBoost = historyKey.flatMap { key in
                usageHistoryStore?.recencyBoost(for: key, now: now)
            } ?? 0
            return (result, score + usageBoost)
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
