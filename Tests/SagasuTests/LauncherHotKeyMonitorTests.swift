import CoreGraphics
import Testing

@testable import Sagasu

@Test
func launcherEventTapReenablesAfterSystemDisablesIt() {
    #expect(GlobalHotKeyMonitor.shouldReenableEventTap(for: .tapDisabledByTimeout))
    #expect(GlobalHotKeyMonitor.shouldReenableEventTap(for: .tapDisabledByUserInput))
    #expect(GlobalHotKeyMonitor.shouldReenableEventTap(for: .keyDown) == false)
}
