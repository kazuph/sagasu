import Foundation
import Testing
@testable import Sagasu

@Test
func clipboardEntryExpiresAfterThreeMonthsByDefault() {
    let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let entry = ClipboardEntry(
        id: UUID(),
        contentHash: "hash",
        capturedAt: capturedAt,
        lastUsedAt: nil,
        pinnedAt: nil,
        content: .text("hello")
    )

    let expirationDate = entry.expirationDate(calendar: Calendar(identifier: .gregorian))
    let expected = Calendar(identifier: .gregorian).date(byAdding: .month, value: 3, to: capturedAt)
    #expect(expirationDate == expected)
}

@Test
func clipboardEntryExtendsSixMonthsAfterReuse() {
    let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let lastUsedAt = Date(timeIntervalSince1970: 1_710_000_000)
    let entry = ClipboardEntry(
        id: UUID(),
        contentHash: "hash",
        capturedAt: capturedAt,
        lastUsedAt: lastUsedAt,
        pinnedAt: nil,
        content: .text("hello")
    )

    let expirationDate = entry.expirationDate(calendar: Calendar(identifier: .gregorian))
    let expected = Calendar(identifier: .gregorian).date(byAdding: .month, value: 6, to: lastUsedAt)
    #expect(expirationDate == expected)
}

@Test
func pinnedClipboardEntryDoesNotExpire() {
    let entry = ClipboardEntry(
        id: UUID(),
        contentHash: "hash",
        capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
        lastUsedAt: nil,
        pinnedAt: Date(timeIntervalSince1970: 1_720_000_000),
        content: .text("hello")
    )

    #expect(entry.expirationDate() == nil)
    #expect(entry.isExpired(asOf: .distantFuture) == false)
}
