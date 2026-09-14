// Run with `swift Scripts/verify-obails-window.swift` against /Applications/Sagasu.app.
// Sends the real window hotkeys to the running Obails app and checks AX geometry.
import AppKit
import ApplicationServices

func attribute(_ name: String, of element: AXUIElement) throws -> CFTypeRef {
    var value: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    guard status == .success, let value else {
        throw NSError(domain: "AXRead", code: Int(status.rawValue))
    }
    return value
}

func frame(of window: AXUIElement) throws -> CGRect {
    let position = try attribute(kAXPositionAttribute, of: window)
    let size = try attribute(kAXSizeAttribute, of: window)
    guard CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else {
        throw NSError(domain: "AXFrameType", code: 1)
    }
    var point = CGPoint.zero
    var dimensions = CGSize.zero
    AXValueGetValue(position as! AXValue, .cgPoint, &point)
    AXValueGetValue(size as! AXValue, .cgSize, &dimensions)
    return CGRect(origin: point, size: dimensions)
}

func matches(_ actual: CGRect, _ expected: CGRect) -> Bool {
    // Same point tolerance as WindowManager.frameSettleTolerance.
    zip([actual.minX, actual.minY, actual.width, actual.height],
        [expected.minX, expected.minY, expected.width, expected.height]).allSatisfy { abs($0 - $1) <= 6 }
}

func send(_ key: CGKeyCode) {
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down)!
        event.flags = [.maskCommand, .maskControl, .maskShift]
        event.post(tap: .cghidEventTap)
    }
}

guard AXIsProcessTrusted(),
      let application = NSRunningApplication.runningApplications(withBundleIdentifier: "com.kazuph.obails").first,
      NSRunningApplication.runningApplications(withBundleIdentifier: "com.kazuph.sagasu").contains(where: {
          $0.bundleURL?.path == "/Applications/Sagasu.app"
      }) else {
    fatalError("Running Obails, installed Sagasu, and Accessibility permission are required")
}
let app = AXUIElementCreateApplication(application.processIdentifier)
let rawWindow = try attribute(kAXFocusedWindowAttribute, of: app)
guard CFGetTypeID(rawWindow) == AXUIElementGetTypeID() else { fatalError("No focused window") }
let window = rawWindow as! AXUIElement
let originalMode = try attribute("AXEnhancedUserInterface", of: app) as! Bool
application.activate()
Thread.sleep(forTimeInterval: 0.3)
let original = try frame(of: window)
let primaryTop = NSScreen.screens[0].frame.maxY
let screens = NSScreen.screens.map { screen in
    let inset: CGFloat = screen.visibleFrame == screen.frame ? 31 : 0
    let visible = screen.visibleFrame
    return CGRect(x: visible.minX, y: primaryTop - visible.maxY + inset,
                  width: visible.width, height: max(120, visible.height - inset))
}
let screen = screens.max { lhs, rhs in
    let l = original.intersection(lhs), r = original.intersection(rhs)
    return l.width * l.height < r.width * r.height
}!
let checks: [(String, CGKeyCode, CGRect)] = [
    ("maximize", 36, screen),
    ("rightHalf", 37, CGRect(x: screen.midX, y: screen.minY, width: screen.width / 2, height: screen.height)),
    ("maximize", 36, screen),
    ("leftHalf", 4, CGRect(x: screen.minX, y: screen.minY, width: screen.width / 2, height: screen.height)),
    ("maximize", 36, screen),
    ("bottomHalf", 38, CGRect(x: screen.minX, y: screen.midY, width: screen.width, height: screen.height / 2)),
    ("maximize", 36, screen),
    ("topHalf", 40, CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: screen.height / 2))
]
var failures = 0
for round in 1...3 {
    for (name, key, expected) in checks {
        let started = Date()
        send(key)
        var elapsed: Int?
        // Observe for a full second, including frames that revert after an initial match.
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.05)
            if elapsed == nil, matches(try frame(of: window), expected) {
                elapsed = Int(Date().timeIntervalSince(started) * 1000)
            }
        }
        let actual = try frame(of: window)
        let mode = try attribute("AXEnhancedUserInterface", of: app) as! Bool
        let passed = matches(actual, expected) && mode == originalMode
        if !passed { failures += 1 }
        print("\(passed ? "PASS" : "FAIL") round=\(round) \(name) firstMatchMs=\(elapsed.map(String.init) ?? "none") expected=\(expected) actual=\(actual) enhancedUI=\(mode)")
    }
}
print("failures=\(failures) checks=\(checks.count * 3)")
exit(failures == 0 ? 0 : 1)
