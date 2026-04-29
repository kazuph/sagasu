import Foundation

struct NotesSearchService: Sendable {
    func search(query: String, limit: Int = 30) throws -> [SearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isEmpty == false else { return [] }

        let output = try executeAppleScript(script(for: trimmedQuery, limit: limit))
        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                let fields = String(line).components(separatedBy: "\t")
                guard fields.count >= 3 else { return nil }
                let noteID = fields[0]
                let title = fields[1]
                let body = Self.cleanPreview(fields[2])

                return SearchResult(
                    title: title.isEmpty ? "Untitled Note" : title,
                    subtitle: body.truncated(limit: 120),
                    detail: noteID,
                    visual: .symbol("note.text"),
                    action: .openNote(noteID)
                )
            }
    }

    static func openNote(withID noteID: String) throws {
        let script = """
        tell application "Notes"
            activate
            set targetNote to first note whose id is "\(appleScriptEscaped(noteID))"
            show targetNote
        end tell
        """

        _ = try executeAppleScript(script)
    }

    private func script(for query: String, limit: Int) -> String {
        """
        set queryText to "\(appleScriptEscaped(query))"
        set maximumCount to \(limit)
        set outputLines to {}
        tell application "Notes"
            considering case false
                set matchedNotes to every note whose name contains queryText or body contains queryText
            end considering
            set noteCount to count of matchedNotes
            if noteCount > maximumCount then
                set noteCount to maximumCount
            end if
            repeat with idx from 1 to noteCount
                set currentNote to item idx of matchedNotes
                set end of outputLines to (my sanitized(id of currentNote) & tab & my sanitized(name of currentNote) & tab & my sanitized(body of currentNote))
            end repeat
        end tell
        set AppleScript's text item delimiters to linefeed
        return outputLines as text

        on sanitized(valueText)
            set textValue to valueText as text
            set textValue to do shell script "printf %s " & quoted form of textValue & " | tr '\\n\\r\\t' '   '"
            return textValue
        end sanitized
        """
    }

    private static func cleanPreview(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .condensedWhitespace()
    }
}

private func appleScriptEscaped(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

private func executeAppleScript(_ script: String) throws -> String {
    let process = Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    do {
        try process.run()
    } catch {
        throw LauncherError.notesAutomationFailed(error.localizedDescription)
    }

    process.waitUntilExit()

    let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

    guard process.terminationStatus == 0 else {
        throw LauncherError.notesAutomationFailed(errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    return output
}
