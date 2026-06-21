import AppKit
import ApplicationServices
import Foundation

@MainActor
struct WindowManager {
    private enum CycleEdge: Hashable {
        case left
        case right
        case top
        case bottom
    }

    private enum FrameAnchor {
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
    }

    func perform(_ command: Command) throws {
        guard Self.requestAccessibilityPermissionIfNeeded() else {
            throw LauncherError.accessibilityPermissionRequired
        }

        guard let application = NSWorkspace.shared.frontmostApplication,
              let window = focusedWindow(for: application),
              let currentFrame = frame(of: window) else {
            return
        }

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
            targetFrame = Self.translatedFrame(currentFrame, from: visibleFrame, to: visibleFrames[targetIndex])
            targetAnchor = nil
            cycleKey = nil
            cycleFraction = nil
        case .previousDisplay:
            let targetIndex = (currentScreenIndex - 1 + screens.count) % screens.count
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

        let integralTargetFrame = targetFrame.integral
        try set(frame: integralTargetFrame, anchor: targetAnchor, for: window, application: application)
        if let cycleKey, let cycleFraction {
            Self.recordCycle(fraction: cycleFraction, for: cycleKey)
        }
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

    static func appleScriptBoundsList(for frame: CGRect) -> String {
        let frame = frame.integral
        return "{\(Int(frame.minX)), \(Int(frame.minY)), \(Int(frame.maxX)), \(Int(frame.maxY))}"
    }

    private func focusedWindow(for application: NSRunningApplication) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
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
        if application.bundleIdentifier == "com.google.Chrome" {
            try setChromeBounds(frame)
            return
        }

        try set(frame: frame, anchor: anchor, for: window)
    }

    private func setChromeBounds(_ frame: CGRect) throws {
        let source = """
        tell application id "com.google.Chrome"
            if (count of windows) > 0 then
                set bounds of front window to \(Self.appleScriptBoundsList(for: frame))
            end if
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if error != nil {
            throw LauncherError.accessibilityPermissionRequired
        }
    }

    private func setPosition(_ position: CGPoint, for window: AXUIElement) throws {
        var position = position
        guard let value = AXValueCreate(.cgPoint, &position) else { return }
        let status = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        if status != .success {
            throw LauncherError.accessibilityPermissionRequired
        }
    }

    private func setSize(_ size: CGSize, for window: AXUIElement) throws {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return }
        let status = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
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

        let integralFrame = actualFrame.integral
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
