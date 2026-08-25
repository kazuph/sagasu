import CoreGraphics
import Testing

@testable import Sagasu

@Test
func launcherEventTapReenablesAfterSystemDisablesIt() {
    #expect(LauncherHotKeyMonitor.shouldReenableEventTap(for: .tapDisabledByTimeout))
    #expect(LauncherHotKeyMonitor.shouldReenableEventTap(for: .tapDisabledByUserInput))
    #expect(LauncherHotKeyMonitor.shouldReenableEventTap(for: .keyDown) == false)
}
