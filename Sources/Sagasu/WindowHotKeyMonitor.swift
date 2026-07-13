import AppKit
import Carbon
import Foundation

final class WindowHotKeyMonitor {
    nonisolated(unsafe) private static var handler: ((WindowManager.Command) -> Void)?
    nonisolated(unsafe) private static var activeEventTap: CFMachPort?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(handler: @escaping (WindowManager.Command) -> Void) throws {
        Self.handler = handler

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
        Self.handler = nil
    }

    static func command(keyCode: UInt32, flags: CGEventFlags) -> WindowManager.Command? {
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
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap = activeEventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            WindowManager.debugLog("eventTap re-enabled type=\(type.rawValue)")
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        guard let command = command(keyCode: keyCode, flags: event.flags) else {
            return Unmanaged.passUnretained(event)
        }

        handler?(command)
        return nil
    }
}
