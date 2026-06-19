import Foundation
import Testing
@testable import Sagasu

@Test
func applicationSearchIncludesFinder() {
    let service = ApplicationSearchService()

    let results = service.search(query: "finder", limit: 10)

    #expect(results.contains { result in
        result.title == "Finder" &&
            result.detail == "/System/Library/CoreServices/Finder.app"
    })
}
