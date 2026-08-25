import AppKit
import Carbon
import Foundation

enum LauncherHotKey {
    case defaultSearch
    case clipboardHistory
}

final class GlobalHotKeyMonitor {
    nonisolated(unsafe) private static var launcherHandler: ((LauncherHotKey) -> Void)?
    nonisolated(unsafe) private static var windowHandler: ((WindowManager.Command) -> Void)?
    nonisolated(unsafe) private static var activeEventTap: CFMachPort?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(
        launcherHandler: @escaping (LauncherHotKey) -> Void,
        windowHandler: @escaping (WindowManager.Command) -> Void
    ) throws {
        Self.launcherHandler = launcherHandler
        Self.windowHandler = windowHandler

        let mask = 1 << CGEventType.keyDown.rawValue
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
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
        Self.launcherHandler = nil
        Self.windowHandler = nil
    }

    static func shouldReenableEventTap(for type: CGEventType) -> Bool {
        type == .tapDisabledByTimeout || type == .tapDisabledByUserInput
    }

    static func windowCommand(keyCode: UInt32, flags: CGEventFlags) -> WindowManager.Command? {
        let relevantFlags = flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        guard relevantFlags == [.maskCommand, .maskControl, .maskShift] else {
            return nil
        }

        switch keyCode {
        case UInt32(kVK_ANSI_J):
            return .bottomHalf
        case UInt32(kVK_ANSI_I):
            return .centerThird
        case UInt32(kVK_ANSI_H):
            return .leftHalf
        case UInt32(kVK_Return):
            return .maximize
        case UInt32(kVK_ANSI_Y):
            return .nextDisplay
        case UInt32(kVK_ANSI_P):
            return .previousDisplay
        case UInt32(kVK_ANSI_L):
            return .rightHalf
        case UInt32(kVK_ANSI_K):
            return .topHalf
        default:
            return nil
        }
    }

    private static let handleEventTap: CGEventTapCallBack = { _, type, event, _ in
        if shouldReenableEventTap(for: type) {
            if let eventTap = activeEventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        if let hotKey = launcherHotKey(keyCode: keyCode, flags: flags) {
            launcherHandler?(hotKey)
            return nil
        }
        if let command = windowCommand(keyCode: keyCode, flags: flags) {
            windowHandler?(command)
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    private static func launcherHotKey(keyCode: UInt32, flags: CGEventFlags) -> LauncherHotKey? {
        let relevantFlags = flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        if keyCode == UInt32(kVK_Space), relevantFlags == .maskCommand {
            return .defaultSearch
        }
        if keyCode == UInt32(kVK_ANSI_V), relevantFlags == [.maskCommand, .maskShift] {
            return .clipboardHistory
        }
        return nil
    }
}
