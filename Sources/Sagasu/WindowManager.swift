import AppKit
import ApplicationServices
import Foundation

@MainActor
struct WindowManager {
    enum Command {
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

        guard let window = focusedWindow(),
              let currentFrame = frame(of: window) else {
            return
        }

        let screens = NSScreen.screens
            .sorted { lhs, rhs in
                lhs.frame.minX < rhs.frame.minX
            }
        guard let currentScreenIndex = screens.firstIndex(where: { screen in
            axVisibleFrame(for: screen).intersects(currentFrame)
        }) ?? screens.firstIndex(where: { screen in
            axVisibleFrame(for: screen).contains(
                CGPoint(x: currentFrame.midX, y: currentFrame.midY)
            )
        }) else {
            return
        }

        let screen = screens[currentScreenIndex]
        let visibleFrame = axVisibleFrame(for: screen)
        let targetFrame: CGRect

        switch command {
        case .bottomHalf:
            let fraction = Self.nextCycleFraction(current: currentFrame.height / visibleFrame.height)
            targetFrame = CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.maxY - visibleFrame.height * fraction,
                width: visibleFrame.width,
                height: visibleFrame.height * fraction
            )
        case .centerThird:
            targetFrame = CGRect(
                x: visibleFrame.minX + visibleFrame.width / 3,
                y: visibleFrame.minY,
                width: visibleFrame.width / 3,
                height: visibleFrame.height
            )
        case .leftHalf:
            let fraction = Self.nextCycleFraction(current: currentFrame.width / visibleFrame.width)
            targetFrame = CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: visibleFrame.width * fraction,
                height: visibleFrame.height
            )
        case .maximize:
            targetFrame = visibleFrame
        case .nextDisplay:
            let targetIndex = (currentScreenIndex + 1) % screens.count
            targetFrame = translatedFrame(currentFrame, from: visibleFrame, to: axVisibleFrame(for: screens[targetIndex]))
        case .previousDisplay:
            let targetIndex = (currentScreenIndex - 1 + screens.count) % screens.count
            targetFrame = translatedFrame(currentFrame, from: visibleFrame, to: axVisibleFrame(for: screens[targetIndex]))
        case .rightHalf:
            let fraction = Self.nextCycleFraction(current: currentFrame.width / visibleFrame.width)
            let width = visibleFrame.width * fraction
            targetFrame = CGRect(
                x: visibleFrame.maxX - width,
                y: visibleFrame.minY,
                width: width,
                height: visibleFrame.height
            )
        case .topHalf:
            let fraction = Self.nextCycleFraction(current: currentFrame.height / visibleFrame.height)
            targetFrame = CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: visibleFrame.width,
                height: visibleFrame.height * fraction
            )
        }

        try set(frame: targetFrame.integral, for: window)
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
        let cycle: [CGFloat] = [
            1.0 / 2.0,
            1.0 / 3.0,
            1.0 / 4.0,
            2.0 / 3.0,
            3.0 / 4.0
        ]
        let tolerance: CGFloat = 0.035

        guard let currentIndex = cycle.firstIndex(where: { abs($0 - current) <= tolerance }) else {
            return cycle[0]
        }

        return cycle[(currentIndex + 1) % cycle.count]
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func focusedWindow() -> AXUIElement? {
        guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
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
        var position = frame.origin
        var size = frame.size
        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size) else {
            return
        }

        let positionStatus = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        let sizeStatus = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        if positionStatus != .success || sizeStatus != .success {
            throw LauncherError.accessibilityPermissionRequired
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

    private func axVisibleFrame(for screen: NSScreen) -> CGRect {
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        return CGRect(
            x: visibleFrame.minX,
            y: screenFrame.maxY - visibleFrame.maxY,
            width: visibleFrame.width,
            height: visibleFrame.height
        )
    }

    private func translatedFrame(_ frame: CGRect, from source: CGRect, to destination: CGRect) -> CGRect {
        let widthRatio = frame.width / max(source.width, 1)
        let heightRatio = frame.height / max(source.height, 1)
        let xRatio = (frame.minX - source.minX) / max(source.width, 1)
        let yRatio = (frame.minY - source.minY) / max(source.height, 1)

        let width = min(destination.width, max(120, destination.width * widthRatio))
        let height = min(destination.height, max(120, destination.height * heightRatio))
        let x = destination.minX + (destination.width - width) * xRatio
        let y = destination.minY + (destination.height - height) * yRatio

        return CGRect(x: x, y: y, width: width, height: height)
    }
}
