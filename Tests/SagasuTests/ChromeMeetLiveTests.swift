import AppKit
import ApplicationServices
import Testing
@testable import Sagasu

@MainActor
@Test
func liveChromeMeetWindowCanBeMaximizedAndMovedRight() throws {
    guard ProcessInfo.processInfo.environment["SAGASU_LIVE_CHROME_MEET_TEST"] == "1" else {
        return
    }

    guard let chrome = NSWorkspace.shared.runningApplications.first(where: { application in
        guard application.bundleIdentifier == "com.google.Chrome" else { return false }
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        return chromeWindows(in: appElement).contains {
            title(of: $0).localizedCaseInsensitiveContains("Meet")
        }
    }) else {
        Issue.record("Chrome with a Meet window is not running")
        return
    }

    let appElement = AXUIElementCreateApplication(chrome.processIdentifier)
    guard let meetWindow = chromeWindows(in: appElement).first(where: {
        title(of: $0).localizedCaseInsensitiveContains("Meet")
    }) else {
        Issue.record("Meet Chrome window was not found")
        return
    }

    NSRunningApplication(processIdentifier: chrome.processIdentifier)?.activate(options: [])
    AXUIElementPerformAction(meetWindow, kAXRaiseAction as CFString)
    AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, meetWindow)

    let manager = WindowManager()
    try manager.perform(.maximize)
    let maximized = try #require(waitForStableFrame(of: meetWindow))

    try manager.perform(.rightHalf)
    let rightHalf = try #require(waitForStableFrame(of: meetWindow))

    print("liveChromeMeet maximized=\(maximized) rightHalf=\(rightHalf)")
    #expect(maximized.width >= rightHalf.width * 1.9)
    #expect(rightHalf.width < maximized.width)
    #expect(rightHalf.minX > maximized.minX)
    #expect(abs(rightHalf.maxX - maximized.maxX) <= 8)
}

private func chromeWindows(in appElement: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
          let windows = value as? [AXUIElement] else {
        return []
    }
    return windows
}

private func title(of window: AXUIElement) -> String {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value) == .success else {
        return ""
    }
    return value as? String ?? ""
}

private func frame(of window: AXUIElement) -> CGRect? {
    var positionValue: CFTypeRef?
    var sizeValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
          AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
          let positionValue,
          let sizeValue,
          CFGetTypeID(positionValue) == AXValueGetTypeID(),
          CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
        return nil
    }

    var position = CGPoint.zero
    var size = CGSize.zero
    AXValueGetValue((positionValue as! AXValue), .cgPoint, &position)
    AXValueGetValue((sizeValue as! AXValue), .cgSize, &size)
    return CGRect(origin: position, size: size)
}

private func waitForStableFrame(of window: AXUIElement) -> CGRect? {
    var previous = frame(of: window)
    for _ in 0..<8 {
        usleep(50_000)
        let current = frame(of: window)
        if current == previous {
            return current
        }
        previous = current
    }
    return previous
}
