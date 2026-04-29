import Foundation

struct WebRouteSearchService: Sendable {
    static let preferredBrowserBundleIdentifier = "com.google.Chrome"

    func search(query: String) -> [SearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isEmpty == false else { return [] }

        return [
            SearchResult(
                title: "Search Google in Chrome",
                subtitle: trimmedQuery,
                detail: "google.com",
                visual: .symbol("globe"),
                action: .openURLInPreferredBrowser(googleSearchURL(for: trimmedQuery), bundleIdentifier: Self.preferredBrowserBundleIdentifier)
            ),
            SearchResult(
                title: "Ask ChatGPT in Chrome",
                subtitle: trimmedQuery,
                detail: "chatgpt.com",
                visual: .symbol("sparkles"),
                action: .openURLInPreferredBrowser(chatGPTURL(for: trimmedQuery), bundleIdentifier: Self.preferredBrowserBundleIdentifier)
            )
        ]
    }

    private func googleSearchURL(for query: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.google.com"
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "q", value: query)
        ]
        return components.url ?? URL(string: "https://www.google.com/search")!
    }

    private func chatGPTURL(for query: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "chatgpt.com"
        components.path = "/"
        components.queryItems = [
            URLQueryItem(name: "prompt", value: query),
            URLQueryItem(name: "autosubmit", value: "false")
        ]
        return components.url ?? URL(string: "https://chatgpt.com/")!
    }
}
