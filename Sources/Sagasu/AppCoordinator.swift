import AppKit
import Carbon
import SwiftUI

@MainActor
final class AppCoordinator: NSObject, ObservableObject {
    let clipboardStore: ClipboardHistoryStore
    let searchEngine: SearchEngine
    let searchViewModel: SearchViewModel

    private var hotKeyMonitor: HotKeyMonitor?
    private var launcherPanelController: LauncherPanelController?

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
    }

    func start(configuration: LaunchConfiguration = .current) {
        do {
            hotKeyMonitor = try HotKeyMonitor(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)) { [weak self] in
                Task { @MainActor in
                    self?.toggleLauncher()
                }
            }
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
        NSApp.terminate(nil)
    }
}
