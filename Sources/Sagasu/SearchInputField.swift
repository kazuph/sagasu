import AppKit
import SwiftUI

struct SearchInputField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onTogglePin: () -> Void
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> LauncherSearchField {
        let textField = LauncherSearchField()
        textField.delegate = context.coordinator
        textField.placeholderString = placeholder
        textField.font = .systemFont(ofSize: 20, weight: .semibold)
        textField.focusRingType = .none
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.lineBreakMode = .byTruncatingTail
        textField.maximumNumberOfLines = 1
        textField.onSubmit = onSubmit
        textField.onMoveUp = onMoveUp
        textField.onMoveDown = onMoveDown
        textField.onTogglePin = onTogglePin
        textField.onEscape = onEscape
        return textField
    }

    func updateNSView(_ nsView: LauncherSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
        nsView.onSubmit = onSubmit
        nsView.onMoveUp = onMoveUp
        nsView.onMoveDown = onMoveDown
        nsView.onTogglePin = onTogglePin
        nsView.onEscape = onEscape

        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            if let launcherWindow = window as? LauncherWindow {
                launcherWindow.searchField = nsView
                launcherWindow.onMoveUp = onMoveUp
                launcherWindow.onMoveDown = onMoveDown
                launcherWindow.onTogglePin = onTogglePin
                if window.isKeyWindow {
                    launcherWindow.focusSearchField()
                    return
                }
            }
            if window.firstResponder !== nsView.currentEditor(),
               window.firstResponder !== nsView {
                window.makeFirstResponder(nsView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            text = textField.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard let textField = control as? LauncherSearchField else { return false }

            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                textField.onSubmit?()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                textField.onEscape?()
                return true
            default:
                return false
            }
        }
    }
}

final class LauncherSearchField: NSTextField {
    var onSubmit: (() -> Void)?
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onTogglePin: (() -> Void)?
    var onEscape: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}
