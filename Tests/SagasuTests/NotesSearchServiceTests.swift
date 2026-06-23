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
