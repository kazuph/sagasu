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
                "name": "In Progress",
                "type": "started"
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
func linearSearchFiltersDoneAndSortsByWorkflowPriority() throws {
    let data = """
    {
      "data": {
        "searchIssues": {
          "nodes": [
            {
              "identifier": "MON-1",
              "title": "Backlog item",
              "url": "https://linear.app/mono/issue/MON-1/backlog-item",
              "team": { "key": "MON", "name": "Monocorp" },
              "state": { "name": "Backlog", "type": "backlog" },
              "assignee": null
            },
            {
              "identifier": "MON-2",
              "title": "Done item",
              "url": "https://linear.app/mono/issue/MON-2/done-item",
              "team": { "key": "MON", "name": "Monocorp" },
              "state": { "name": "Done", "type": "completed" },
              "assignee": null
            },
            {
              "identifier": "MON-3",
              "title": "Todo item",
              "url": "https://linear.app/mono/issue/MON-3/todo-item",
              "team": { "key": "MON", "name": "Monocorp" },
              "state": { "name": "Todo", "type": "unstarted" },
              "assignee": null
            },
            {
              "identifier": "MON-4",
              "title": "In Progress item",
              "url": "https://linear.app/mono/issue/MON-4/in-progress-item",
              "team": { "key": "MON", "name": "Monocorp" },
              "state": { "name": "In Progress", "type": "started" },
              "assignee": null
            },
            {
              "identifier": "MON-5",
              "title": "Human Review item",
              "url": "https://linear.app/mono/issue/MON-5/human-review-item",
              "team": { "key": "MON", "name": "Monocorp" },
              "state": { "name": "Human Review", "type": "started" },
              "assignee": null
            }
          ]
        }
      }
    }
    """.data(using: .utf8)!

    let results = try LinearSearchService.searchResults(from: data)

    #expect(results.map(\.title) == [
        "MON-5 Human Review item",
        "MON-4 In Progress item",
        "MON-3 Todo item",
        "MON-1 Backlog item"
    ])
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
