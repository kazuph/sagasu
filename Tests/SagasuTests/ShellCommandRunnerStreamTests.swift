import Foundation
import Testing
@testable import Sagasu

private let shell = URL(fileURLWithPath: "/bin/sh")

private func childPIDs(matching marker: String) -> [String] {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    process.arguments = ["-f", marker]
    process.standardOutput = pipe
    try? process.run()
    process.waitUntilExit()
    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return output.split(whereSeparator: \.isNewline).map(String.init)
}

@Test
func streamLinesStopsEarlyWhenHandlerReturnsFalseAndLeavesNoProcess() throws {
    let marker = "sagasu-stream-\(UUID().uuidString)"
    let start = Date()
    var count = 0
    let result = try ShellCommandRunner().streamLines(
        executableURL: shell,
        arguments: ["-c", "# \(marker)\nwhile true; do echo /tmp/line; done"],
        timeLimit: 10
    ) { _ in
        count += 1
        return count < 100
    }
    #expect(result.stoppedEarly)
    #expect(result.timedOut == false)
    #expect(count == 100)
    #expect(Date().timeIntervalSince(start) < 2)
    #expect(childPIDs(matching: marker).isEmpty)
}

@Test
func streamLinesReturnsAtTimeLimitWithLinesReadSoFar() throws {
    let marker = "sagasu-timeout-\(UUID().uuidString)"
    let start = Date()
    var lines: [String] = []
    let result = try ShellCommandRunner().streamLines(
        executableURL: shell,
        arguments: ["-c", "# \(marker)\necho first; sleep 30"],
        timeLimit: 0.5
    ) { line in
        lines.append(line)
        return true
    }
    #expect(result.timedOut)
    #expect(result.stoppedEarly)
    #expect(lines == ["first"])
    #expect(Date().timeIntervalSince(start) < 3)
    #expect(childPIDs(matching: marker).isEmpty)
}

@Test
func streamLinesThrowsCancellationErrorWhenTaskIsCancelled() async throws {
    let marker = "sagasu-cancel-\(UUID().uuidString)"
    let task = Task.detached {
        try ShellCommandRunner().streamLines(
            executableURL: shell,
            arguments: ["-c", "# \(marker)\nsleep 30"],
            timeLimit: 20
        ) { _ in true }
    }
    try await Task.sleep(for: .milliseconds(200))
    let start = Date()
    task.cancel()
    do {
        _ = try await task.value
        Issue.record("expected CancellationError")
    } catch is CancellationError {
    }
    #expect(Date().timeIntervalSince(start) < 2)
    #expect(childPIDs(matching: marker).isEmpty)
}

@Test
func streamLinesAssemblesLinesSplitAcrossChunksAndKeepsTrailingLine() throws {
    let long = String(repeating: "x", count: 200_000)
    var lines: [String] = []
    let result = try ShellCommandRunner().streamLines(
        executableURL: shell,
        arguments: ["-c", "printf 'あ/い\\n\(long)\\nlast-without-newline'"]
    ) { line in
        lines.append(line)
        return true
    }
    #expect(result.stoppedEarly == false)
    #expect(lines == ["あ/い", long, "last-without-newline"])
}

@Test
func streamLinesDoesNotFailOnNonZeroExitWhenStoppedEarlyButFailsAtEOF() throws {
    let early = try ShellCommandRunner().streamLines(
        executableURL: shell,
        arguments: ["-c", "echo a; echo b; sleep 5; exit 3"]
    ) { _ in false }
    #expect(early.stoppedEarly)

    #expect(throws: (any Error).self) {
        _ = try ShellCommandRunner().streamLines(executableURL: shell, arguments: ["-c", "echo a; exit 3"]) { _ in true }
    }
}

@Test
func spotlightCollectionStopsAtCandidateLimit() throws {
    let service = FileSearchService(
        scopes: [FileManager.default.temporaryDirectory],
        commonDirectories: [],
        homeDirectory: URL(fileURLWithPath: "/Users/tester"),
        spotlightCollectLimit: 2_000
    )
    var seen = Set<String>()
    let start = Date()
    let collected = try service.collectSpotlightURLs(
        executableURL: shell,
        arguments: ["-c", "i=0; while true; do i=$((i+1)); echo /Users/tester/src/item-$i.txt; done"],
        query: "item",
        usageHistoryStore: nil,
        now: Date(),
        excluding: &seen
    )
    #expect(seen.count == 2_000)
    #expect(collected.urls.count == FileSearchService.spotlightCandidateLimit)
    #expect(collected.rawLineCount == 2_000)
    #expect(Date().timeIntervalSince(start) < 3)
}
