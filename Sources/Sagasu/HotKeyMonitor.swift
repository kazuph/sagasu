import Carbon
import Foundation

final class HotKeyMonitor {
    private static let signature: OSType = 0x53414753
    nonisolated(unsafe) private static var nextIdentifier: UInt32 = 1
    nonisolated(unsafe) private static var handlers: [UInt32: () -> Void] = [:]
    nonisolated(unsafe) private static var eventHandler: EventHandlerRef?

    private let identifier: UInt32
    private var hotKeyReference: EventHotKeyRef?

    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) throws {
        identifier = Self.nextIdentifier
        Self.nextIdentifier += 1
        Self.handlers[identifier] = handler
        try Self.installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: identifier)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyReference
        )

        guard status == noErr else {
            Self.handlers[identifier] = nil
            throw LauncherError.hotKeyRegistrationFailed(status)
        }
    }

    deinit {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
        }
        Self.handlers[identifier] = nil
    }

    private static func installHandlerIfNeeded() throws {
        guard eventHandler == nil else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, _ in
                var hotKeyID = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard parameterStatus == noErr else {
                    return parameterStatus
                }

                HotKeyMonitor.handlers[hotKeyID.id]?()
                return noErr
            },
            1,
            &eventSpec,
            nil,
            &eventHandler
        )

        guard status == noErr else {
            throw LauncherError.hotKeyRegistrationFailed(status)
        }
    }
}
