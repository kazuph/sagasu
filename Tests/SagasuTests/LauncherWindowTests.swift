import AppKit
import Testing

@testable import Sagasu

@MainActor
@Test
func launcherWindowRejectsDetachedSearchField() {
    let window = LauncherWindow(
        contentRect: NSRect(x: 0, y: 0, width: 680, height: 392),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    let detachedSearchField = NSTextField()
    window.searchField = detachedSearchField

    #expect(window.focusSearchField() == false)
    #expect(window.searchField == nil)
    #expect(window.firstResponder !== detachedSearchField)
}

@MainActor
@Test
func launcherWindowFocusesAttachedSearchField() throws {
    let window = LauncherWindow(
        contentRect: NSRect(x: 0, y: 0, width: 680, height: 392),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    let searchField = NSTextField()
    let contentView = try #require(window.contentView)
    contentView.addSubview(searchField)
    window.searchField = searchField

    #expect(window.focusSearchField())
    #expect(window.firstResponder === searchField.currentEditor())
    #expect(window.focusSearchField())
    #expect(window.firstResponder === searchField.currentEditor())
}
