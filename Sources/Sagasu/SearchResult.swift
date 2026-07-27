import Foundation

enum SearchAction: Hashable {
    case launchApplication(URL)
    case openURL(URL)
    case openURLInPreferredBrowser(URL, bundleIdentifier: String)
    case openNote(String)
    case restoreClipboard(UUID)
    case saveClipboardImage
    case extractTextFromClipboardImage
    case focusTerminalPane(String)
    case configureLinearAPIKey
    case copyText(String)
}

enum SearchResultVisual: Hashable {
    case symbol(String)
    case fileIcon(URL)
    case imageThumbnail(URL)
}

struct SearchResult: Hashable, Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let detail: String
    let visual: SearchResultVisual
    let action: SearchAction
    let searchTerms: String

    init(
        title: String,
        subtitle: String,
        detail: String,
        visual: SearchResultVisual,
        action: SearchAction,
        searchTerms: String = ""
    ) {
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.visual = visual
        self.action = action
        self.searchTerms = searchTerms
    }
}
