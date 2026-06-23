import Foundation

struct LinearSearchService: Sendable {
    private struct GraphQLRequest: Encodable {
        struct Variables: Encodable {
            let query: String
            let first: Int
        }

        let query: String
        let variables: Variables
    }

    private struct GraphQLResponse: Decodable {
        struct GraphQLError: Decodable {
            let message: String
        }

        let data: DataPayload?
        let errors: [GraphQLError]?
    }

    private struct DataPayload: Decodable {
        let searchIssues: IssueConnection
    }

    private struct IssueConnection: Decodable {
        let nodes: [Issue]
    }

    private struct Issue: Decodable {
        struct Team: Decodable {
            let key: String
            let name: String
        }

        struct State: Decodable {
            let name: String
        }

        struct User: Decodable {
            let name: String
        }

        let identifier: String
        let title: String
        let url: URL
        let team: Team
        let state: State
        let assignee: User?
    }

    private let credentialStore: LinearCredentialStore
    private let urlSession: URLSession
    private let endpoint = URL(string: "https://api.linear.app/graphql")!

    init(
        credentialStore: LinearCredentialStore = LinearCredentialStore(),
        urlSession: URLSession = .shared
    ) {
        self.credentialStore = credentialStore
        self.urlSession = urlSession
    }

    func hasAPIKey() -> Bool {
        credentialStore.hasAPIKey()
    }

    func searchIssues(query: String, limit: Int = 40) async throws -> [SearchResult] {
        let trimmedQuery = query.condensedWhitespace()
        guard trimmedQuery.isEmpty == false else { return [] }
        guard let apiKey = try credentialStore.apiKey(), apiKey.isEmpty == false else {
            return [Self.configureAPIKeyResult()]
        }

        let requestBody = GraphQLRequest(
            query: Self.issueSearchQuery,
            variables: GraphQLRequest.Variables(query: trimmedQuery, first: limit)
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await urlSession.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           (200..<300).contains(httpResponse.statusCode) == false {
            throw LauncherError.linearRequestFailed("HTTP \(httpResponse.statusCode)")
        }
        return try Self.searchResults(from: data)
    }

    static func configureAPIKeyResult() -> SearchResult {
        SearchResult(
            title: "Set Linear API Key",
            subtitle: "Save a personal Linear API key in macOS Keychain",
            detail: "Linear",
            visual: .symbol("key"),
            action: .configureLinearAPIKey
        )
    }

    static func searchResults(from data: Data) throws -> [SearchResult] {
        let response = try JSONDecoder().decode(GraphQLResponse.self, from: data)
        if let errors = response.errors, errors.isEmpty == false {
            throw LauncherError.linearRequestFailed(errors.map(\.message).joined(separator: " / "))
        }
        return response.data?.searchIssues.nodes.map(issueResult) ?? []
    }

    private static func issueResult(_ issue: Issue) -> SearchResult {
        let assignee = issue.assignee?.name ?? "Unassigned"
        return SearchResult(
            title: "\(issue.identifier) \(issue.title)",
            subtitle: "\(issue.team.key) · \(issue.state.name) · \(assignee)",
            detail: issue.url.absoluteString,
            visual: .symbol("line.3.horizontal.decrease.circle"),
            action: .openURLInPreferredBrowser(issue.url, bundleIdentifier: WebRouteSearchService.preferredBrowserBundleIdentifier)
        )
    }

    private static let issueSearchQuery = """
    query SagasuLinearIssueSearch($query: String, $first: Int) {
      searchIssues(term: $query, first: $first) {
        nodes {
          identifier
          title
          url
          team {
            key
            name
          }
          state {
            name
          }
          assignee {
            name
          }
        }
      }
    }
    """
}
