import Foundation
import Testing
@testable import Sagasu

@Test
func defaultsToApplications() {
    let parsed = SearchModeParser.parse("safari")

    #expect(parsed.mode == .applications)
    #expect(parsed.query == "safari")
    #expect(parsed.clipboardImageOnly == false)
}

@Test
func parsesFilePrefix() {
    let parsed = SearchModeParser.parse("f design doc")

    #expect(parsed.mode == .files)
    #expect(parsed.query == "design doc")
    #expect(parsed.clipboardImageOnly == false)
}

@Test
func parsesUppercaseFilePrefixWithEmptyQuery() {
    let parsed = SearchModeParser.parse("F ")

    #expect(parsed.mode == .files)
    #expect(parsed.query == "")
    #expect(parsed.clipboardImageOnly == false)
}

@Test
func parsesDirectoryPrefix() {
    let parsed = SearchModeParser.parse("d down")

    #expect(parsed.mode == .directories)
    #expect(parsed.query == "down")
    #expect(parsed.clipboardImageOnly == false)
}

@Test
func parsesTerminalPrefix() {
    let parsed = SearchModeParser.parse("t sagasu")

    #expect(parsed.mode == .terminals)
    #expect(parsed.query == "sagasu")
    #expect(parsed.clipboardImageOnly == false)
}

@Test
func parsesNotesPrefixCaseInsensitively() {
    let parsed = SearchModeParser.parse("N meeting")

    #expect(parsed.mode == .notes)
    #expect(parsed.query == "meeting")
    #expect(parsed.clipboardImageOnly == false)
}

@Test
func parsesClipboardPrefix() {
    let parsed = SearchModeParser.parse("v copied text")

    #expect(parsed.mode == .clipboard)
    #expect(parsed.query == "copied text")
    #expect(parsed.clipboardImageOnly == false)
}

@Test
func parsesClipboardImagePrefix() {
    let parsed = SearchModeParser.parse("vi concept")

    #expect(parsed.mode == .clipboard)
    #expect(parsed.query == "concept")
    #expect(parsed.clipboardImageOnly == true)
}

@Test
func shellCommandRunnerHandlesLargeOutput() throws {
    let output = try ShellCommandRunner().run(
        executableURL: URL(fileURLWithPath: "/usr/bin/jot"),
        arguments: ["40000"]
    )

    let lines = output.split(whereSeparator: { $0.isNewline })
    #expect(lines.count == 40_000)
    #expect(lines.first == "1")
    #expect(lines.last == "40000")
}
