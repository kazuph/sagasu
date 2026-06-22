import Foundation
import Testing
@testable import Sagasu

@Test
func githubURLFromGHQPathSupportsGitHubHostPrefix() {
    let url = GitHubSearchService.githubURL(fromGHQPath: "github.com/kazuph/sagasu")

    #expect(url?.absoluteString == "https://github.com/kazuph/sagasu")
    #expect(GitHubSearchService.repositoryName(fromGHQPath: "github.com/kazuph/sagasu") == "kazuph/sagasu")
}

@Test
func githubURLFromGHQPathSupportsOwnerRepositoryPair() {
    let url = GitHubSearchService.githubURL(fromGHQPath: "monocorp-jp/beiju-MOE-PoC")

    #expect(url?.absoluteString == "https://github.com/monocorp-jp/beiju-MOE-PoC")
    #expect(GitHubSearchService.repositoryName(fromGHQPath: "monocorp-jp/beiju-MOE-PoC") == "monocorp-jp/beiju-MOE-PoC")
}

@Test
func githubURLFromGHQPathRejectsInvalidPath() {
    #expect(GitHubSearchService.githubURL(fromGHQPath: "sagasu") == nil)
}
