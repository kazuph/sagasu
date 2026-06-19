import AppKit
import Foundation
import SwiftUI

final class LauncherWindow: NSWindow {
    var onCancel: (() -> Void)?
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onTogglePin: (() -> Void)?
    var onDeleteClipboardEntry: (() -> Void)?
    weak var searchField: NSView?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func focusSearchField(selectingASCIIInputSource: Bool = false) {
        guard let searchField else { return }
        if selectingASCIIInputSource {
            KeyboardInputSourceController.selectASCIIInputSource()
        }
        makeFirstResponder(searchField)

        if let textField = searchField as? NSTextField {
            textField.currentEditor()?.selectedRange = NSRange(location: textField.stringValue.count, length: 0)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            switch event.keyCode {
            case 126:
                onMoveUp?()
                return
            case 125:
                onMoveDown?()
                return
            case 53:
                onCancel?()
                return
            default:
                let relevantModifiers = event.modifierFlags.intersection([.control, .option, .command, .shift])
                if relevantModifiers == [.control],
                   let characters = event.charactersIgnoringModifiers?.lowercased() {
                    switch characters {
                    case "p":
                        onMoveUp?()
                        return
                    case "n":
                        onMoveDown?()
                        return
                    default:
                        break
                    }
                }

                if relevantModifiers == [.command],
                   let characters = event.charactersIgnoringModifiers?.lowercased() {
                    switch characters {
                    case "p":
                        onTogglePin?()
                        return
                    case "d":
                        onDeleteClipboardEntry?()
                        return
                    default:
                        break
                    }
                }
            }
        }

        super.sendEvent(event)
    }
}

@MainActor
final class LauncherPanelController: NSWindowController, NSWindowDelegate {
    private enum Layout {
        static let panelSize = NSSize(width: 680, height: 392)
        static let topMargin: CGFloat = 82
    }

    private var isBecomeKeyPending = false
    private var lastShownAt: Date?
    var onDismiss: (() -> Void)?

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    init(rootView: SearchRootView) {
        let panel = LauncherWindow(
            contentRect: NSRect(origin: .zero, size: Layout.panelSize),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace, .transient]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .none
        panel.standardWindowButton(.closeButton)?.isHidden = false
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.delegate = nil
        panel.contentView = NSHostingView(rootView: rootView)

        super.init(window: panel)
        panel.onCancel = { [weak self] in
            self?.hide()
        }
        panel.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        isBecomeKeyPending = true
        lastShownAt = Date()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let presentation = frameForPresentation()
        window.setContentSize(presentation.size)
        window.setFrameTopLeftPoint(
            NSPoint(
                x: presentation.minX,
                y: presentation.maxY
            )
        )
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
        window.orderFrontRegardless()

        DispatchQueue.main.async { [weak window] in
            (window as? LauncherWindow)?.focusSearchField(selectingASCIIInputSource: true)
        }
    }

    func hide() {
        guard let window, window.isVisible else {
            isBecomeKeyPending = false
            lastShownAt = nil
            NSApp.setActivationPolicy(.accessory)
            onDismiss?()
            return
        }

        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        window.orderOut(nil)
        NSAnimationContext.endGrouping()
        isBecomeKeyPending = false
        lastShownAt = nil
        NSApp.setActivationPolicy(.accessory)
        onDismiss?()
    }

    func captureSnapshot(to url: URL) throws {
        guard let contentView = window?.contentView else {
            throw LauncherError.snapshotFailed("Launcher content view is unavailable.")
        }

        let bounds = contentView.bounds
        guard let bitmap = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw LauncherError.snapshotFailed("Bitmap snapshot could not be created.")
        }

        contentView.cacheDisplay(in: bounds, to: bitmap)

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw LauncherError.snapshotFailed("Snapshot PNG encoding failed.")
        }

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        isBecomeKeyPending = false
        (window as? LauncherWindow)?.focusSearchField(selectingASCIIInputSource: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    func windowDidResignKey(_ notification: Notification) {
        guard isBecomeKeyPending == false else { return }
        if let lastShownAt, Date().timeIntervalSince(lastShownAt) < 0.25 {
            return
        }
        hide()
    }

    func windowDidResignMain(_ notification: Notification) {
        guard isBecomeKeyPending == false else { return }
        if let lastShownAt, Date().timeIntervalSince(lastShownAt) < 0.25 {
            return
        }
        hide()
    }

    private func frameForPresentation() -> NSRect {
        let screen = activeScreen() ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSRect(origin: .zero, size: Layout.panelSize)
        let origin = NSPoint(
            x: visibleFrame.midX - (Layout.panelSize.width / 2),
            y: max(visibleFrame.minY, visibleFrame.maxY - Layout.panelSize.height - Layout.topMargin)
        )
        return NSRect(origin: origin, size: Layout.panelSize)
    }

    private func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: {
            $0.frame.contains(mouseLocation) || $0.visibleFrame.contains(mouseLocation)
        }) {
            return screen
        }

        if let windowScreen = window?.screen {
            return windowScreen
        }

        return NSScreen.main
    }
}
