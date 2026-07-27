import Foundation

struct MacOSSettingsSearchService {
    private static let extensionPointIdentifier = "com.apple.Settings.extension.ui"
    private static let systemExtensionsURL = URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions", isDirectory: true)
    private static let systemSettingsPluginsURL = URL(
        fileURLWithPath: "/System/Applications/System Settings.app/Contents/PlugIns",
        isDirectory: true
    )

    private let additionalResults: [SearchResult]

    init(preferredLocalizations: [String] = Locale.preferredLanguages) {
        additionalResults = Self.loadSettings(
            fileManager: .default,
            extensionRoots: [Self.systemExtensionsURL, Self.systemSettingsPluginsURL],
            preferredLocalizations: preferredLocalizations
        )
    }

    func results() -> [SearchResult] {
        additionalResults
    }

    private static func loadSettings(
        fileManager: FileManager,
        extensionRoots: [URL],
        preferredLocalizations: [String]
    ) -> [SearchResult] {
        return extensionRoots.flatMap { root -> [SearchResult] in
            guard let bundleURLs = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }

            return bundleURLs.compactMap { bundleURL in
                loadSetting(
                    at: bundleURL,
                    preferredLocalizations: preferredLocalizations
                )
            }
        }
    }

    private static func loadSetting(
        at bundleURL: URL,
        preferredLocalizations: [String]
    ) -> SearchResult? {
        guard bundleURL.pathExtension.caseInsensitiveCompare("appex") == .orderedSame,
              let bundle = Bundle(url: bundleURL),
              let info = bundle.infoDictionary,
              let extensionAttributes = info["EXAppExtensionAttributes"] as? [String: Any],
              extensionAttributes["EXExtensionPointIdentifier"] as? String == extensionPointIdentifier,
              let settingsAttributes = extensionAttributes["SettingsExtensionAttributes"] as? [String: Any],
              settingsAttributes["allowsXAppleSystemPreferencesURLScheme"] as? Bool == true,
              let bundleIdentifier = bundle.bundleIdentifier,
              let url = URL(string: "x-apple.systempreferences:\(bundleIdentifier)") else {
            return nil
        }

        let localizedInfo = loadLocalizedInfo(in: bundle)
        let localization = preferredLocalization(
            from: Set(localizedInfo.keys).union(bundle.localizations),
            preferredLocalizations: preferredLocalizations
        )
        let displayName = localization
            .flatMap { localizedInfo[$0]?["CFBundleDisplayName"] as? String }
            ?? (info["CFBundleDisplayName"] as? String)
            ?? bundleIdentifier
        let searchTerms = settingsAttributes["searchTermsFileName"]
            .flatMap { $0 as? String }
            .flatMap { searchTermsFileName in
                loadSearchTerms(
                    in: bundle,
                    fileName: searchTermsFileName,
                    localization: localization
                )
            }
            ?? ""

        return SearchResult(
            title: displayName,
            subtitle: "macOS Settings",
            detail: bundleIdentifier,
            visual: .symbol("gearshape"),
            action: .openURL(url),
            searchTerms: searchTerms
        )
    }

    private static func loadLocalizedInfo(in bundle: Bundle) -> [String: [String: Any]] {
        guard let url = bundle.url(forResource: "InfoPlist", withExtension: "loctable"),
              let data = try? Data(contentsOf: url),
              let propertyList = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let values = propertyList as? [String: [String: Any]] else {
            return [:]
        }
        return values
    }

    private static func preferredLocalization(
        from availableLocalizations: Set<String>,
        preferredLocalizations: [String]
    ) -> String? {
        let localizations = availableLocalizations.filter { $0 != "LocProvenance" }
        return Bundle.preferredLocalizations(
            from: Array(localizations),
            forPreferences: preferredLocalizations
        ).first
    }

    private static func loadSearchTerms(
        in bundle: Bundle,
        fileName: String,
        localization: String?
    ) -> String? {
        guard let localization,
              let url = bundle.url(
                forResource: fileName,
                withExtension: "searchTerms",
                subdirectory: nil,
                localization: localization
              ),
              let data = try? Data(contentsOf: url),
              let propertyList = try? PropertyListSerialization.propertyList(from: data, format: nil) else {
            return nil
        }

        let terms = localizableStrings(in: propertyList)
        guard terms.isEmpty == false else { return nil }
        return terms.joined(separator: " ")
    }

    private static func localizableStrings(in value: Any) -> [String] {
        if let dictionary = value as? [String: Any] {
            let strings = (dictionary["localizableStrings"] as? [[String: Any]] ?? []).flatMap { value in
                [value["title"] as? String, value["index"] as? String].compactMap { $0 }
            }
            return strings + dictionary.values.flatMap(localizableStrings(in:))
        }

        if let array = value as? [Any] {
            return array.flatMap(localizableStrings(in:))
        }

        return []
    }
}
