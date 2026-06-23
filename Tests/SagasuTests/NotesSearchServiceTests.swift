import Foundation
import Testing
@testable import Sagasu

@Test
func notesSearchScriptUsesValidIgnoringCaseSyntaxForJapaneseQueries() {
    let script = NotesSearchService.searchScript(for: "銀行", limit: 30)

    #expect(script.contains("set queryText to \"銀行\""))
    #expect(script.contains("ignoring case"))
    #expect(script.contains("end ignoring"))
    #expect(script.contains("considering case false") == false)
}

@Test
func notesSearchScriptUsesBoundedTitleFiltering() {
    let script = NotesSearchService.searchScript(for: "銀行", limit: 30)

    #expect(script.contains("with timeout of 5 seconds"))
    #expect(script.contains("notes whose name contains queryText"))
    #expect(script.contains("plaintext of currentNote"))
    #expect(script.contains("every note whose") == false)
    #expect(script.contains("body contains queryText") == false)
}
