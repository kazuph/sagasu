import AppKit
import Carbon
import Foundation

enum KeyboardInputSourceController {
    static func selectASCIIInputSource() {
        let keyCode = CGKeyCode(kVK_JIS_Eisu)
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
