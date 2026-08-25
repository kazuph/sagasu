import AppKit
import Carbon
import ServiceManagement
import SwiftUI

@MainActor
final class AppCoordinator: NSObject, ObservableObject, NSMenuDelegate {
    let clipboardStore: ClipboardHistoryStore
    let clipboardImageTextService: ClipboardImageTextService
    let linearCredentialStore: LinearCredentialStore
    let searchEngine: SearchEngine
    let searchViewModel: SearchViewModel

    private var launcherHotKeyMonitor: LauncherHotKeyMonitor?
    private var launcherHotKeyMonitors: [HotKeyMonitor] = []
    private var windowHotKeyMonitor: WindowHotKeyMonitor?
    private var windowHotKeyMonitors: [HotKeyMonitor] = []
    private let debugWindowCommandNotification = Notification.Name("com.kazuph.sagasu.debug.windowCommand")
    private let windowManager = WindowManager()
    private var launcherPanelController: LauncherPanelController?
    private var statusItem: NSStatusItem?
    private var launchAtLoginMenuItem: NSMenuItem?
    private var didPresentAccessibilityPermissionError = false
    private var lastLauncherHotKey: LauncherHotKey?
    private var lastLauncherHotKeyAt = Date.distantPast
    private var lastWindowCommand: WindowManager.Command?
    private var lastWindowCommandAt = Date.distantPast
    private var lastWindowCommandSource: String?
    private var applicationBeforeLauncher: NSRunningApplication?
    private var isPresentingLinearAPIKeyDialog = false
    private(set) var isQuitRequested = false

    var shouldHideLauncherOnApplicationResignActive: Bool {
        isPresentingLinearAPIKeyDialog == false
    }

