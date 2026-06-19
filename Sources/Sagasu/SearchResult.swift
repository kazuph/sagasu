import Foundation

enum SearchAction: Hashable {
    case launchApplication(URL)
    case openURL(URL)
    case openURLInPreferredBrowser(URL, bundleIdentifier: String)
    case openNote(String)
    case restoreClipboard(UUID)
    case saveClipboardImageAndExtractText
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
}
