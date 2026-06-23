import Foundation
import Testing
@testable import Sagasu

@Test
func linearSearchDecodesIssueSearchResults() throws {
    let data = """
    {
      "data": {
        "searchIssues": {
          "nodes": [
            {
              "identifier": "MON-123",
              "title": "Fix launcher search",
              "url": "https://linear.app/mono/issue/MON-123/fix-launcher-search",
              "team": {
                "key": "MON",
                "name": "Monocorp"
              },
              "state": {
                "name": "In Progress"
              },
              "assignee": {
                "name": "Kazuhiro"
              }
            }
          ]
        }
      }
    }
    """.data(using: .utf8)!

    let results = try LinearSearchService.searchResults(from: data)

    #expect(results.count == 1)
    #expect(results[0].title == "MON-123 Fix launcher search")
    #expect(results[0].subtitle == "MON · In Progress · Kazuhiro")
    #expect(results[0].detail == "https://linear.app/mono/issue/MON-123/fix-launcher-search")
}

@Test
func linearSearchSurfacesGraphQLErrors() throws {
    let data = """
    {
      "errors": [
        {
          "message": "Authentication required"
        }
      ]
    }
    """.data(using: .utf8)!

    #expect(throws: LauncherError.self) {
        _ = try LinearSearchService.searchResults(from: data)
    }
}

@Test
func linearSearchExtractsGraphQLErrorMessageFromHTTPFailureBody() {
    let data = """
    {
      "errors": [
        {
          "message": "Variable \\"$query\\" of type \\"String\\" used in position expecting type \\"String!\\"."
        }
      ]
    }
    """.data(using: .utf8)!

    #expect(LinearSearchService.graphQLErrorMessage(from: data) == "Variable \"$query\" of type \"String\" used in position expecting type \"String!\".")
}
