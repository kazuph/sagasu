import AppKit
import Testing
@testable import Sagasu

@MainActor
@Test
func clipboardImageSearchShowsSaveAndExtractTools() throws {
    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.clearContents()
    pasteboard.writeObjects([makeTestImage()])
    let service = ClipboardImageTextService(pasteboard: pasteboard)

    let results = service.searchResults(query: "image")

    #expect(results.map(\.title) == [
        "Image: Save Clipboard Image",
        "Image: Extract Text from Clipboard Image"
    ])
    #expect(results.map(\.action) == [
        .saveClipboardImage,
        .extractTextFromClipboardImage
    ])
}

@MainActor
@Test
func clipboardImageSearchCanFindExtractToolByOCR() throws {
    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.clearContents()
    pasteboard.writeObjects([makeTestImage()])
    let service = ClipboardImageTextService(pasteboard: pasteboard)

    let results = service.searchResults(query: "ocr")

    #expect(results.map(\.action).contains(.extractTextFromClipboardImage))
}

private func makeTestImage() -> NSImage {
    let image = NSImage(size: NSSize(width: 16, height: 16))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 16, height: 16).fill()
    image.unlockFocus()
    return image
}
