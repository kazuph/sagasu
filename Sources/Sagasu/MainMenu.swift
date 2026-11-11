import AppKit

extension AppCoordinator {
    /// Accessory apps have no main menu, so text fields never receive
    /// Edit shortcuts (⌘V etc.). Targets are nil so actions go to the first responder.
    static func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        appItem.submenu = NSMenu(title: "Sagasu")
        mainMenu.addItem(appItem)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(makeEditItem("Undo", Selector(("undo:")), "z", [.command]))
        editMenu.addItem(makeEditItem("Redo", Selector(("redo:")), "z", [.command, .shift]))
        editMenu.addItem(.separator())
        editMenu.addItem(makeEditItem("Cut", #selector(NSText.cut(_:)), "x", [.command]))
        editMenu.addItem(makeEditItem("Copy", #selector(NSText.copy(_:)), "c", [.command]))
        editMenu.addItem(makeEditItem("Paste", #selector(NSText.paste(_:)), "v", [.command]))
        editMenu.addItem(makeEditItem("Select All", #selector(NSText.selectAll(_:)), "a", [.command]))

        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        return mainMenu
    }

    private static func makeEditItem(
        _ title: String,
        _ action: Selector,
        _ key: String,
        _ modifiers: NSEvent.ModifierFlags
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = nil
        return item
    }
}
