import Foundation
import Testing
@testable import Sagasu

@Test
func webRoutesAreEmptyForBlankQuery() {
    let results = WebRouteSearchService().search(query: "   ")

    #expect(results.isEmpty)
}

@Test
func webRoutesIncludeGoogleAndChatGPT() {
    let results = WebRouteSearchService().search(query: "swift launcher")

    #expect(results.count == 2)
    #expect(results.map(\.title) == ["Search Google in Chrome", "Ask ChatGPT in Chrome"])

    guard case .openURLInPreferredBrowser(let googleURL, let googleBundleIdentifier) = results[0].action else {
        Issue.record("First route should open Google in preferred browser")
        return
    }

    guard case .openURLInPreferredBrowser(let chatGPTURL, let chatGPTBundleIdentifier) = results[1].action else {
        Issue.record("Second route should open ChatGPT in preferred browser")
        return
    }

    let googleComponents = URLComponents(url: googleURL, resolvingAgainstBaseURL: false)
    let chatGPTComponents = URLComponents(url: chatGPTURL, resolvingAgainstBaseURL: false)

    #expect(googleBundleIdentifier == "com.google.Chrome")
    #expect(chatGPTBundleIdentifier == "com.google.Chrome")
    #expect(googleComponents?.host == "www.google.com")
    #expect(googleComponents?.queryItems?.first(where: { $0.name == "q" })?.value == "swift launcher")
    #expect(chatGPTComponents?.host == "chatgpt.com")
    #expect(chatGPTComponents?.queryItems?.first(where: { $0.name == "prompt" })?.value == "swift launcher")
    #expect(chatGPTComponents?.queryItems?.first(where: { $0.name == "autosubmit" })?.value == "false")
}
