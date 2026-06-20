import Foundation
import Testing
@testable import Sagasu

@MainActor
@Test
func windowCycleAdvancesFromCurrentFraction() {
    #expect(WindowManager.nextCycleFraction(current: 1.0 / 2.0) == 1.0 / 3.0)
    #expect(WindowManager.nextCycleFraction(current: 1.0 / 3.0) == 1.0 / 4.0)
    #expect(WindowManager.nextCycleFraction(current: 1.0 / 4.0) == 2.0 / 3.0)
    #expect(WindowManager.nextCycleFraction(current: 2.0 / 3.0) == 3.0 / 4.0)
    #expect(WindowManager.nextCycleFraction(current: 3.0 / 4.0) == 1.0 / 2.0)
}

@MainActor
@Test
func windowCycleStartsAtHalfForUnknownCurrentFraction() {
    #expect(WindowManager.nextCycleFraction(current: 0.61) == 1.0 / 2.0)
}

@MainActor
@Test
func windowCycleToleratesIntegralPixelRounding() {
    #expect(WindowManager.nextCycleFraction(current: 0.501) == 1.0 / 3.0)
    #expect(WindowManager.nextCycleFraction(current: 0.668) == 3.0 / 4.0)
}

@MainActor
@Test
func windowCycleUsesPreviousAppliedFractionWhenAppAdjustsFrame() {
    #expect(
        WindowManager.nextCycleFraction(
            current: 0.61,
            previous: 1.0 / 4.0,
            isStillOnSameEdge: true
        ) == 2.0 / 3.0
    )
    #expect(
        WindowManager.nextCycleFraction(
            current: 0.61,
            previous: 2.0 / 3.0,
            isStillOnSameEdge: true
        ) == 3.0 / 4.0
    )
}

@MainActor
@Test
func windowCycleIgnoresPreviousFractionAfterManualMove() {
    #expect(
        WindowManager.nextCycleFraction(
            current: 0.61,
            previous: 2.0 / 3.0,
            isStillOnSameEdge: false
        ) == 1.0 / 2.0
    )
}

@MainActor
@Test
func axVisibleFrameUsesPrimaryScreenTopForStackedDisplays() {
    let primaryFrame = CGRect(x: 0, y: 0, width: 1470, height: 956)

    let mainVisible = WindowManager.axVisibleFrame(
        screenFrame: primaryFrame,
        visibleFrame: CGRect(x: 0, y: 0, width: 1470, height: 922),
        primaryScreenFrame: primaryFrame
    )
    #expect(mainVisible == CGRect(x: 0, y: 34, width: 1470, height: 922))

    let upperVisible = WindowManager.axVisibleFrame(
        screenFrame: CGRect(x: -1090, y: 956, width: 2560, height: 1440),
        visibleFrame: CGRect(x: -1090, y: 956, width: 2560, height: 1440),
        primaryScreenFrame: primaryFrame
    )
    #expect(upperVisible == CGRect(x: -1090, y: -1440, width: 2560, height: 1440))

    let topVisible = WindowManager.axVisibleFrame(
        screenFrame: CGRect(x: -1090, y: 2396, width: 2560, height: 1080),
        visibleFrame: CGRect(x: -1090, y: 2396, width: 2560, height: 1080),
        primaryScreenFrame: primaryFrame
    )
    #expect(topVisible == CGRect(x: -1090, y: -2520, width: 2560, height: 1080))
}

@MainActor
@Test
func bestScreenIndexUsesLargestIntersection() {
    let visibleFrames = [
        CGRect(x: 0, y: 0, width: 1000, height: 800),
        CGRect(x: 900, y: 0, width: 1000, height: 800)
    ]
    let mostlySecondScreen = CGRect(x: 880, y: 100, width: 800, height: 500)

    #expect(WindowManager.bestScreenIndex(for: mostlySecondScreen, in: visibleFrames) == 1)
}
