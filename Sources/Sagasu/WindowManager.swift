import AppKit
import ApplicationServices
import Darwin
import Foundation

@MainActor
struct WindowManager {
    private enum CycleEdge: Hashable {
        case left
        case right
        case top
        case bottom
    }

    enum FrameAnchor {
        case left
        case right
        case top
        case bottom
    }

    private struct CycleKey: Hashable {
        let processIdentifier: pid_t
        let edge: CycleEdge
    }

    private struct CycleState {
        let fraction: CGFloat
        let updatedAt: Date
    }

    struct EnhancedUserInterfaceGuardPlan: Equatable {
        let shouldDisableBeforeOperation: Bool
    }

    enum ChromeReadbackResult: Equatable {
        case matched(CGRect)
        case clamped(CGRect)
        case mismatch(CGRect?)

        var isSettled: Bool {
            switch self {
            case .matched, .clamped:
                return true
            case .mismatch:
                return false
            }
        }

        var debugName: String {
            switch self {
            case .matched:
                return "matched"
            case .clamped:
                return "clamped"
            case .mismatch:
                return "mismatch"
            }
        }
    }

    private static let cycle: [CGFloat] = [
        1.0 / 2.0,
        1.0 / 3.0,
        1.0 / 4.0,
        2.0 / 3.0,
        3.0 / 4.0
    ]
    private static let cycleTolerance: CGFloat = 0.035
    private static let cycleStateLifetime: TimeInterval = 8
    private static let secondaryDisplayWindowTopInset: CGFloat = 31
    private static let enhancedUserInterfaceAttribute = "AXEnhancedUserInterface"
    private static let chromeSettleRetryCount = 3
    private static let chromeSettleRetryDelayMicroseconds: useconds_t = 60_000
    private static var cycleStates: [CycleKey: CycleState] = [:]

    enum Command: Equatable {
        case bottomHalf
        case centerThird
        case leftHalf
        case maximize
        case nextDisplay
        case previousDisplay
        case rightHalf
        case topHalf

        var debugName: String {
            switch self {
            case .bottomHalf:
                return "bottomHalf"
            case .centerThird:
                return "centerThird"
            case .leftHalf:
                return "leftHalf"
            case .maximize:
                return "maximize"
            case .nextDisplay:
                return "nextDisplay"
            case .previousDisplay:
                return "previousDisplay"
            case .rightHalf:
                return "rightHalf"
            case .topHalf:
                return "topHalf"
            }
        }

        static func fromDebugName(_ name: String) -> Command? {
            switch name {
            case "bottomHalf":
                return .bottomHalf
            case "centerThird":
                return .centerThird
            case "leftHalf":
                return .leftHalf
            case "maximize":
                return .maximize
            case "nextDisplay":
                return .nextDisplay
            case "previousDisplay":
                return .previousDisplay
            case "rightHalf":
                return .rightHalf
            case "topHalf":
                return .topHalf
            default:
                return nil
            }
        }
    }

