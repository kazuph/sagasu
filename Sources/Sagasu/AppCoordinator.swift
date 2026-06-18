import AppKit
import Carbon
import SwiftUI

@MainActor
final class AppCoordinator: NSObject, ObservableObject {
    let clipboardStore: ClipboardHistoryStore
    let searchEngine: SearchEngine
    let searchViewModel: SearchViewModel

    private var hotKeyMonitor: HotKeyMonitor?
    private var windowHotKeyMonitors: [HotKeyMonitor] = []
    private let windowManager = WindowManager()
    private var launcherPanelController: LauncherPanelController?
    private var statusItem: NSStatusItem?
    private var didPresentAccessibilityPermissionError = false
    private(set) var isQuitRequested = false

    override init() {
        let clipboardStore = ClipboardHistoryStore()
        let searchEngine = SearchEngine(clipboardStore: clipboardStore)
        self.clipboardStore = clipboardStore
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
    }

    func start(configuration: LaunchConfiguration = .current) {
        NSApp.applicationIconImage = SagasuIcon.appIcon()
        _ = WindowManager.requestAccessibilityPermissionIfNeeded()
        configureStatusItem()

        do {
            hotKeyMonitor = try HotKeyMonitor(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)) { [weak self] in
                Task { @MainActor in
                    self?.toggleLauncher()
                }
            }
            configureWindowManagementHotKeys()
        } catch {
            NSApp.presentError(error)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let rootView = SearchRootView(viewModel: self.searchViewModel) { [weak self] in
                self?.hideLauncher()
            }
            let panelController = LauncherPanelController(rootView: rootView)
            panelController.onDismiss = { [weak self] in
                self?.searchViewModel.dismiss()
            }
            self.launcherPanelController = panelController

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
        guard let launcherPanelController else { return }

        if launcherPanelController.isVisible {
            hideLauncher()
        } else {
            searchViewModel.prepareForPresentation()
            launcherPanelController.show()
        }
    }

    func hideLauncher() {
        launcherPanelController?.hide()
    }

    @objc private func showLauncherFromStatusItem(_ sender: Any?) {
        searchViewModel.prepareForPresentation()
        launcherPanelController?.show()
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
        let titleItem = NSMenuItem(title: "🔭 Sagasu", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open Sagasu", action: #selector(showLauncherFromStatusItem(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Sagasu", action: #selector(quitFromStatusItem(_:)), keyEquivalent: "q"))
        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
        self.statusItem = statusItem
    }

    private func configureWindowManagementHotKeys() {
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
                    Task { @MainActor in
                        do {
                            try self?.windowManager.perform(command)
                        } catch {
                            self?.presentWindowManagement(error: error)
                        }
                    }
                }
            } catch {
                fputs("Sagasu window hotkey registration failed for keyCode \(keyCode): \(error.localizedDescription)\n", stderr)
                return nil
            }
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
            }
            try? searchEngine.markUsed(action: action)
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