    override init() {
        let clipboardStore = ClipboardHistoryStore()
        let clipboardImageTextService = ClipboardImageTextService()
        let linearCredentialStore = LinearCredentialStore()
        let searchEngine = SearchEngine(
            linearSearchService: LinearSearchService(credentialStore: linearCredentialStore),
            clipboardStore: clipboardStore,
            clipboardImageTextService: clipboardImageTextService
        )
        self.clipboardStore = clipboardStore
        self.clipboardImageTextService = clipboardImageTextService
        self.linearCredentialStore = linearCredentialStore
        self.searchEngine = searchEngine
        self.searchViewModel = SearchViewModel(searchEngine: searchEngine)
        super.init()
        self.searchViewModel.actionHandler = { [weak self] action in
            self?.perform(action: action)
        }
        self.searchViewModel.clipboardPinToggleHandler = { [weak self] entryID in
            try self?.clipboardStore.togglePin(entryID: entryID)
        }
        self.searchViewModel.clipboardDeleteHandler = { [weak self] entryID in
            try self?.clipboardStore.delete(entryID: entryID)
        }
        self.searchViewModel.linearAPIKeyNeededHandler = { [weak self] in
            self?.presentLinearAPIKeyDialog()
        }
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    func start(configuration: LaunchConfiguration = .current) {
        NSApp.applicationIconImage = SagasuIcon.appIcon()
        _ = WindowManager.requestAccessibilityPermissionIfNeeded()
        configureStatusItem()

        do {
            launcherHotKeyMonitor = try LauncherHotKeyMonitor { [weak self] hotKey in
                Task { @MainActor in
                    self?.handleLauncherHotKey(hotKey)
                }
            }
        } catch {
            fputs("Sagasu launcher event tap failed: \(error.localizedDescription)\n", stderr)
        }

        configureLauncherCarbonHotKeys()

        configureWindowManagementHotKeys()
        configureDebugWindowCommandsIfNeeded()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let rootView = SearchRootView(viewModel: self.searchViewModel) { [weak self] in
                self?.hideLauncher()
            }
            let panelController = LauncherPanelController(rootView: rootView)
            panelController.onDismiss = { [weak self] in
                self?.searchViewModel.dismiss()
                self?.ensureEventTapsEnabled()
            }
            self.launcherPanelController = panelController
            self.ensureEventTapsEnabled()

            if configuration.showOnLaunch {
                self.searchViewModel.prepareForPresentation()
                self.launcherPanelController?.show()
            }

            if let snapshotPath = configuration.snapshotPath {
                let snapshotURL = URL(fileURLWithPath: snapshotPath)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    self?.captureSnapshotAndTerminate(at: snapshotURL)
                }
            }
        }
    }

    func toggleLauncher() {
        toggleLauncher(initialQuery: "")
    }

    private func handleLauncherHotKey(_ hotKey: LauncherHotKey) {
        let now = Date()
        if lastLauncherHotKey == hotKey,
           now.timeIntervalSince(lastLauncherHotKeyAt) < 0.08 {
            return
        }

        lastLauncherHotKey = hotKey
        lastLauncherHotKeyAt = now

        switch hotKey {
        case .defaultSearch:
            toggleLauncher(initialQuery: "")
        case .clipboardHistory:
            showLauncher(initialQuery: "v ")
        }
    }

    private func toggleLauncher(initialQuery: String) {
        guard let launcherPanelController else { return }

        if launcherPanelController.isVisible {
            hideLauncher()
        } else {
            rememberApplicationBeforeLauncher()
            searchViewModel.prepareForPresentation(initialQuery: initialQuery)
            launcherPanelController.show()
        }
    }

    private func showLauncher(initialQuery: String) {
        rememberApplicationBeforeLauncher()
        searchViewModel.prepareForPresentation(initialQuery: initialQuery)
        launcherPanelController?.show()
    }

    func hideLauncher() {
        launcherPanelController?.hide()
    }

    @objc private func showLauncherFromStatusItem(_ sender: Any?) {
        searchViewModel.prepareForPresentation()
        launcherPanelController?.show()
    }

    @objc private func toggleLaunchAtLoginFromStatusItem(_ sender: Any?) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            presentLaunchAtLoginError(error)
        }
        updateLaunchAtLoginMenuItem()
    }

    @objc private func quitFromStatusItem(_ sender: Any?) {
        isQuitRequested = true
        NSApp.terminate(sender)
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: 24)
        statusItem.button?.title = "🔭"
        statusItem.button?.font = .systemFont(ofSize: 16)
        statusItem.button?.toolTip = "Sagasu"

        let menu = NSMenu()
        menu.delegate = self
        let titleItem = NSMenuItem(title: "🔭 Sagasu", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open Sagasu", action: #selector(showLauncherFromStatusItem(_:)), keyEquivalent: ""))
        let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLoginFromStatusItem(_:)), keyEquivalent: "")
        menu.addItem(launchAtLoginItem)
        launchAtLoginMenuItem = launchAtLoginItem
        menu.addItem(.separator())
        let windowManagementItem = NSMenuItem(title: "Window Management", action: nil, keyEquivalent: "")
        windowManagementItem.isEnabled = false
        menu.addItem(windowManagementItem)
        for title in Self.windowManagementShortcutTitles {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Sagasu", action: #selector(quitFromStatusItem(_:)), keyEquivalent: "q"))
        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
        self.statusItem = statusItem
        updateLaunchAtLoginMenuItem()
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateLaunchAtLoginMenuItem()
    }

    private func updateLaunchAtLoginMenuItem() {
        launchAtLoginMenuItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func presentLaunchAtLoginError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Launch at Login could not be updated."
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    private static let windowManagementShortcutTitles = [
        "⌃⇧⌘H  Left width cycle",
        "⌃⇧⌘J  Bottom height cycle",
        "⌃⇧⌘K  Top height cycle",
        "⌃⇧⌘L  Right width cycle",
        "⌃⇧⌘I  Center third",
        "⌃⇧⌘↩  Maximize",
        "⌃⇧⌘Y  Next display",
        "⌃⇧⌘P  Previous display"
    ]

    private func configureLauncherCarbonHotKeys() {
        let bindings: [(UInt32, UInt32, LauncherHotKey)] = [
            (UInt32(kVK_Space), UInt32(cmdKey), .defaultSearch),
            (UInt32(kVK_ANSI_V), UInt32(cmdKey | shiftKey), .clipboardHistory)
        ]

        launcherHotKeyMonitors = bindings.compactMap { keyCode, modifiers, hotKey in
            do {
                return try HotKeyMonitor(keyCode: keyCode, modifiers: modifiers) { [weak self] in
                    Task { @MainActor in self?.handleLauncherHotKey(hotKey) }
                }
            } catch {
                fputs("Sagasu launcher hotkey registration failed for keyCode \(keyCode): \(error.localizedDescription)\n", stderr)
                return nil
            }
        }
    }

    private func configureWindowManagementHotKeys() {
        do {
            windowHotKeyMonitor = try WindowHotKeyMonitor { [weak self] command in
                Task { @MainActor in self?.performWindowManagement(command, source: "tap") }
            }
        } catch {
            fputs("Sagasu window hotkey monitor failed: \(error.localizedDescription)\n", stderr)
        }

        let modifiers = UInt32(controlKey | shiftKey | cmdKey)
        let bindings: [(UInt32, WindowManager.Command)] = [
            (UInt32(kVK_ANSI_J), .bottomHalf),
            (UInt32(kVK_ANSI_I), .centerThird),
            (UInt32(kVK_ANSI_H), .leftHalf),
            (UInt32(kVK_Return), .maximize),
            (UInt32(kVK_ANSI_Y), .nextDisplay),
            (UInt32(kVK_ANSI_P), .previousDisplay),
            (UInt32(kVK_ANSI_L), .rightHalf),
            (UInt32(kVK_ANSI_K), .topHalf)
        ]

        windowHotKeyMonitors = bindings.compactMap { keyCode, command in
            do {
                return try HotKeyMonitor(keyCode: keyCode, modifiers: modifiers) { [weak self] in
                    Task { @MainActor in self?.performWindowManagement(command, source: "carbon") }
                }
            } catch {
                fputs("Sagasu window hotkey registration failed for keyCode \(keyCode): \(error.localizedDescription)\n", stderr)
                return nil
            }
        }
    }

    private func ensureEventTapsEnabled() {
        launcherHotKeyMonitor?.ensureEnabled()
        windowHotKeyMonitor?.ensureEnabled()
    }

    private func configureDebugWindowCommandsIfNeeded() {
        guard ProcessInfo.processInfo.environment["SAGASU_WINDOW_DEBUG"] == "1" else { return }
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleDebugWindowCommand(_:)),
            name: debugWindowCommandNotification,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        WindowManager.debugLog("debug window command notification enabled name=\(debugWindowCommandNotification.rawValue)")
    }

    @objc private func handleDebugWindowCommand(_ notification: Notification) {
        guard let commandName = notification.userInfo?["command"] as? String,
              let command = WindowManager.Command.fromDebugName(commandName) else {
            WindowManager.debugLog("debug notification ignored userInfo=\(String(describing: notification.userInfo))")
            return
        }
        performWindowManagement(command, source: "debug")
    }

    private func performWindowManagement(_ command: WindowManager.Command, source: String) {
        let now = Date()
        if lastWindowCommand == command,
           lastWindowCommandSource != source,
           now.timeIntervalSince(lastWindowCommandAt) < 0.08 {
            WindowManager.debugLog("debounced duplicate source=\(source) command=\(command.debugName) sinceLastCompletionMs=\(Int((now.timeIntervalSince(lastWindowCommandAt) * 1000).rounded()))")
            return
        }

        WindowManager.debugLog("dispatch source=\(source) command=\(command.debugName) time=\(now.timeIntervalSince1970)")
        let startedAt = Date()
        do {
            try windowManager.perform(command)
            lastWindowCommand = command
            lastWindowCommandAt = Date()
            lastWindowCommandSource = source
            WindowManager.debugLog("dispatch complete source=\(source) command=\(command.debugName) elapsedMs=\(Int((Date().timeIntervalSince(startedAt) * 1000).rounded()))")
        } catch {
            WindowManager.debugLog("dispatch failed source=\(source) command=\(command.debugName) error=\(error.localizedDescription) elapsedMs=\(Int((Date().timeIntervalSince(startedAt) * 1000).rounded()))")
            presentWindowManagement(error: error)
        }
    }

    private func presentWindowManagement(error: Error) {
        if case LauncherError.accessibilityPermissionRequired = error {
            guard didPresentAccessibilityPermissionError == false else { return }
            didPresentAccessibilityPermissionError = true
            WindowManager.openAccessibilitySettings()
            NSApp.presentError(error)
            return
        }

        if case LauncherError.windowManagementFailed = error {
            return
        }

        NSApp.presentError(error)
    }

    private func perform(action: SearchAction) {
        do {
            switch action {
            case .launchApplication(let url):
                let configuration = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            case .openURL(let url):
                NSWorkspace.shared.open(url)
            case .openURLInPreferredBrowser(let url, let bundleIdentifier):
                open(url: url, preferringBrowserWithBundleIdentifier: bundleIdentifier)
            case .openNote(let noteID):
                try NotesSearchService.openNote(withID: noteID)
            case .restoreClipboard(let entryID):
                try clipboardStore.restore(entryID: entryID)
                try? searchEngine.markUsed(action: action)
                hideLauncher()
                pasteRestoredClipboardSoon()
                return
            case .saveClipboardImage:
                Task { @MainActor [weak self] in
                    self?.saveClipboardImage()
                }
                return
            case .extractTextFromClipboardImage:
                Task { @MainActor [weak self] in
                    await self?.extractTextFromClipboardImage()
                }
                return
            case .focusTerminalPane(let paneID):
                try HerdrSearchService().focusPane(withID: paneID)
            case .configureLinearAPIKey:
                presentLinearAPIKeyDialog()
                return
            case .copyText(let text):
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            try? searchEngine.markUsed(action: action)
            hideLauncher()
        } catch {
            searchViewModel.present(error: error)
        }
    }

    private func presentLinearAPIKeyDialog() {
        guard isPresentingLinearAPIKeyDialog == false else { return }
        isPresentingLinearAPIKeyDialog = true
        launcherPanelController?.suppressAutoHide = true
        defer {
            launcherPanelController?.suppressAutoHide = false
            isPresentingLinearAPIKeyDialog = false
        }

        let alert = NSAlert()
        alert.messageText = "Set Linear API Key"
        alert.informativeText = "Paste a personal Linear API key. Sagasu stores it in macOS Keychain and uses it only for `l ` Linear issue search."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let inputField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        inputField.placeholderString = "lin_api_..."
        alert.accessoryView = inputField

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        do {
            try linearCredentialStore.save(apiKey: inputField.stringValue)
            searchViewModel.refreshCurrentSearch()
            launcherPanelController?.window?.makeKeyAndOrderFront(nil)
        } catch {
            searchViewModel.present(error: error)
            launcherPanelController?.window?.makeKeyAndOrderFront(nil)
        }
    }

    private func rememberApplicationBeforeLauncher() {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return
        }
        applicationBeforeLauncher = application
    }

    private func pasteRestoredClipboardSoon() {
        let targetApplication = applicationBeforeLauncher
        Task { @MainActor in
            if let targetApplication, targetApplication.isTerminated == false {
                targetApplication.activate(options: [.activateAllWindows])
            }

            try? await Task.sleep(nanoseconds: 150_000_000)
            Self.sendPasteShortcut()
        }
    }

    static func sendPasteShortcut() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func saveClipboardImage() {
        do {
            let savedImageURL = try clipboardImageTextService.saveClipboardImage()
            try? searchEngine.markUsed(action: .saveClipboardImage)
            hideLauncher()
            NSWorkspace.shared.activateFileViewerSelecting([savedImageURL])
        } catch {
            searchViewModel.present(error: error)
        }
    }

    private func extractTextFromClipboardImage() async {
        do {
            let recognizedText = try await clipboardImageTextService.extractTextFromClipboardImage()
            try clipboardStore.addTextEntry(recognizedText, writingToPasteboard: true)
            try? searchEngine.markUsed(action: .extractTextFromClipboardImage)
            hideLauncher()
        } catch {
            searchViewModel.present(error: error)
        }
    }

    private func open(url: URL, preferringBrowserWithBundleIdentifier bundleIdentifier: String) {
        guard let browserURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            NSWorkspace.shared.open(url)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: browserURL, configuration: configuration) { [weak self] _, error in
            guard let error else { return }
            Task { @MainActor in
                self?.searchViewModel.present(error: error)
            }
        }
    }

    private func captureSnapshotAndTerminate(at url: URL) {
        do {
            try launcherPanelController?.captureSnapshot(to: url)
        } catch {
            searchViewModel.present(error: error)
        }
        isQuitRequested = true
        NSApp.terminate(nil)
    }
}
