import Foundation

struct GitHubSearchService: Sendable {
    private struct RepositoryResponse: Decodable {
        let fullName: String
        let description: String?
        let url: URL
    }

    private struct UserResponse: Decodable {
        let login: String
    }

    private struct OrganizationResponse: Decodable {
        let login: String
    }

    private struct IssueResponse: Decodable {
        struct Repository: Decodable {
            let nameWithOwner: String
        }

        let title: String
        let url: URL
        let repository: Repository
        let state: String
        let number: Int
    }

    private let commandRunner: ShellCommandRunner

    init(commandRunner: ShellCommandRunner = ShellCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func searchOwnedRepositories(query: String, limit: Int = 40) throws -> [SearchResult] {
        let ghqResults = searchGHQRepositories(query: query, limit: limit)
        let remainingLimit = max(0, limit - ghqResults.count)
        guard remainingLimit > 0 else { return ghqResults }

        var seen = Set(ghqResults.compactMap { Self.repositoryKey(from: $0.action) })
        let githubResults = try searchGitHubRepositories(query: query, scope: .owned, limit: remainingLimit)
            .filter { result in
                guard let key = Self.repositoryKey(from: result.action) else { return true }
                return seen.insert(key).inserted
            }
        return ghqResults + githubResults
    }

    func searchGlobalRepositories(query: String, limit: Int = 40) throws -> [SearchResult] {
        try searchGitHubRepositories(query: query, scope: .global, limit: limit)
    }

    func searchGHQRepositories(query: String, limit: Int = 40) -> [SearchResult] {
        guard let ghqURL = executableURL(named: "ghq") else { return [] }
        let output = (try? commandRunner.run(executableURL: ghqURL, arguments: ["list"])) ?? ""
        let terms = query.condensedWhitespace().lowercased().split(separator: " ").map(String.init)

        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> SearchResult? in
                makeGHQResult(from: String(line), terms: terms)
            }
            .prefix(limit)
            .map { $0 }
    }

    func searchIssues(query: String, limit: Int = 40) throws -> [SearchResult] {
        try searchIssuesOrPullRequests(command: "issues", query: query, limit: limit)
    }

    func searchPullRequests(query: String, limit: Int = 40) throws -> [SearchResult] {
        try searchIssuesOrPullRequests(command: "prs", query: query, limit: limit)
    }

    func isGitHubCLIAvailable() -> Bool {
        executableURL(named: "gh") != nil
    }

    private enum RepositoryScope {
        case owned
        case global
    }

    private func searchGitHubRepositories(query: String, scope: RepositoryScope, limit: Int) throws -> [SearchResult] {
        let trimmedQuery = query.condensedWhitespace()
        guard trimmedQuery.isEmpty == false, let ghURL = executableURL(named: "gh") else { return [] }

        var arguments = ["search", "repos", trimmedQuery, "--limit", "\(limit)", "--json", "fullName,description,url"]
        if scope == .owned {
            let owners = try ownedLogins()
            guard owners.isEmpty == false else { return [] }
            for owner in owners {
                arguments.append(contentsOf: ["--owner", owner])
            }
        }

        let output = try commandRunner.run(executableURL: ghURL, arguments: arguments)
        let repositories = try JSONDecoder().decode([RepositoryResponse].self, from: Data(output.utf8))
        return repositories.map { repositoryResult($0, source: scope == .owned ? "GitHub repository" : "GitHub global repository") }
    }

    private func searchIssuesOrPullRequests(command: String, query: String, limit: Int) throws -> [SearchResult] {
        let trimmedQuery = query.condensedWhitespace()
        guard trimmedQuery.isEmpty == false, let ghURL = executableURL(named: "gh") else { return [] }

        let owners = try ownedLogins()
        guard owners.isEmpty == false else { return [] }

        var arguments = ["search", command, trimmedQuery, "--limit", "\(limit)", "--json", "title,url,repository,state,number"]
        for owner in owners {
            arguments.append(contentsOf: ["--owner", owner])
        }

        let output = try commandRunner.run(executableURL: ghURL, arguments: arguments)
        let issues = try JSONDecoder().decode([IssueResponse].self, from: Data(output.utf8))
        return issues.map { issue in
            SearchResult(
                title: issue.title,
                subtitle: "\(issue.repository.nameWithOwner)#\(issue.number) · \(issue.state)",
                detail: issue.url.absoluteString,
                visual: .symbol(command == "prs" ? "arrow.triangle.pull" : "smallcircle.filled.circle"),
                action: .openURLInPreferredBrowser(issue.url, bundleIdentifier: WebRouteSearchService.preferredBrowserBundleIdentifier)
            )
        }
    }

    private func ownedLogins() throws -> [String] {
        guard let ghURL = executableURL(named: "gh") else { return [] }
        let userOutput = try commandRunner.run(executableURL: ghURL, arguments: ["api", "user", "--jq", "{login: .login}"])
        let user = try JSONDecoder().decode(UserResponse.self, from: Data(userOutput.utf8))
        let orgOutput = try commandRunner.run(executableURL: ghURL, arguments: ["api", "user/orgs", "--jq", "[.[] | {login: .login}]"])
        let organizations = (try? JSONDecoder().decode([OrganizationResponse].self, from: Data(orgOutput.utf8))) ?? []

        var seen: Set<String> = []
        return ([user.login] + organizations.map(\.login)).filter { seen.insert($0).inserted }
    }

    private func repositoryResult(_ repository: RepositoryResponse, source: String) -> SearchResult {
        SearchResult(
            title: repository.fullName,
            subtitle: repository.description?.nilIfEmpty ?? source,
            detail: repository.url.absoluteString,
            visual: .symbol("chevron.left.forwardslash.chevron.right"),
            action: .openURLInPreferredBrowser(repository.url, bundleIdentifier: WebRouteSearchService.preferredBrowserBundleIdentifier)
        )
    }

    private func makeGHQResult(from line: String, terms: [String]) -> SearchResult? {
        let repositoryPath = line.condensedWhitespace()
        guard repositoryPath.isEmpty == false else { return nil }
        let searchable = repositoryPath.lowercased()
        guard terms.allSatisfy({ searchable.contains($0) }) else { return nil }
        guard let url = Self.githubURL(fromGHQPath: repositoryPath) else { return nil }
        let title = Self.repositoryName(fromGHQPath: repositoryPath)

        return SearchResult(
            title: title,
            subtitle: "ghq · \(repositoryPath)",
            detail: url.absoluteString,
            visual: .symbol("externaldrive"),
            action: .openURLInPreferredBrowser(url, bundleIdentifier: WebRouteSearchService.preferredBrowserBundleIdentifier)
        )
    }

    private func executableURL(named name: String) -> URL? {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/bin/\(name)"
        ]
        return candidates
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func githubURL(fromGHQPath path: String) -> URL? {
        let components = path.split(separator: "/").map(String.init)
        guard components.count >= 2 else { return nil }
        let ownerAndRepo: ArraySlice<String>
        if let githubIndex = components.firstIndex(of: "github.com") {
            ownerAndRepo = components.dropFirst(githubIndex + 1).prefix(2)
        } else {
            ownerAndRepo = components.suffix(2)
        }
        guard ownerAndRepo.count == 2 else { return nil }
        return URL(string: "https://github.com/\(ownerAndRepo.joined(separator: "/"))")
    }

    static func repositoryName(fromGHQPath path: String) -> String {
        guard let url = githubURL(fromGHQPath: path) else { return path }
        return url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func repositoryKey(from action: SearchAction) -> String? {
        guard case .openURLInPreferredBrowser(let url, _) = action else { return nil }
        return url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
