import AppKit
import Carbon
import Foundation

enum LauncherHotKey {
    case defaultSearch
    case clipboardHistory
}

final class LauncherHotKeyMonitor {
    nonisolated(unsafe) private static var handler: ((LauncherHotKey) -> Void)?
    nonisolated(unsafe) private static var activeEventTap: CFMachPort?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(handler: @escaping (LauncherHotKey) -> Void) throws {
        Self.handler = handler

        let mask = 1 << CGEventType.keyDown.rawValue

        guard let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: Self.handleEventTap,
            userInfo: nil
        ) else {
            throw LauncherError.hotKeyRegistrationFailed(-1)
        }

        self.eventTap = eventTap
        Self.activeEventTap = eventTap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        self.runLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        Self.activeEventTap = nil
        Self.handler = nil
    }

    private static let handleEventTap: CGEventTapCallBack = { _, type, event, _ in
        if shouldReenableEventTap(for: type) {
            if let eventTap = activeEventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown,
              let hotKey = LauncherHotKeyMonitor.hotKey(for: event) else {
            return Unmanaged.passUnretained(event)
        }

        LauncherHotKeyMonitor.handler?(hotKey)
        return nil
    }

    static func shouldReenableEventTap(for type: CGEventType) -> Bool {
        type == .tapDisabledByTimeout || type == .tapDisabledByUserInput
    }

    private static func hotKey(for event: CGEvent) -> LauncherHotKey? {
        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let relevantFlags = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])

        if keyCode == UInt32(kVK_Space), relevantFlags == .maskCommand {
            return .defaultSearch
        }

        if keyCode == UInt32(kVK_ANSI_V), relevantFlags == [.maskCommand, .maskShift] {
            return .clipboardHistory
        }

        return nil
    }
}
