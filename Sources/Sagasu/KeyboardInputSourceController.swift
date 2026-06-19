import AppKit
import Carbon
import Foundation

enum KeyboardInputSourceController {
    private static let preferredInputSourceIDs = [
        "com.apple.keylayout.ABC",
        "com.apple.keylayout.US"
    ]

    static func selectASCIIInputSource() {
        pressJapaneseKeyboardEisuKey()
    }

    private static func pressJapaneseKeyboardEisuKey() {
        let keyCode = CGKeyCode(kVK_JIS_Eisu)
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    static func selectASCIIInputSourceDirectly() {
        for inputSourceID in preferredInputSourceIDs where selectInputSource(withID: inputSourceID) {
            return
        }

        selectFirstASCIICapableInputSource()
    }

    @discardableResult
    private static func selectInputSource(withID inputSourceID: String) -> Bool {
        let filter = [kTISPropertyInputSourceID as String: inputSourceID] as CFDictionary
        guard let inputSource = inputSources(matching: filter).first else { return false }
        return TISSelectInputSource(inputSource) == noErr
    }

    private static func selectFirstASCIICapableInputSource() {
        let filter = [kTISPropertyInputSourceIsASCIICapable as String: true] as CFDictionary
        guard let inputSource = inputSources(matching: filter).first else { return }
        TISSelectInputSource(inputSource)
    }

    private static func inputSources(matching filter: CFDictionary) -> [TISInputSource] {
        guard let unmanagedSources = TISCreateInputSourceList(filter, false) else { return [] }
        let sources = unmanagedSources.takeRetainedValue() as NSArray
        return sources.map { $0 as! TISInputSource }
    }
}