    func perform(_ command: Command) throws {
        let startedAt = Date()
        guard Self.requestAccessibilityPermissionIfNeeded() else {
            throw LauncherError.accessibilityPermissionRequired
        }

        guard let application = NSWorkspace.shared.frontmostApplication,
              let window = focusedWindow(for: application),
              let currentFrame = frame(of: window) else {
            Self.debugLog("perform command=\(command.debugName) skipped=no-focused-window elapsedMs=\(Self.elapsedMilliseconds(since: startedAt))")
            return
        }
        Self.debugLog("targetApp bundleId=\(application.bundleIdentifier ?? "unknown") pid=\(application.processIdentifier) before=\(currentFrame)")

        let primaryScreenFrame = NSScreen.screens.first?.frame ?? .zero
        let screens = NSScreen.screens
            .sorted { lhs, rhs in
                if lhs.frame.minX == rhs.frame.minX {
                    return lhs.frame.minY < rhs.frame.minY
                }
                return lhs.frame.minX < rhs.frame.minX
            }
        let visibleFrames = screens.map { screen in
            windowUsableFrame(for: screen, primaryScreenFrame: primaryScreenFrame)
        }
        guard let currentScreenIndex = Self.bestScreenIndex(for: currentFrame, in: visibleFrames) else {
            Self.debugLog("perform command=\(command.debugName) skipped=no-screen before=\(currentFrame) elapsedMs=\(Self.elapsedMilliseconds(since: startedAt))")
            return
        }

        let visibleFrame = visibleFrames[currentScreenIndex]
        let targetFrame: CGRect
        let targetAnchor: FrameAnchor?
        let cycleKey: CycleKey?
        let cycleFraction: CGFloat?

        switch command {
        case .bottomHalf:
            let key = CycleKey(processIdentifier: application.processIdentifier, edge: .bottom)
            let fraction = Self.nextCycleFraction(
                current: currentFrame.height / visibleFrame.height,
                key: key,
                isStillOnSameEdge: Self.isFrame(currentFrame, alignedTo: .bottom, in: visibleFrame)
            )
            targetFrame = CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.maxY - visibleFrame.height * fraction,
                width: visibleFrame.width,
                height: visibleFrame.height * fraction
            )
            targetAnchor = .bottom
            cycleKey = key
            cycleFraction = fraction
        case .centerThird:
            targetFrame = CGRect(
                x: visibleFrame.minX + visibleFrame.width / 3,
                y: visibleFrame.minY,
                width: visibleFrame.width / 3,
                height: visibleFrame.height
            )
            targetAnchor = nil
            cycleKey = nil
            cycleFraction = nil
        case .leftHalf:
            let key = CycleKey(processIdentifier: application.processIdentifier, edge: .left)
            let fraction = Self.nextCycleFraction(
                current: currentFrame.width / visibleFrame.width,
                key: key,
                isStillOnSameEdge: Self.isFrame(currentFrame, alignedTo: .left, in: visibleFrame)
            )
            targetFrame = CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: visibleFrame.width * fraction,
                height: visibleFrame.height
            )
            targetAnchor = .left
            cycleKey = key
            cycleFraction = fraction
        case .maximize:
            targetFrame = visibleFrame
            targetAnchor = nil
            cycleKey = nil
            cycleFraction = nil
        case .nextDisplay:
            let targetIndex = (currentScreenIndex + 1) % screens.count
            Self.debugLog("selectedScreen currentIndex=\(currentScreenIndex) targetIndex=\(targetIndex)")
            targetFrame = Self.translatedFrame(currentFrame, from: visibleFrame, to: visibleFrames[targetIndex])
            targetAnchor = nil
            cycleKey = nil
            cycleFraction = nil
        case .previousDisplay:
            let targetIndex = (currentScreenIndex - 1 + screens.count) % screens.count
            Self.debugLog("selectedScreen currentIndex=\(currentScreenIndex) targetIndex=\(targetIndex)")
            targetFrame = Self.translatedFrame(currentFrame, from: visibleFrame, to: visibleFrames[targetIndex])
            targetAnchor = nil
            cycleKey = nil
            cycleFraction = nil
        case .rightHalf:
            let key = CycleKey(processIdentifier: application.processIdentifier, edge: .right)
            let fraction = Self.nextCycleFraction(
                current: currentFrame.width / visibleFrame.width,
                key: key,
                isStillOnSameEdge: Self.isFrame(currentFrame, alignedTo: .right, in: visibleFrame)
            )
            let width = visibleFrame.width * fraction
            targetFrame = CGRect(
                x: visibleFrame.maxX - width,
                y: visibleFrame.minY,
                width: width,
                height: visibleFrame.height
            )
            targetAnchor = .right
            cycleKey = key
            cycleFraction = fraction
        case .topHalf:
            let key = CycleKey(processIdentifier: application.processIdentifier, edge: .top)
            let fraction = Self.nextCycleFraction(
                current: currentFrame.height / visibleFrame.height,
                key: key,
                isStillOnSameEdge: Self.isFrame(currentFrame, alignedTo: .top, in: visibleFrame)
            )
            targetFrame = CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: visibleFrame.width,
                height: visibleFrame.height * fraction
            )
            targetAnchor = .top
            cycleKey = key
            cycleFraction = fraction
        }

        let integralTargetFrame = Self.pixelAlignedFrame(targetFrame)
        Self.debugLog("target command=\(command.debugName) screenIndex=\(currentScreenIndex) frame=\(integralTargetFrame)")
        try set(frame: integralTargetFrame, anchor: targetAnchor, for: window, application: application)
        if let cycleKey, let cycleFraction {
            Self.recordCycle(fraction: cycleFraction, for: cycleKey)
        }
        Self.debugLog("final command=\(command.debugName) frame=\(String(describing: self.frame(of: window))) elapsedMs=\(Self.elapsedMilliseconds(since: startedAt))")
    }

    static func requestAccessibilityPermissionIfNeeded(prompt: Bool = true) -> Bool {
        guard AXIsProcessTrusted() == false else { return true }
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func nextCycleFraction(current: CGFloat) -> CGFloat {
        guard let currentIndex = cycle.firstIndex(where: { abs($0 - current) <= cycleTolerance }) else {
            return cycle[0]
        }

        return cycle[(currentIndex + 1) % cycle.count]
    }

    static func nextCycleFraction(current: CGFloat, previous: CGFloat?, isStillOnSameEdge: Bool) -> CGFloat {
        if current >= 1.0 - cycleTolerance {
            return nextCycleFraction(current: current)
        }

        if isStillOnSameEdge,
           let previous,
           let previousIndex = cycle.firstIndex(where: { abs($0 - previous) <= cycleTolerance }) {
            return cycle[(previousIndex + 1) % cycle.count]
        }

        return nextCycleFraction(current: current)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    static func pixelAlignedFrame(_ frame: CGRect) -> CGRect {
        let minX = frame.minX.rounded()
        let minY = frame.minY.rounded()
        let maxX = frame.maxX.rounded()
        let maxY = frame.maxY.rounded()
        return CGRect(
            x: minX,
            y: minY,
            width: max(1, maxX - minX),
            height: max(1, maxY - minY)
        )
    }

    private func focusedWindow(for application: NSRunningApplication) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        if application.bundleIdentifier == "com.google.Chrome",
           let main = copyWindowAttribute(kAXMainWindowAttribute, from: appElement) {
            return main
        }
        if let focused = copyWindowAttribute(kAXFocusedWindowAttribute, from: appElement) {
            return focused
        }
        return copyWindowAttribute(kAXMainWindowAttribute, from: appElement)
    }

    private func frame(of window: AXUIElement) -> CGRect? {
        guard let positionValue = copyValueAttribute(kAXPositionAttribute, from: window),
              let sizeValue = copyValueAttribute(kAXSizeAttribute, from: window) else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func set(frame: CGRect, for window: AXUIElement) throws {
        try setSize(frame.size, for: window)
        _ = self.frame(of: window)
        try setPosition(frame.origin, for: window)
        _ = self.frame(of: window)
        try setSize(frame.size, for: window)
        _ = self.frame(of: window)
        try setPosition(frame.origin, for: window)
        _ = self.frame(of: window)
    }

    private func set(frame: CGRect, anchor: FrameAnchor?, for window: AXUIElement) throws {
        guard let anchor else {
            try set(frame: frame, for: window)
            return
        }

        let currentFrame = self.frame(of: window)
        switch anchor {
        case .right where (currentFrame?.width ?? frame.width) < frame.width:
            try setPosition(CGPoint(x: frame.maxX - (currentFrame?.width ?? frame.width), y: frame.minY), for: window)
            _ = self.frame(of: window)
            try set(frame: frame, for: window)
        case .bottom where (currentFrame?.height ?? frame.height) < frame.height:
            try setPosition(CGPoint(x: frame.minX, y: frame.maxY - (currentFrame?.height ?? frame.height)), for: window)
            _ = self.frame(of: window)
            try set(frame: frame, for: window)
        default:
            try set(frame: frame, for: window)
        }

        try alignActualFrame(to: frame, anchor: anchor, for: window)
    }

    private func set(
        frame: CGRect,
        anchor: FrameAnchor?,
        for window: AXUIElement,
        application: NSRunningApplication
    ) throws {
        focus(window, for: application)
        if application.bundleIdentifier == "com.google.Chrome" {
            Self.debugLog("chrome before=\(String(describing: self.frame(of: window))) target=\(frame)")
            if let currentFrame = self.frame(of: window),
               Self.framesMatch(currentFrame, frame, tolerance: 6) {
                Self.debugLog("chrome ax already matched before=\(currentFrame)")
                return
            }
            try setChromeFrame(frame, anchor: anchor, for: window, application: application)
            return
        }

        try set(frame: frame, anchor: anchor, for: window)
    }

    private func focus(_ window: AXUIElement, for application: NSRunningApplication) {
        application.activate(options: [])
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, window)
    }

    private func setChromeFrame(
        _ frame: CGRect,
        anchor: FrameAnchor?,
        for window: AXUIElement,
        application: NSRunningApplication
    ) throws {
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        let enhancedUI = Self.copyBooleanAttribute(Self.enhancedUserInterfaceAttribute, from: appElement)
        let guardPlan = Self.enhancedUserInterfaceGuardPlan(originalValue: enhancedUI.value)
        var shouldRestoreEnhancedUI = false
        Self.debugLog("chrome enhancedUI read status=\(enhancedUI.status.rawValue) value=\(String(describing: enhancedUI.value))")

        if guardPlan.shouldDisableBeforeOperation {
            let status = Self.setBooleanAttribute(Self.enhancedUserInterfaceAttribute, value: false, on: appElement)
            Self.debugLog("chrome enhancedUI disable status=\(status.rawValue)")
            shouldRestoreEnhancedUI = Self.shouldRestoreEnhancedUserInterface(
                originalValue: enhancedUI.value,
                disableSucceeded: status == .success
            )
        }
        defer {
            if shouldRestoreEnhancedUI {
                let status = Self.setBooleanAttribute(Self.enhancedUserInterfaceAttribute, value: true, on: appElement)
                Self.debugLog("chrome enhancedUI restore status=\(status.rawValue)")
            }
        }

        try setSize(frame.size, for: window)
        try setPosition(frame.origin, for: window)
        try setSize(frame.size, for: window)

        switch try settleChromeReadback(targetFrame: frame, anchor: anchor, for: window) {
        case .matched(let actualFrame):
            Self.debugLog("chrome final readback matched target=\(frame) actual=\(actualFrame)")
        case .clamped(let actualFrame):
            Self.debugLog("chrome final readback clamped target=\(frame) actual=\(actualFrame)")
        case .mismatch(let actualFrame):
            Self.debugLog("chrome final readback mismatch target=\(frame) actual=\(String(describing: actualFrame))")
            throw LauncherError.windowManagementFailed("Chrome did not reach the requested position and size.")
        }
    }

    private func settleChromeReadback(
        targetFrame: CGRect,
        anchor: FrameAnchor?,
        for window: AXUIElement
    ) throws -> ChromeReadbackResult {
        var actualFrame = self.frame(of: window)
        var result = Self.chromeReadbackResult(
            targetFrame: targetFrame,
            actualFrame: actualFrame,
            anchor: anchor
        )
        if result.isSettled { return result }

        if let measuredFrame = actualFrame, let anchor {
            let correctedOrigin = Self.correctionOrigin(
                targetFrame: targetFrame,
                measuredSize: measuredFrame.size,
                anchor: anchor
            )
            Self.debugLog("chrome anchor correction origin=\(correctedOrigin) measured=\(measuredFrame)")
            try setPosition(correctedOrigin, for: window)
            actualFrame = self.frame(of: window)
            result = Self.chromeReadbackResult(
                targetFrame: targetFrame,
                actualFrame: actualFrame,
                anchor: anchor
            )
            if result.isSettled { return result }
        }

        for attempt in 1...Self.chromeSettleRetryCount {
            usleep(Self.chromeSettleRetryDelayMicroseconds)
            try setSize(targetFrame.size, for: window)
            let measuredFrame = self.frame(of: window)
            let origin = Self.correctionOrigin(
                targetFrame: targetFrame,
                measuredSize: measuredFrame?.size ?? targetFrame.size,
                anchor: anchor
            )
            try setPosition(origin, for: window)
            actualFrame = self.frame(of: window)
            result = Self.chromeReadbackResult(
                targetFrame: targetFrame,
                actualFrame: actualFrame,
                anchor: anchor
            )
            Self.debugLog("chrome settle attempt=\(attempt) readback=\(String(describing: actualFrame)) result=\(result.debugName)")
            if result.isSettled { return result }
        }

        return result
    }

    static func enhancedUserInterfaceGuardPlan(originalValue: Bool?) -> EnhancedUserInterfaceGuardPlan {
        EnhancedUserInterfaceGuardPlan(shouldDisableBeforeOperation: originalValue == true)
    }

    static func shouldRestoreEnhancedUserInterface(originalValue: Bool?, disableSucceeded: Bool) -> Bool {
        originalValue == true && disableSucceeded
    }

    static func chromeReadbackResult(
        targetFrame: CGRect,
        actualFrame: CGRect?,
        anchor: FrameAnchor? = nil
    ) -> ChromeReadbackResult {
        guard let actualFrame else { return .mismatch(nil) }
        if framesMatch(actualFrame, targetFrame, tolerance: 6) {
            return .matched(actualFrame)
        }
        if isAnchoredClamp(actualFrame, targetFrame: targetFrame, anchor: anchor, tolerance: 6) {
            return .clamped(actualFrame)
        }
        return .mismatch(actualFrame)
    }

    static func correctionOrigin(
        targetFrame: CGRect,
        measuredSize: CGSize,
        anchor: FrameAnchor?
    ) -> CGPoint {
        switch anchor {
        case .right:
            return CGPoint(x: targetFrame.maxX - measuredSize.width, y: targetFrame.minY)
        case .bottom:
            return CGPoint(x: targetFrame.minX, y: targetFrame.maxY - measuredSize.height)
        case .left, .top, nil:
            return targetFrame.origin
        }
    }

    private static func isAnchoredClamp(
        _ actualFrame: CGRect,
        targetFrame: CGRect,
        anchor: FrameAnchor?,
        tolerance: CGFloat
    ) -> Bool {
        guard let anchor else { return false }

        switch anchor {
        case .left:
            return abs(actualFrame.minX - targetFrame.minX) <= tolerance
                && abs(actualFrame.minY - targetFrame.minY) <= tolerance
                && abs(actualFrame.height - targetFrame.height) <= tolerance
                && actualFrame.width >= targetFrame.width - tolerance
        case .right:
            return abs(actualFrame.maxX - targetFrame.maxX) <= tolerance
                && abs(actualFrame.minY - targetFrame.minY) <= tolerance
                && abs(actualFrame.height - targetFrame.height) <= tolerance
                && actualFrame.width >= targetFrame.width - tolerance
        case .top:
            return abs(actualFrame.minX - targetFrame.minX) <= tolerance
                && abs(actualFrame.minY - targetFrame.minY) <= tolerance
                && abs(actualFrame.width - targetFrame.width) <= tolerance
                && actualFrame.height >= targetFrame.height - tolerance
        case .bottom:
            return abs(actualFrame.minX - targetFrame.minX) <= tolerance
                && abs(actualFrame.maxY - targetFrame.maxY) <= tolerance
                && abs(actualFrame.width - targetFrame.width) <= tolerance
                && actualFrame.height >= targetFrame.height - tolerance
        }
    }

    private static func copyBooleanAttribute(_ attribute: String, from element: AXUIElement) -> (value: Bool?, status: AXError) {
        var rawValue: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &rawValue)
        guard status == .success,
              let rawValue,
              CFGetTypeID(rawValue) == CFBooleanGetTypeID() else {
            return (nil, status)
        }
        return (CFBooleanGetValue((rawValue as! CFBoolean)), status)
    }

    private static func setBooleanAttribute(_ attribute: String, value: Bool, on element: AXUIElement) -> AXError {
        let rawValue = value ? kCFBooleanTrue! : kCFBooleanFalse!
        return AXUIElementSetAttributeValue(element, attribute as CFString, rawValue)
    }

    private static func framesMatch(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance &&
            abs(lhs.minY - rhs.minY) <= tolerance &&
            abs(lhs.width - rhs.width) <= tolerance &&
            abs(lhs.height - rhs.height) <= tolerance
    }

    nonisolated static func debugLog(_ message: @autoclosure () -> String) {
        guard ProcessInfo.processInfo.environment["SAGASU_WINDOW_DEBUG"] == "1" else { return }
        let line = "[WindowManager] \(Self.debugTimestampMilliseconds()) \(message())\n"
        fputs(line, stderr)
        guard let data = line.data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: "/tmp/sagasu-window-debug.log")
        if FileManager.default.fileExists(atPath: url.path) == false {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    private nonisolated static func debugTimestampMilliseconds() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000).rounded())
    }

    private nonisolated static func elapsedMilliseconds(since date: Date) -> Int64 {
        Int64((Date().timeIntervalSince(date) * 1000).rounded())
    }

    private func setPosition(_ position: CGPoint, for window: AXUIElement) throws {
        var position = position
        guard let value = AXValueCreate(.cgPoint, &position) else { return }
        let status = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        Self.debugLog("ax setPosition value=\(position) status=\(status.rawValue)")
        if status != .success {
            throw LauncherError.accessibilityPermissionRequired
        }
    }

    private func setSize(_ size: CGSize, for window: AXUIElement) throws {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return }
        let status = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        Self.debugLog("ax setSize value=\(size) status=\(status.rawValue)")
        if status != .success {
            throw LauncherError.accessibilityPermissionRequired
        }
    }

    private func alignActualFrame(to targetFrame: CGRect, anchor: FrameAnchor, for window: AXUIElement) throws {
        guard var actualFrame = frame(of: window) else { return }

        let widthDelta = actualFrame.width - targetFrame.width
        if abs(widthDelta) > 200 {
            actualFrame.size.width = targetFrame.width
        }

        let heightDelta = actualFrame.height - targetFrame.height
        if abs(heightDelta) > 240 {
            actualFrame.size.height = targetFrame.height
        }

        switch anchor {
        case .left:
            actualFrame.origin.x = targetFrame.minX
        case .right:
            actualFrame.origin.x = targetFrame.maxX - actualFrame.width
        case .top:
            actualFrame.origin.y = targetFrame.minY
        case .bottom:
            actualFrame.origin.y = targetFrame.maxY - actualFrame.height
        }

        let integralFrame = Self.pixelAlignedFrame(actualFrame)
        switch anchor {
        case .right, .bottom:
            try setPosition(integralFrame.origin, for: window)
            _ = self.frame(of: window)
            try setSize(integralFrame.size, for: window)
            _ = self.frame(of: window)
        case .left, .top:
            try set(frame: integralFrame, for: window)
        }
    }

    private func copyAttribute(_ attribute: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard status == .success else { return nil }
        return value
    }

    private func copyWindowAttribute(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        guard let value = copyAttribute(attribute, from: element),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func copyValueAttribute(_ attribute: String, from element: AXUIElement) -> AXValue? {
        guard let value = copyAttribute(attribute, from: element),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        return (value as! AXValue)
    }

    static func axFrame(from appKitFrame: CGRect, primaryScreenFrame: CGRect) -> CGRect {
        return CGRect(
            x: appKitFrame.minX,
            y: primaryScreenFrame.maxY - appKitFrame.maxY,
            width: appKitFrame.width,
            height: appKitFrame.height
        )
    }

    static func axVisibleFrame(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        primaryScreenFrame: CGRect
    ) -> CGRect {
        axFrame(from: visibleFrame, primaryScreenFrame: primaryScreenFrame)
    }

    static func bestScreenIndex(for frame: CGRect, in visibleFrames: [CGRect]) -> Int? {
        let intersections = visibleFrames.enumerated().map { index, visibleFrame in
            (index: index, area: frame.intersection(visibleFrame).area)
        }
        if let best = intersections.max(by: { $0.area < $1.area }), best.area > 0 {
            return best.index
        }

        let center = CGPoint(x: frame.midX, y: frame.midY)
        return visibleFrames.firstIndex { $0.contains(center) }
    }

    private func axVisibleFrame(for screen: NSScreen, primaryScreenFrame: CGRect) -> CGRect {
        Self.axVisibleFrame(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            primaryScreenFrame: primaryScreenFrame
        )
    }

    private func windowUsableFrame(for screen: NSScreen, primaryScreenFrame: CGRect) -> CGRect {
        Self.windowUsableFrame(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            primaryScreenFrame: primaryScreenFrame
        )
    }

    static func windowUsableFrame(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        primaryScreenFrame: CGRect
    ) -> CGRect {
        var frame = axVisibleFrame(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            primaryScreenFrame: primaryScreenFrame
        )
        if visibleFrame == screenFrame {
            frame.origin.y += secondaryDisplayWindowTopInset
            frame.size.height = max(120, frame.height - secondaryDisplayWindowTopInset)
        }
        return frame
    }

    static func translatedFrame(_ frame: CGRect, from source: CGRect, to destination: CGRect) -> CGRect {
        let widthRatio = frame.width / max(source.width, 1)
        let heightRatio = frame.height / max(source.height, 1)
        let xRatio = (frame.minX - source.minX) / max(source.width, 1)
        let yRatio = (frame.minY - source.minY) / max(source.height, 1)

        let width = min(destination.width, max(120, destination.width * widthRatio))
        let height = min(destination.height, max(120, destination.height * heightRatio))
        let x = destination.minX + destination.width * xRatio
        let y = destination.minY + destination.height * yRatio

        return CGRect(
            x: min(max(x, destination.minX), destination.maxX - width),
            y: min(max(y, destination.minY), destination.maxY - height),
            width: width,
            height: height
        )
    }

    private static func nextCycleFraction(current: CGFloat, key: CycleKey, isStillOnSameEdge: Bool) -> CGFloat {
        cleanupCycleStates()
        return nextCycleFraction(
            current: current,
            previous: cycleStates[key]?.fraction,
            isStillOnSameEdge: isStillOnSameEdge
        )
    }

    private static func recordCycle(fraction: CGFloat, for key: CycleKey) {
        cycleStates[key] = CycleState(fraction: fraction, updatedAt: Date())
    }

    private static func cleanupCycleStates(now: Date = Date()) {
        cycleStates = cycleStates.filter { _, state in
            now.timeIntervalSince(state.updatedAt) <= cycleStateLifetime
        }
    }

    private static func isFrame(_ frame: CGRect, alignedTo edge: CycleEdge, in visibleFrame: CGRect) -> Bool {
        let tolerance: CGFloat = 8
        switch edge {
        case .left:
            return abs(frame.minX - visibleFrame.minX) <= tolerance || frame.midX <= visibleFrame.midX
        case .right:
            return abs(frame.maxX - visibleFrame.maxX) <= tolerance || frame.midX >= visibleFrame.midX
        case .top:
            return abs(frame.minY - visibleFrame.minY) <= tolerance || frame.midY <= visibleFrame.midY
        case .bottom:
            return abs(frame.maxY - visibleFrame.maxY) <= tolerance || frame.midY >= visibleFrame.midY
        }
    }
}

private extension CGRect {
    var area: CGFloat {
        max(0, width) * max(0, height)
    }
}
