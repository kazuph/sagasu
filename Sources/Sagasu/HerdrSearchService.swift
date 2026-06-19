import AppKit
import Foundation

struct HerdrSearchService: Sendable {
    private struct PaneListResponse: Decodable {
        struct Result: Decodable {
            let panes: [Pane]
        }

        let result: Result
    }

    private struct Pane: Decodable {
        let agent: String?
        let agentStatus: String?
        let cwd: String?
        let focused: Bool
        let globalID: String
        let globalNumber: Int?
        let paneID: String
        let paneNumber: Int?
        let shortID: String?
        let terminalID: String?
        let workspaceID: String
        let workspaceNumber: Int?

        enum CodingKeys: String, CodingKey {
            case agent
            case agentStatus = "agent_status"
            case cwd
            case focused
            case globalID = "global_id"
            case globalNumber = "global_number"
            case paneID = "pane_id"
            case paneNumber = "pane_number"
            case shortID = "short_id"
            case terminalID = "terminal_id"
            case workspaceID = "workspace_id"
            case workspaceNumber = "workspace_number"
        }
    }

    private let herdrURL: URL
    private let commandRunner: ShellCommandRunner

    init(
        herdrURL: URL? = nil,
        commandRunner: ShellCommandRunner = ShellCommandRunner()
    ) throws {
        self.herdrURL = try herdrURL ?? Self.resolveHerdrURL()
        self.commandRunner = commandRunner
    }

    func search(query: String, limit: Int = 40) throws -> [SearchResult] {
        let normalizedQuery = SearchMatcher.normalize(query)
        let panes = try listPanes()
        let ranked = panes.compactMap { pane -> (SearchResult, Int)? in
            let result = makeResult(for: pane)
            let primary = SearchMatcher.normalize(result.title)
            let secondary = SearchMatcher.normalize(
                [
                    result.subtitle,
                    result.detail,
                    pane.agent,
                    pane.agentStatus,
                    pane.globalID,
                    pane.paneID,
                    pane.shortID,
                    pane.terminalID,
                    pane.workspaceID,
                    pane.workspaceNumber.map { "workspace \($0) w\($0)" },
                    pane.globalNumber.map { "pane \($0) p\($0)" }
                ]
                    .compactMap { $0 }
                    .joined(separator: " ")
            )

            let score: Int
            if normalizedQuery.isEmpty {
                score = pane.focused ? 1_000 : 500 - (pane.globalNumber ?? 0)
            } else if let matchedScore = SearchMatcher.score(
                query: normalizedQuery,
                primaryText: primary,
                secondaryText: secondary
            ) {
                score = matchedScore + (pane.focused ? 25 : 0)
            } else {
                return nil
            }

            return (result, score)
        }

        return ranked
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.title.localizedCaseInsensitiveCompare(rhs.0.title) == .orderedAscending
            }
            .prefix(limit)
            .map(\.0)
    }

    func focusPane(withID paneID: String) throws {
        _ = try commandRunner.run(executableURL: herdrURL, arguments: ["pane", "focus", paneID])
        activateTerminalApplication()
    }

    private func listPanes() throws -> [Pane] {
        let output = try commandRunner.run(executableURL: herdrURL, arguments: ["pane", "list"])
        guard let data = output.data(using: .utf8) else { return [] }
        return try JSONDecoder().decode(PaneListResponse.self, from: data).result.panes
    }

    private func makeResult(for pane: Pane) -> SearchResult {
        let cwd = pane.cwd ?? ""
        let cwdURL = URL(fileURLWithPath: cwd)
        let directoryName = cwdURL.lastPathComponent.isEmpty ? cwd : cwdURL.lastPathComponent
        let agentText = pane.agent ?? "terminal"
        let statusText = pane.agentStatus ?? "unknown"
        let workspaceText = pane.workspaceNumber.map { "space \($0)" } ?? pane.workspaceID
        let paneText = pane.globalNumber.map { "p_\($0)" } ?? pane.globalID

        return SearchResult(
            title: "\(directoryName) · \(agentText)",
            subtitle: "\(workspaceText) · \(paneText) · \(statusText)",
            detail: cwd,
            visual: .symbol("terminal"),
            action: .focusTerminalPane(pane.globalID)
        )
    }

    private func activateTerminalApplication() {
        let bundleIdentifiers = [
            "com.mitchellh.ghostty",
            "com.googlecode.iterm2",
            "com.apple.Terminal",
            "dev.warp.Warp-Stable",
            "dev.warp.Warp"
        ]

        for bundleIdentifier in bundleIdentifiers {
            if let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
                application.activate(options: [.activateAllWindows])
                return
            }
        }

        if let application = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == "Ghostty" }) {
            application.activate(options: [.activateAllWindows])
        }
    }

    private static func resolveHerdrURL(fileManager: FileManager = .default) throws -> URL {
        let candidates = [
            fileManager.homeDirectoryForCurrentUser.appending(path: ".local/bin/herdr"),
            URL(fileURLWithPath: "/opt/homebrew/bin/herdr"),
            URL(fileURLWithPath: "/usr/local/bin/herdr")
        ]

        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate.path) {
            return candidate
        }

        throw LauncherError.herdrUnavailable
    }
}
